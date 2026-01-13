import Foundation

/// Custom HTTP endpoint connector for LLM interactions
class CustomConnector: LLMProviderProtocol {
    let providerType: LLMProvider = .custom
    let supportsStreaming: Bool = false
    
    // MARK: - API Configuration
    
    private let session = URLSession.shared
    
    // MARK: - LLMProviderProtocol Implementation
    
    func generateResponse(
        context: LLMContext,
        agent: LLMAgent,
        apiKey: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try buildRequest(context: context, agent: agent, apiKey: apiKey)
                    
                    let (data, response) = try await session.data(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw LLMProviderError.networkError(URLError(.badServerResponse))
                    }
                    
                    guard httpResponse.statusCode == 200 else {
                        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                        print("Custom API error (\(httpResponse.statusCode)): \(errorMessage)")
                        throw LLMProviderError.apiError(errorMessage)
                    }
                    
                    // Parse response
                    let responseText = try parseResponse(data, agent: agent)
                    
                    // Custom endpoints return complete response
                    continuation.yield(responseText)
                    continuation.finish()
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func validateConfiguration(_ agent: LLMAgent) -> Bool {
        // For custom endpoints, we'll be permissive
        return !agent.model.isEmpty
    }
    
    func estimateTokens(_ text: String) -> Int {
        // Rough estimation: ~4 characters per token
        return text.count / 4
    }
    
    func getContextWindowSize(for model: String) -> Int {
        // Default context window for custom endpoints
        // This should be configurable in a real implementation
        return 4096
    }
    
    // MARK: - Private Methods
    
    private func buildRequest(
        context: LLMContext,
        agent: LLMAgent,
        apiKey: String
    ) throws -> URLRequest {
        
        // For custom endpoints, we'll try to detect the format based on the model name
        // or use a generic OpenAI-compatible format
        
        guard let baseURL = getCustomEndpoint(for: agent) else {
            throw LLMProviderError.invalidConfiguration
        }
        
        let url = URL(string: baseURL)!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add authorization if API key is provided
        if !apiKey.isEmpty {
            if apiKey.hasPrefix("Bearer ") {
                request.setValue(apiKey, forHTTPHeaderField: "Authorization")
            } else {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        }
        
        // Build request body based on detected format
        let requestBody = try buildRequestBody(context: context, agent: agent)
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        return request
    }
    
    private func getCustomEndpoint(for agent: LLMAgent) -> String? {
        // This would typically be configured by the user
        // For now, we'll use some common patterns
        
        if agent.model.contains("localhost") || agent.model.contains("127.0.0.1") {
            return agent.model
        }
        
        if agent.model.hasPrefix("http://") || agent.model.hasPrefix("https://") {
            return agent.model
        }
        
        // Default patterns for common self-hosted solutions
        if agent.model.contains("text-generation-webui") {
            return "http://localhost:5000/api/v1/chat/completions"
        }
        
        if agent.model.contains("koboldcpp") {
            return "http://localhost:5001/api/v1/chat/completions"
        }
        
        if agent.model.contains("oobabooga") {
            return "http://localhost:5000/v1/chat/completions"
        }
        
        // Fallback: assume it's an OpenAI-compatible endpoint
        return "http://localhost:8000/v1/chat/completions"
    }
    
    private func buildRequestBody(context: LLMContext, agent: LLMAgent) throws -> [String: Any] {
        // Build messages array (OpenAI-compatible format)
        var messages: [[String: Any]] = []
        
        // Add system prompt if available
        if !context.systemPrompt.isEmpty {
            messages.append([
                "role": "system",
                "content": context.systemPrompt
            ])
        }
        
        // Add conversation history
        for message in context.conversationHistory.suffix(20) { // Limit to recent messages
            let role: String
            switch message.sender {
            case .human:
                role = "user"
            case .llm:
                role = "assistant"
            case .system:
                continue // Skip system messages
            }
            
            messages.append([
                "role": role,
                "content": message.content
            ])
        }
        
        // Create request body (OpenAI-compatible format)
        let requestBody: [String: Any] = [
            "model": extractModelName(from: agent.model),
            "messages": messages,
            "temperature": agent.temperature,
            "max_tokens": min(agent.maxTokens, 4096),
            "top_p": 1.0,
            "frequency_penalty": 0.0,
            "presence_penalty": 0.0,
            "stream": false
        ]
        
        return requestBody
    }
    
    private func extractModelName(from modelString: String) -> String {
        // Extract model name from URL or path
        if modelString.contains("/") {
            return modelString.components(separatedBy: "/").last ?? modelString
        }
        return modelString
    }
    
    private func parseResponse(_ data: Data, agent: LLMAgent) throws -> String {
        // Try multiple response formats
        
        // Try OpenAI format first
        if let openAIResponse = try? parseOpenAIFormat(data) {
            return openAIResponse
        }
        
        // Try simple text response
        if let textResponse = String(data: data, encoding: .utf8),
           !textResponse.isEmpty {
            return textResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Try generic JSON response
        if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            
            // Check for common response fields
            if let text = jsonObject["text"] as? String {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            if let response = jsonObject["response"] as? String {
                return response.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            if let content = jsonObject["content"] as? String {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            if let output = jsonObject["output"] as? String {
                return output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            // Check for error
            if let error = jsonObject["error"] as? String {
                throw LLMProviderError.apiError(error)
            }
        }
        
        throw LLMProviderError.invalidResponse
    }
    
    private func parseOpenAIFormat(_ data: Data) throws -> String {
        guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMProviderError.invalidResponse
        }
        
        // Check for error
        if let error = jsonObject["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw LLMProviderError.apiError(message)
        }
        
        // Parse successful response (OpenAI format)
        guard let choices = jsonObject["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMProviderError.invalidResponse
        }
        
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}