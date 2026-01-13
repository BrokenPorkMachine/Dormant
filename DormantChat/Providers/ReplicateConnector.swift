import Foundation

/// Replicate API connector for LLM interactions
class ReplicateConnector: LLMProviderProtocol {
    let providerType: LLMProvider = .replicate
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
                    // Replicate has a different flow: create prediction, then poll for results
                    let predictionId = try await createPrediction(context: context, agent: agent, apiKey: apiKey)
                    let responseText = try await pollPrediction(predictionId: predictionId, apiKey: apiKey)
                    
                    continuation.yield(responseText)
                    continuation.finish()
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func validateConfiguration(_ agent: LLMAgent) -> Bool {
        let supportedModels = [
            "meta/llama-2-70b-chat",
            "mistralai/mixtral-8x7b-instruct-v0.1",
            "meta/codellama-34b-instruct",
            "meta/llama-2-13b-chat",
            "meta/llama-2-7b-chat"
        ]
        return supportedModels.contains(agent.model) || agent.model.contains("/")
    }
    
    func estimateTokens(_ text: String) -> Int {
        // Rough estimation: ~4 characters per token
        return text.count / 4
    }
    
    func getContextWindowSize(for model: String) -> Int {
        switch model.lowercased() {
        case let model where model.contains("llama-2-70b"):
            return 4096
        case let model where model.contains("mixtral"):
            return 32768
        case let model where model.contains("codellama"):
            return 16384
        default:
            return 4096
        }
    }
    
    // MARK: - Private Methods
    
    private func createPrediction(
        context: LLMContext,
        agent: LLMAgent,
        apiKey: String
    ) async throws -> String {
        
        let baseURL = agent.provider.baseURL
        let url = URL(string: "\(baseURL)/predictions")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build the prompt
        let prompt = buildPrompt(from: context, agent: agent)
        
        // Create request body
        let requestBody: [String: Any] = [
            "version": getModelVersion(for: agent.model),
            "input": [
                "prompt": prompt,
                "temperature": agent.temperature,
                "max_new_tokens": min(agent.maxTokens, 4096),
                "top_p": 1.0,
                "repetition_penalty": 1.0
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.networkError(URLError(.badServerResponse))
        }
        
        guard httpResponse.statusCode == 201 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("Replicate API error (\(httpResponse.statusCode)): \(errorMessage)")
            throw LLMProviderError.apiError(errorMessage)
        }
        
        guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let predictionId = jsonObject["id"] as? String else {
            throw LLMProviderError.invalidResponse
        }
        
        return predictionId
    }
    
    private func pollPrediction(predictionId: String, apiKey: String) async throws -> String {
        let baseURL = LLMProvider.replicate.baseURL
        let url = URL(string: "\(baseURL)/predictions/\(predictionId)")!
        
        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // Poll until completion (with timeout)
        let maxAttempts = 60 // 5 minutes max
        var attempts = 0
        
        while attempts < maxAttempts {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw LLMProviderError.networkError(URLError(.badServerResponse))
            }
            
            guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = jsonObject["status"] as? String else {
                throw LLMProviderError.invalidResponse
            }
            
            switch status {
            case "succeeded":
                if let output = jsonObject["output"] as? [String] {
                    return output.joined(separator: "").trimmingCharacters(in: .whitespacesAndNewlines)
                } else if let output = jsonObject["output"] as? String {
                    return output.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    throw LLMProviderError.invalidResponse
                }
                
            case "failed":
                let error = jsonObject["error"] as? String ?? "Prediction failed"
                throw LLMProviderError.apiError(error)
                
            case "canceled":
                throw LLMProviderError.apiError("Prediction was canceled")
                
            default:
                // Still processing, wait and retry
                try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                attempts += 1
            }
        }
        
        throw LLMProviderError.apiError("Prediction timed out")
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
    
    private func getModelVersion(for model: String) -> String {
        // These would need to be updated with actual version hashes from Replicate
        switch model {
        case "meta/llama-2-70b-chat":
            return "02e509c789964a7ea8736978a43525956ef40397be9033abf9fd2badfe68c9e3"
        case "mistralai/mixtral-8x7b-instruct-v0.1":
            return "gryphe/mythomax-l2-13b:df7690f1994d94e96ad9d568eac121aecf50684a0b0963b25a41cc40061269e5"
        case "meta/codellama-34b-instruct":
            return "1bfb924a5f22f15b2eb2b7d3b4a663de4c17b3e8b4e6b8c8d5e5f5e5f5e5f5e5"
        default:
            return "latest" // Fallback
        }
    }
}