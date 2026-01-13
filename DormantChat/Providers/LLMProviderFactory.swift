import Foundation

/// Factory for creating LLM provider instances
class LLMProviderFactory {
    
    /// Shared singleton instance
    static let shared = LLMProviderFactory()
    
    private init() {}
    
    /// Create a provider instance for the given provider type
    /// - Parameter providerType: The type of provider to create
    /// - Returns: A provider instance conforming to LLMProviderProtocol
    /// - Throws: LLMProviderError if the provider type is not supported
    func createProvider(for providerType: LLMProvider) throws -> LLMProviderProtocol {
        switch providerType {
        case .openai:
            return OpenAIConnector()
        case .anthropic:
            return AnthropicConnector()
        case .huggingface:
            return HuggingFaceConnector()
        case .ollama:
            return OllamaConnector()
        case .gemini:
            return GeminiConnector()
        case .grok:
            return GrokConnector()
        case .cohere:
            return CohereConnector()
        case .mistral:
            return MistralConnector()
        case .perplexity:
            return PerplexityConnector()
        case .together:
            return TogetherConnector()
        case .replicate:
            return ReplicateConnector()
        case .groq:
            return GroqConnector()
        case .custom:
            return CustomConnector()
        }
    }
    
    /// Get all supported provider types
    /// - Returns: Array of supported LLMProvider types
    func getSupportedProviders() -> [LLMProvider] {
        return LLMProvider.allCases
    }
    
    /// Check if a provider type is supported
    /// - Parameter providerType: The provider type to check
    /// - Returns: True if the provider is supported
    func isProviderSupported(_ providerType: LLMProvider) -> Bool {
        return getSupportedProviders().contains(providerType)
    }
    
    /// Validate an agent configuration against its provider
    /// - Parameter agent: The agent to validate
    /// - Returns: True if the configuration is valid
    /// - Throws: LLMProviderError if validation fails
    func validateAgentConfiguration(_ agent: LLMAgent) throws -> Bool {
        guard isProviderSupported(agent.provider) else {
            throw LLMProviderError.providerUnavailable
        }
        
        let provider = try createProvider(for: agent.provider)
        return provider.validateConfiguration(agent)
    }
    
    /// Get the context window size for a specific agent
    /// - Parameter agent: The agent to get context window size for
    /// - Returns: Context window size in tokens
    /// - Throws: LLMProviderError if the provider is not supported
    func getContextWindowSize(for agent: LLMAgent) throws -> Int {
        let provider = try createProvider(for: agent.provider)
        return provider.getContextWindowSize(for: agent.model)
    }
    
    /// Estimate tokens for text using a specific provider
    /// - Parameters:
    ///   - text: The text to estimate tokens for
    ///   - providerType: The provider type to use for estimation
    /// - Returns: Estimated token count
    /// - Throws: LLMProviderError if the provider is not supported
    func estimateTokens(_ text: String, using providerType: LLMProvider) throws -> Int {
        let provider = try createProvider(for: providerType)
        return provider.estimateTokens(text)
    }
}

/// Configuration validator for LLM agents
struct LLMAgentValidator {
    
    /// Validate all aspects of an agent configuration
    /// - Parameter agent: The agent to validate
    /// - Returns: ValidationResult with details about any issues
    static func validate(_ agent: LLMAgent) -> ValidationResult {
        var errors: [String] = []
        var warnings: [String] = []
        
        // Basic field validation
        if agent.name.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Agent name cannot be empty")
        }
        
        if agent.model.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Model name cannot be empty")
        }
        
        // Temperature validation
        if agent.temperature < 0.0 {
            errors.append("Temperature cannot be negative")
        } else if agent.temperature > 2.0 {
            errors.append("Temperature cannot exceed 2.0")
        } else if agent.temperature > 1.5 {
            warnings.append("High temperature (>\(agent.temperature)) may produce unpredictable results")
        }
        
        // Max tokens validation
        if agent.maxTokens <= 0 {
            errors.append("Max tokens must be greater than 0")
        } else if agent.maxTokens > 4096 {
            warnings.append("Max tokens (\(agent.maxTokens)) is very high and may be expensive")
        }
        
        // Provider-specific validation
        do {
            let isValid = try LLMProviderFactory.shared.validateAgentConfiguration(agent)
            if !isValid {
                errors.append("Invalid configuration for \(agent.provider.displayName) provider")
            }
        } catch {
            errors.append("Provider validation failed: \(error.localizedDescription)")
        }
        
        return ValidationResult(isValid: errors.isEmpty, errors: errors, warnings: warnings)
    }
}

/// Result of agent configuration validation
struct ValidationResult {
    let isValid: Bool
    let errors: [String]
    let warnings: [String]
    
    var hasWarnings: Bool {
        return !warnings.isEmpty
    }
    
    var allIssues: [String] {
        return errors + warnings
    }
}