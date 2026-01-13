import Foundation

/// Cohere API connector for LLM interactions
class CohereConnector: LLMProviderProtocol {
    let providerType: LLMProvider = .cohere
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
                        print("Cohere API error (\(httpResponse.statusCode)): \(errorMessage)")
                        throw LLMProviderError.apiError(errorMessage)
                    }
                    
                    // Parse response
                    let responseText = try parseResponse(data)
                    
                    // Cohere doesn't support streaming in this implementation
                    continuation.yield(responseText)
                    continuation.finish()
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func validateConfiguration(_ agent: LLMAgent) -> Bool {
        let supportedModels = ["command", "command-light", "command-nightly", "command-r", "command-r-plus"]
        return supportedModels.contains(agent.model)
    }
    
    func estimateTokens(_ text: String) -> Int {
        // Rough estimation: ~4 characters per token
        return text.count / 4
    }
    
    func getContextWindowSize(for model: String) -> Int {
        switch model.lowercased() {
        case "command", "command-nightly":
            return 4096
        case "command-light":
            return 4096
        case "command-r":
            return 128000
        case "command-r-plus":
            return 128000
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
        let url = URL(string: "\(baseURL)/chat")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build chat history
        var chatHistory: [[String: Any]] = []
        
        // Add conversation history
        for message in context.conversationHistory.suffix(20) { // Limit to recent messages
            let role: String
            switch message.sender {
            case .human:
                role = "USER"
            case .llm:
                role = "CHATBOT"
            case .system:
                continue // Skip system messages
            }
            
            chatHistory.append([
                "role": role,
                "message": message.content
            ])
        }
        
        // Build the final user message (last message should be from user)
        let lastUserMessage = context.conversationHistory.last?.content ?? "Hello"
        
        // Create request body
        var requestBody: [String: Any] = [
            "model": agent.model,
            "message": lastUserMessage,
            "temperature": agent.temperature,
            "max_tokens": min(agent.maxTokens, 4000),
            "k": 0,
            "p": 0.75,
            "frequency_penalty": 0.0,
            "presence_penalty": 0.0,
            "stream": false
        ]
        
        // Add chat history if available
        if !chatHistory.isEmpty {
            requestBody["chat_history"] = chatHistory
        }
        
        // Add system prompt as preamble if available
        if !context.systemPrompt.isEmpty {
            requestBody["preamble"] = context.systemPrompt
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        return request
    }
    
    private func parseResponse(_ data: Data) throws -> String {
        guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMProviderError.invalidResponse
        }
        
        // Check for error
        if let message = jsonObject["message"] as? String,
           message.contains("error") || message.contains("invalid") {
            throw LLMProviderError.apiError(message)
        }
        
        // Parse successful response
        if let text = jsonObject["text"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Alternative response format
        if let generations = jsonObject["generations"] as? [[String: Any]],
           let firstGeneration = generations.first,
           let text = firstGeneration["text"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        throw LLMProviderError.invalidResponse
    }
}