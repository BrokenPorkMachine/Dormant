import Foundation

/// Context provided to LLM agents when they wake up
struct LLMContext {
    let systemPrompt: String
    let conversationHistory: [ChatMessage]
    let metadata: ContextMetadata
    
    init(systemPrompt: String, conversationHistory: [ChatMessage], metadata: ContextMetadata) {
        self.systemPrompt = systemPrompt
        self.conversationHistory = conversationHistory
        self.metadata = metadata
    }
}

/// Metadata about the context being provided to an LLM
struct ContextMetadata {
    let roomId: UUID
    let agentId: UUID
    let wakeTime: Date
    let totalMessages: Int
    let contextWindowSize: Int
    
    init(roomId: UUID, agentId: UUID, wakeTime: Date = Date(), totalMessages: Int, contextWindowSize: Int) {
        self.roomId = roomId
        self.agentId = agentId
        self.wakeTime = wakeTime
        self.totalMessages = totalMessages
        self.contextWindowSize = contextWindowSize
    }
}

/// Response from an LLM provider
struct LLMResponse {
    let content: String
    let finishReason: FinishReason
    let usage: TokenUsage?
    let metadata: ResponseMetadata
    
    init(content: String, finishReason: FinishReason, usage: TokenUsage? = nil, metadata: ResponseMetadata) {
        self.content = content
        self.finishReason = finishReason
        self.usage = usage
        self.metadata = metadata
    }
}

/// Reason why the LLM response finished
enum FinishReason: String, Codable {
    case stop
    case length
    case contentFilter = "content_filter"
    case toolCalls = "tool_calls"
    case error
}

/// Token usage information
struct TokenUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    
    init(promptTokens: Int, completionTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = promptTokens + completionTokens
    }
}

/// Metadata about the LLM response
struct ResponseMetadata {
    let provider: LLMProvider
    let model: String
    let responseTime: TimeInterval
    let requestId: String?
    
    init(provider: LLMProvider, model: String, responseTime: TimeInterval, requestId: String? = nil) {
        self.provider = provider
        self.model = model
        self.responseTime = responseTime
        self.requestId = requestId
    }
}