import Foundation

/// LLM Agent Configuration
struct LLMAgent: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var provider: LLMProvider
    var model: String
    var personality: String
    var temperature: Double
    var maxTokens: Int
    var state: AgentState
    var lastWakeTime: Date?
    
    init(
        id: UUID = UUID(),
        name: String,
        provider: LLMProvider,
        model: String,
        personality: String = "",
        temperature: Double = 0.7,
        maxTokens: Int = 1000,
        state: AgentState = .dormant,
        lastWakeTime: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.model = model
        self.personality = personality
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.state = state
        self.lastWakeTime = lastWakeTime
    }
}