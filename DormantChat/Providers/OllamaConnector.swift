import Foundation

/// Ollama local API connector for LLM interactions
class OllamaConnector: LLMProviderProtocol {
    let providerType: LLMProvider = .ollama
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
                        print("Ollama API error (\(httpResponse.statusCode)): \(errorMessage)")
                        
                        if httpResponse.statusCode == 404 {
                            throw LLMProviderError.apiError("Model '\(agent.model)' not found. Please pull the model first with: ollama pull \(agent.model)")
                        }
                        
                        throw LLMProviderError.apiError(errorMessage)
                    }
                    
                    // Parse response
                    let responseText = try parseResponse(data)
                    
                    // Ollama returns complete response
                    continuation.yield(responseText)
                    continuation.finish()
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func validateConfiguration(_ agent: LLMAgent) -> Bool {
        // Ollama supports many models, so we'll be permissive
        let commonModels = ["llama2", "codellama", "mistral", "llama3", "phi3", "gemma", "qwen", "vicuna", "orca-mini"]
        return commonModels.contains(agent.model) || agent.model.contains(":")
    }
    
    func estimateTokens(_ text: String) -> Int {
        // Rough estimation: ~4 characters per token
        return text.count / 4
    }
    
    func getContextWindowSize(for model: String) -> Int {
        switch model.lowercased() {
        case "llama2":
            return 4096
        case "codellama":
            return 16384
        case "mistral":
            return 8192
        case "llama3":
            return 8192
        case "phi3":
            return 4096
        case "gemma":
            return 8192
        default:
            return 4096
        }
    }
    
    // MARK: - Private Methods
    
    private func buildRequest(
        context: LLMContext,
        agent: LLMAgent,
        apiKey: String
    ) throws -> URLRequest {
        
        let baseURL = agent.provider.baseURL
        let url = URL(string: "\(baseURL)/generate")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120 // Longer timeout for local processing
        
        // Build the prompt
        let prompt = buildPrompt(from: context, agent: agent)
        
        // Create request body
        let requestBody: [String: Any] = [
            "model": agent.model,
            "prompt": prompt,
            "stream": false,
            "options": [
                "temperature": agent.temperature,
                "num_predict": min(agent.maxTokens, 4096),
                "top_p": 0.9,
                "top_k": 40,
                "repeat_penalty": 1.1
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        return request
    }
    
    private func buildPrompt(from context: LLMContext, agent: LLMAgent) -> String {
        var prompt = ""
        
        // Add system prompt if available
        if !context.systemPrompt.isEmpty {
            prompt += "System: \(context.systemPrompt)\n\n"
        }
        
        // Add conversation history
        for message in context.conversationHistory.suffix(15) { // Limit to recent messages
            let senderName: String
            switch message.sender {
            case .human(_, let username):
                senderName = username
            case .llm(_, let agentName, _):
                senderName = agentName
            case .system:
                continue // Skip system messages
            }
            
            prompt += "\(senderName): \(message.content)\n"
        }
        
        // Add agent prompt
        prompt += "\(agent.name): "
        
        return prompt
    }
    
    private func parseResponse(_ data: Data) throws -> String {
        guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMProviderError.invalidResponse
        }
        
        // Check for error
        if let error = jsonObject["error"] as? String {
            throw LLMProviderError.apiError(error)
        }
        
        // Parse successful response
        guard let response = jsonObject["response"] as? String else {
            throw LLMProviderError.invalidResponse
        }
        
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Utility Methods
    
    /// Check if Ollama is running and accessible
    func checkOllamaStatus() async -> Bool {
        do {
            let url = URL(string: "http://localhost:11434/api/tags")!
            let (_, response) = try await session.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            return false
        }
    }
    
    /// Get list of available models from Ollama
    func getAvailableModels() async throws -> [String] {
        let url = URL(string: "http://localhost:11434/api/tags")!
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw LLMProviderError.networkError(URLError(.badServerResponse))
        }
        
        guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = jsonObject["models"] as? [[String: Any]] else {
            throw LLMProviderError.invalidResponse
        }
        
        return models.compactMap { model in
            model["name"] as? String
        }
    }
}