import Foundation

/// Google Gemini API connector for LLM interactions
class GeminiConnector: LLMProviderProtocol {
    let providerType: LLMProvider = .gemini
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
                        print("Gemini API error (\(httpResponse.statusCode)): \(errorMessage)")
                        throw LLMProviderError.apiError(errorMessage)
                    }
                    
                    // Parse response
                    let responseText = try parseResponse(data)
                    
                    // Gemini doesn't support streaming in this implementation, so yield complete response
                    continuation.yield(responseText)
                    continuation.finish()
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func validateConfiguration(_ agent: LLMAgent) -> Bool {
        let supportedModels = ["gemini-pro", "gemini-pro-vision", "gemini-1.5-pro", "gemini-1.5-flash"]
        return supportedModels.contains(agent.model)
    }
    
    func estimateTokens(_ text: String) -> Int {
        // Rough estimation: ~4 characters per token
        return text.count / 4
    }
    
    func getContextWindowSize(for model: String) -> Int {
        switch model.lowercased() {
        case "gemini-pro":
            return 30720
        case "gemini-pro-vision":
            return 12288
        case "gemini-1.5-pro":
            return 1048576 // 1M tokens
        case "gemini-1.5-flash":
            return 1048576 // 1M tokens
        default:
            return 30720
        }
    }
    
    // MARK: - Private Methods
    
    private func buildRequest(
        context: LLMContext,
        agent: LLMAgent,
        apiKey: String
    ) throws -> URLRequest {
        
        let baseURL = agent.provider.baseURL
        let url = URL(string: "\(baseURL)/models/\(agent.model):generateContent?key=\(apiKey)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build conversation parts
        var parts: [[String: Any]] = []
        
        // Add system prompt if available
        if !context.systemPrompt.isEmpty {
            parts.append(["text": context.systemPrompt])
        }
        
        // Add conversation history
        for message in context.conversationHistory.suffix(20) { // Limit to recent messages
            switch message.sender {
            case .human, .llm:
                parts.append(["text": message.content])
            case .system:
                continue // Skip system messages
            }
        }
        
        // Create request body
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": parts
                ]
            ],
            "generationConfig": [
                "temperature": agent.temperature,
                "maxOutputTokens": min(agent.maxTokens, 8192),
                "topP": 0.8,
                "topK": 10
            ],
            "safetySettings": [
                [
                    "category": "HARM_CATEGORY_HARASSMENT",
                    "threshold": "BLOCK_MEDIUM_AND_ABOVE"
                ],
                [
                    "category": "HARM_CATEGORY_HATE_SPEECH",
                    "threshold": "BLOCK_MEDIUM_AND_ABOVE"
                ],
                [
                    "category": "HARM_CATEGORY_SEXUALLY_EXPLICIT",
                    "threshold": "BLOCK_MEDIUM_AND_ABOVE"
                ],
                [
                    "category": "HARM_CATEGORY_DANGEROUS_CONTENT",
                    "threshold": "BLOCK_MEDIUM_AND_ABOVE"
                ]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        return request
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
        
        // Parse successful response
        guard let candidates = jsonObject["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw LLMProviderError.invalidResponse
        }
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}