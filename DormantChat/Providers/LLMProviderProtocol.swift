import Foundation

/// Protocol that all LLM providers must implement
protocol LLMProviderProtocol {
    /// The type of provider this implementation represents
    var providerType: LLMProvider { get }
    
    /// Generate a streaming response from the LLM
    /// - Parameters:
    ///   - context: The conversation context and system prompt
    ///   - agent: The agent configuration
    ///   - apiKey: The API key for authentication
    /// - Returns: An async throwing stream of response chunks
    func generateResponse(
        context: LLMContext,
        agent: LLMAgent,
        apiKey: String
    ) async throws -> AsyncThrowingStream<String, Error>
    
    /// Validate that the agent configuration is valid for this provider
    /// - Parameter agent: The agent to validate
    /// - Returns: True if the configuration is valid
    func validateConfiguration(_ agent: LLMAgent) -> Bool
    
    /// Estimate the number of tokens in the given text
    /// - Parameter text: The text to estimate tokens for
    /// - Returns: Estimated token count
    func estimateTokens(_ text: String) -> Int
    
    /// Get the maximum context window size for the given model
    /// - Parameter model: The model name
    /// - Returns: Maximum context window size in tokens
    func getContextWindowSize(for model: String) -> Int
    
    /// Check if the provider supports streaming responses
    var supportsStreaming: Bool { get }
}

/// Errors that can occur during LLM provider operations
enum LLMProviderError: Error, LocalizedError {
    case invalidAPIKey
    case invalidModel
    case invalidConfiguration
    case networkError(Error)
    case rateLimitExceeded
    case contentFiltered
    case contextTooLong
    case providerUnavailable
    case streamingNotSupported
    case invalidResponse
    case apiError(String)
    case unknownError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid API key provided"
        case .invalidModel:
            return "Invalid model specified"
        case .invalidConfiguration:
            return "Invalid agent configuration"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .rateLimitExceeded:
            return "Rate limit exceeded"
        case .contentFiltered:
            return "Content was filtered by the provider"
        case .contextTooLong:
            return "Context exceeds maximum length"
        case .providerUnavailable:
            return "Provider is currently unavailable"
        case .streamingNotSupported:
            return "Streaming is not supported by this provider"
        case .invalidResponse:
            return "Invalid response from provider"
        case .apiError(let message):
            return "API error: \(message)"
        case .unknownError(let message):
            return "Unknown error: \(message)"
        }
    }
}