import Foundation

/// Anthropic API connector with streaming support
class AnthropicConnector: LLMProviderProtocol {
    let providerType: LLMProvider = .anthropic
    let supportsStreaming: Bool = true
    
    private let baseURL = "https://api.anthropic.com/v1"
    private let session = URLSession.shared
    
    func generateResponse(
        context: LLMContext,
        agent: LLMAgent,
        apiKey: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        
        guard validateConfiguration(agent) else {
            throw LLMProviderError.invalidConfiguration
        }
        
        let request = try buildRequest(context: context, agent: agent, apiKey: apiKey)
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (data, response) = try await session.data(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: LLMProviderError.networkError(URLError(.badServerResponse)))
                        return
                    }
                    
                    if httpResponse.statusCode == 401 {
                        continuation.finish(throwing: LLMProviderError.invalidAPIKey)
                        return
                    }
                    
                    if httpResponse.statusCode == 429 {
                        continuation.finish(throwing: LLMProviderError.rateLimitExceeded)
                        return
                    }
                    
                    if httpResponse.statusCode >= 400 {
                        continuation.finish(throwing: LLMProviderError.providerUnavailable)
                        return
                    }
                    
                    // Parse streaming response
                    let dataString = String(data: data, encoding: .utf8) ?? ""
                    let lines = dataString.components(separatedBy: .newlines)
                    
                    for line in lines {
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))
                            
                            if jsonString.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                                continuation.finish()
                                return
                            }
                            
                            if let data = jsonString.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let type = json["type"] as? String,
                               type == "content_block_delta",
                               let delta = json["delta"] as? [String: Any],
                               let text = delta["text"] as? String {
                                continuation.yield(text)
                            }
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: LLMProviderError.networkError(error))
                }
            }
        }
    }
    
    func validateConfiguration(_ agent: LLMAgent) -> Bool {
        guard agent.provider == .anthropic else { return false }
        guard !agent.name.isEmpty else { return false }
        guard !agent.model.isEmpty else { return false }
        guard agent.temperature >= 0.0 && agent.temperature <= 1.0 else { return false }
        guard agent.maxTokens > 0 && agent.maxTokens <= 4096 else { return false }
        
        let validModels = ["claude-3-opus-20240229", "claude-3-sonnet-20240229", "claude-3-haiku-20240307", "claude-3-opus", "claude-3-sonnet", "claude-3-haiku"]
        return validModels.contains(agent.model)
    }
    
    func estimateTokens(_ text: String) -> Int {
        // Rough estimation: ~4 characters per token for English text
        return max(1, text.count / 4)
    }
    
    func getContextWindowSize(for model: String) -> Int {
        switch model {
        case "claude-3-opus-20240229", "claude-3-opus":
            return 200000
        case "claude-3-sonnet-20240229", "claude-3-sonnet":
            return 200000
        case "claude-3-haiku-20240307", "claude-3-haiku":
            return 200000
        default:
            return 200000
        }
    }
    
    private func buildRequest(context: LLMContext, agent: LLMAgent, apiKey: String) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/messages") else {
            throw LLMProviderError.invalidConfiguration
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        // Build messages array
        var messages: [[String: Any]] = []
        
        // Add conversation history (Anthropic doesn't use system messages in the messages array)
        for message in context.conversationHistory {
            let role: String
            switch message.sender {
            case .human:
                role = "user"
            case .llm:
                role = "assistant"
            case .system:
                continue // Skip system messages in conversation history
            }
            
            messages.append([
                "role": role,
                "content": message.content
            ])
        }
        
        var requestBody: [String: Any] = [
            "model": agent.model,
            "messages": messages,
            "max_tokens": agent.maxTokens,
            "stream": true
        ]
        
        // Add system prompt if provided
        if !context.systemPrompt.isEmpty {
            requestBody["system"] = context.systemPrompt
        }
        
        // Add temperature if not default
        if agent.temperature != 0.7 {
            requestBody["temperature"] = agent.temperature
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        return request
    }
}