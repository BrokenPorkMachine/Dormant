import Foundation

/// OpenAI API connector with streaming support
class OpenAIConnector: LLMProviderProtocol {
    let providerType: LLMProvider = .openai
    let supportsStreaming: Bool = true
    
    private let baseURL = "https://api.openai.com/v1"
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
                               let choices = json["choices"] as? [[String: Any]],
                               let firstChoice = choices.first,
                               let delta = firstChoice["delta"] as? [String: Any],
                               let content = delta["content"] as? String {
                                continuation.yield(content)
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
        guard agent.provider == .openai else { return false }
        guard !agent.name.isEmpty else { return false }
        guard !agent.model.isEmpty else { return false }
        guard agent.temperature >= 0.0 && agent.temperature <= 2.0 else { return false }
        guard agent.maxTokens > 0 && agent.maxTokens <= 4096 else { return false }
        
        let validModels = ["gpt-4", "gpt-4-turbo", "gpt-4-turbo-preview", "gpt-3.5-turbo", "gpt-3.5-turbo-16k"]
        return validModels.contains(agent.model)
    }
    
    func estimateTokens(_ text: String) -> Int {
        // Rough estimation: ~4 characters per token for English text
        return max(1, text.count / 4)
    }
    
    func getContextWindowSize(for model: String) -> Int {
        switch model {
        case "gpt-4", "gpt-4-turbo", "gpt-4-turbo-preview":
            return 128000
        case "gpt-3.5-turbo":
            return 4096
        case "gpt-3.5-turbo-16k":
            return 16384
        default:
            return 4096
        }
    }
    
    private func buildRequest(context: LLMContext, agent: LLMAgent, apiKey: String) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw LLMProviderError.invalidConfiguration
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build messages array
        var messages: [[String: Any]] = []
        
        // Add system message if personality is provided
        if !context.systemPrompt.isEmpty {
            messages.append([
                "role": "system",
                "content": context.systemPrompt
            ])
        }
        
        // Add conversation history
        for message in context.conversationHistory {
            let role: String
            switch message.sender {
            case .human:
                role = "user"
            case .llm:
                role = "assistant"
            case .system:
                role = "system"
            }
            
            messages.append([
                "role": role,
                "content": message.content
            ])
        }
        
        let requestBody: [String: Any] = [
            "model": agent.model,
            "messages": messages,
            "temperature": agent.temperature,
            "max_tokens": agent.maxTokens,
            "stream": true
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        return request
    }
}