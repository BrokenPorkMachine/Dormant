import Foundation

/// Hugging Face API connector for LLM interactions
class HuggingFaceConnector: LLMProviderProtocol {
    let providerType: LLMProvider = .huggingface
    let supportsStreaming: Bool = false
    
    // MARK: - API Configuration
    
    private let baseURL = "https://api-inference.huggingface.co/models"
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
                        print("Hugging Face API error (\(httpResponse.statusCode)): \(errorMessage)")
                        throw LLMProviderError.apiError(errorMessage)
                    }
                    
                    // Parse response
                    let responseText = try parseResponse(data)
                    
                    // Hugging Face doesn't support streaming, so we yield the complete response
                    continuation.yield(responseText)
                    continuation.finish()
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func validateConfiguration(_ agent: LLMAgent) -> Bool {
        // Check if model is supported
        let supportedModels = [
            "microsoft/DialoGPT-medium",
            "microsoft/DialoGPT-large",
            "facebook/blenderbot-400M-distill",
            "facebook/blenderbot-1B-distill",
            "microsoft/DialoGPT-small",
            "EleutherAI/gpt-neo-2.7B",
            "EleutherAI/gpt-j-6B"
        ]
        
        return supportedModels.contains(agent.model) || agent.model.contains("/")
    }
    
    func estimateTokens(_ text: String) -> Int {
        // Rough estimation: ~4 characters per token
        return text.count / 4
    }
    
    func getContextWindowSize(for model: String) -> Int {
        switch model.lowercased() {
        case let model where model.contains("gpt-j"):
            return 2048
        case let model where model.contains("dialogpt"):
            return 1024
        case let model where model.contains("blenderbot"):
            return 512
        default:
            return 2048
        }
    }
    
    // MARK: - Private Methods
    
    private func buildRequest(
        context: LLMContext,
        agent: LLMAgent,
        apiKey: String
    ) throws -> URLRequest {
        
        let modelURL = URL(string: "\(baseURL)/\(agent.model)")!
        var request = URLRequest(url: modelURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build conversation context
        let conversationText = buildConversationText(from: context, agent: agent)
        
        // Create request body based on model type
        let requestBody: [String: Any]
        
        if agent.model.contains("DialoGPT") {
            // DialoGPT format
            requestBody = [
                "inputs": conversationText,
                "parameters": [
                    "max_length": min(agent.maxTokens, 1000),
                    "temperature": agent.temperature,
                    "do_sample": true,
                    "pad_token_id": 50256
                ],
                "options": [
                    "wait_for_model": true
                ]
            ]
        } else if agent.model.contains("blenderbot") {
            // BlenderBot format
            requestBody = [
                "inputs": conversationText,
                "parameters": [
                    "max_length": min(agent.maxTokens, 512),
                    "temperature": agent.temperature,
                    "do_sample": true
                ],
                "options": [
                    "wait_for_model": true
                ]
            ]
        } else {
            // Generic text generation format
            requestBody = [
                "inputs": conversationText,
                "parameters": [
                    "max_new_tokens": min(agent.maxTokens, 1000),
                    "temperature": agent.temperature,
                    "do_sample": true,
                    "return_full_text": false
                ],
                "options": [
                    "wait_for_model": true
                ]
            ]
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        return request
    }
    
    private func buildConversationText(from context: LLMContext, agent: LLMAgent) -> String {
        var conversationText = ""
        
        // Add system prompt if available
        if !context.systemPrompt.isEmpty {
            conversationText += "System: \(context.systemPrompt)\n\n"
        }
        
        // Add conversation history
        for message in context.conversationHistory.suffix(10) { // Limit to recent messages
            let senderName: String
            switch message.sender {
            case .human(_, let username):
                senderName = username
            case .llm(_, let agentName, _):
                senderName = agentName
            case .system:
                continue // Skip system messages
            }
            
            conversationText += "\(senderName): \(message.content)\n"
        }
        
        // Add agent prompt
        conversationText += "\(agent.name):"
        
        return conversationText
    }
    
    private func parseResponse(_ data: Data) throws -> String {
        // Try to parse as array first (most common format)
        if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let firstResult = jsonArray.first,
           let generatedText = firstResult["generated_text"] as? String {
            
            // Clean up the response by removing the input prompt
            let cleanedText = cleanGeneratedText(generatedText)
            return cleanedText.isEmpty ? "I'm sorry, I couldn't generate a response." : cleanedText
        }
        
        // Try to parse as single object
        if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let generatedText = jsonObject["generated_text"] as? String {
            
            let cleanedText = cleanGeneratedText(generatedText)
            return cleanedText.isEmpty ? "I'm sorry, I couldn't generate a response." : cleanedText
        }
        
        // Try to parse error response
        if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = jsonObject["error"] as? String {
            throw LLMProviderError.apiError(error)
        }
        
        // Fallback: return raw text if JSON parsing fails
        let rawText = String(data: data, encoding: .utf8) ?? ""
        if !rawText.isEmpty {
            return rawText
        }
        
        throw LLMProviderError.invalidResponse
    }
    
    private func cleanGeneratedText(_ text: String) -> String {
        // Remove common artifacts and clean up the response
        var cleaned = text
        
        // Remove the input prompt if it's repeated
        if let colonIndex = cleaned.firstIndex(of: ":") {
            let afterColon = String(cleaned[cleaned.index(after: colonIndex)...])
            if !afterColon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                cleaned = afterColon
            }
        }
        
        // Clean up whitespace and newlines
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove any remaining conversation markers
        let conversationMarkers = ["Human:", "Assistant:", "User:", "Bot:", "AI:"]
        for marker in conversationMarkers {
            if cleaned.hasPrefix(marker) {
                cleaned = String(cleaned.dropFirst(marker.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return cleaned
    }
}