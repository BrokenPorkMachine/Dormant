import Foundation

/// Groq API connector for LLM interactions (ultra-fast inference)
class GroqConnector: LLMProviderProtocol {
    let providerType: LLMProvider = .groq
    let supportsStreaming: Bool = true
    
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
                        print("Groq API error (\(httpResponse.statusCode)): \(errorMessage)")
                        throw LLMProviderError.apiError(errorMessage)
                    }
                    
                    // Parse response
                    let responseText = try parseResponse(data)
                    
                    // Groq uses OpenAI-compatible format
                    continuation.yield(responseText)
                    continuation.finish()
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func validateConfiguration(_ agent: LLMAgent) -> Bool {
        let supportedModels = ["llama3-8b-8192", "llama3-70b-8192", "mixtral-8x7b-32768", "gemma-7b-it"]
        return supportedModels.contains(agent.model)
    }
    
    func estimateTokens(_ text: String) -> Int {
        // Rough estimation: ~4 characters per token
        return text.count / 4
    }
    
    func getContextWindowSize(for model: String) -> Int {
        switch model.lowercased() {
        case "llama3-8b-8192":
            return 8192
        case "llama3-70b-8192":
            return 8192
        case "mixtral-8x7b-32768":
            return 32768
        case "gemma-7b-it":
            return 8192
        default:
            return 8192
        }
    }
    
    // MARK: - Private Methods
    
    private func buildRequest(
        context: LLMContext,
        agent: LLMAgent,
        apiKey: String
    ) throws -> URLRequest {
        
        let baseURL = agent.provider.baseURL
        let url = URL(string: "\(baseURL)/chat/completions")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build messages array
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
            "messages": messages,
            "model": agent.model,
            "temperature": agent.temperature,
            "max_tokens": min(agent.maxTokens, getMaxTokensForModel(agent.model)),
            "top_p": 1.0,
            "stream": false
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        return request
    }
    
    private func getMaxTokensForModel(_ model: String) -> Int {
        switch model {
        case "llama3-8b-8192", "llama3-70b-8192":
            return 8192
        case "mixtral-8x7b-32768":
            return 32768
        case "gemma-7b-it":
            return 8192
        default:
            return 4096
        }
    }
    
    private func parseResponse(_ data: Data) throws -> String {
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