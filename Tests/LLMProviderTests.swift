import Foundation
import Testing
@testable import DormantChat

@Suite("LLM Provider Abstraction Layer")
struct LLMProviderTests {
    
    @Test("Provider factory creates correct providers")
    func testProviderFactoryCreation() throws {
        let factory = LLMProviderFactory.shared
        
        // Test OpenAI provider creation
        let openaiProvider = try factory.createProvider(for: .openai)
        #expect(openaiProvider.providerType == .openai)
        #expect(openaiProvider.supportsStreaming == true)
        
        // Test Anthropic provider creation
        let anthropicProvider = try factory.createProvider(for: .anthropic)
        #expect(anthropicProvider.providerType == .anthropic)
        #expect(anthropicProvider.supportsStreaming == true)
        
        // Test all providers are now supported
        let huggingfaceProvider = try factory.createProvider(for: .huggingface)
        #expect(huggingfaceProvider is HuggingFaceConnector)
        
        let ollamaProvider = try factory.createProvider(for: .ollama)
        #expect(ollamaProvider is OllamaConnector)
        
        let customProvider = try factory.createProvider(for: .custom)
        #expect(customProvider is CustomConnector)
    }
    
    @Test("Provider factory supported providers")
    func testSupportedProviders() {
        let factory = LLMProviderFactory.shared
        let supported = factory.getSupportedProviders()
        
        #expect(supported.contains(.openai))
        #expect(supported.contains(.anthropic))
        #expect(supported.contains(.huggingface))
        #expect(supported.contains(.ollama))
        #expect(supported.contains(.custom))
        #expect(supported.contains(.gemini))
        #expect(supported.contains(.grok))
        
        #expect(factory.isProviderSupported(.openai))
        #expect(factory.isProviderSupported(.anthropic))
        #expect(factory.isProviderSupported(.huggingface))
        #expect(factory.isProviderSupported(.ollama))
        #expect(factory.isProviderSupported(.custom))
    }
    
    @Test("OpenAI provider configuration validation")
    func testOpenAIProviderValidation() throws {
        let provider = try LLMProviderFactory.shared.createProvider(for: .openai)
        
        // Valid configuration
        let validAgent = LLMAgent(
            name: "TestAgent",
            provider: .openai,
            model: "gpt-4",
            temperature: 0.7,
            maxTokens: 1000
        )
        #expect(provider.validateConfiguration(validAgent))
        
        // Invalid provider
        let wrongProviderAgent = LLMAgent(
            name: "TestAgent",
            provider: .anthropic,
            model: "gpt-4"
        )
        #expect(!provider.validateConfiguration(wrongProviderAgent))
        
        // Invalid model
        let invalidModelAgent = LLMAgent(
            name: "TestAgent",
            provider: .openai,
            model: "invalid-model"
        )
        #expect(!provider.validateConfiguration(invalidModelAgent))
        
        // Invalid temperature
        let invalidTempAgent = LLMAgent(
            name: "TestAgent",
            provider: .openai,
            model: "gpt-4",
            temperature: 3.0
        )
        #expect(!provider.validateConfiguration(invalidTempAgent))
    }
    
    @Test("Anthropic provider configuration validation")
    func testAnthropicProviderValidation() throws {
        let provider = try LLMProviderFactory.shared.createProvider(for: .anthropic)
        
        // Valid configuration
        let validAgent = LLMAgent(
            name: "TestAgent",
            provider: .anthropic,
            model: "claude-3-sonnet",
            temperature: 0.7,
            maxTokens: 1000
        )
        #expect(provider.validateConfiguration(validAgent))
        
        // Invalid provider
        let wrongProviderAgent = LLMAgent(
            name: "TestAgent",
            provider: .openai,
            model: "claude-3-sonnet"
        )
        #expect(!provider.validateConfiguration(wrongProviderAgent))
        
        // Invalid temperature (Anthropic max is 1.0)
        let invalidTempAgent = LLMAgent(
            name: "TestAgent",
            provider: .anthropic,
            model: "claude-3-sonnet",
            temperature: 1.5
        )
        #expect(!provider.validateConfiguration(invalidTempAgent))
    }
    
    @Test("Token estimation")
    func testTokenEstimation() throws {
        let openaiProvider = try LLMProviderFactory.shared.createProvider(for: .openai)
        let anthropicProvider = try LLMProviderFactory.shared.createProvider(for: .anthropic)
        
        let testText = "Hello, world! This is a test message."
        
        let openaiTokens = openaiProvider.estimateTokens(testText)
        let anthropicTokens = anthropicProvider.estimateTokens(testText)
        
        #expect(openaiTokens > 0)
        #expect(anthropicTokens > 0)
        #expect(openaiTokens == anthropicTokens) // Both use same estimation method
    }
    
    @Test("Context window sizes")
    func testContextWindowSizes() throws {
        let openaiProvider = try LLMProviderFactory.shared.createProvider(for: .openai)
        let anthropicProvider = try LLMProviderFactory.shared.createProvider(for: .anthropic)
        
        // OpenAI context windows
        #expect(openaiProvider.getContextWindowSize(for: "gpt-4") == 128000)
        #expect(openaiProvider.getContextWindowSize(for: "gpt-3.5-turbo") == 4096)
        #expect(openaiProvider.getContextWindowSize(for: "gpt-3.5-turbo-16k") == 16384)
        
        // Anthropic context windows
        #expect(anthropicProvider.getContextWindowSize(for: "claude-3-opus") == 200000)
        #expect(anthropicProvider.getContextWindowSize(for: "claude-3-sonnet") == 200000)
        #expect(anthropicProvider.getContextWindowSize(for: "claude-3-haiku") == 200000)
    }
    
    @Test("Agent validator integration")
    func testAgentValidatorIntegration() throws {
        let factory = LLMProviderFactory.shared
        
        // Valid agent
        let validAgent = LLMAgent(
            name: "TestAgent",
            provider: .openai,
            model: "gpt-4"
        )
        #expect(try factory.validateAgentConfiguration(validAgent))
        
        // Another valid agent (now supported provider)
        let huggingfaceAgent = LLMAgent(
            name: "TestAgent",
            provider: .huggingface,
            model: "microsoft/DialoGPT-medium"
        )
        #expect(try factory.validateAgentConfiguration(huggingfaceAgent))
        
        // Test that validation returns true for valid configurations
        #expect(try factory.validateAgentConfiguration(validAgent) == true)
    }
    
    @Test("LLM context and response models")
    func testLLMContextAndResponseModels() {
        let roomId = UUID()
        let agentId = UUID()
        
        let metadata = ContextMetadata(
            roomId: roomId,
            agentId: agentId,
            totalMessages: 10,
            contextWindowSize: 4096
        )
        
        let context = LLMContext(
            systemPrompt: "You are a helpful assistant.",
            conversationHistory: [],
            metadata: metadata
        )
        
        #expect(context.systemPrompt == "You are a helpful assistant.")
        #expect(context.conversationHistory.isEmpty)
        #expect(context.metadata.roomId == roomId)
        #expect(context.metadata.agentId == agentId)
        
        let responseMetadata = ResponseMetadata(
            provider: .openai,
            model: "gpt-4",
            responseTime: 1.5
        )
        
        let response = LLMResponse(
            content: "Hello!",
            finishReason: .stop,
            metadata: responseMetadata
        )
        
        #expect(response.content == "Hello!")
        #expect(response.finishReason == .stop)
        #expect(response.metadata.provider == .openai)
    }
}