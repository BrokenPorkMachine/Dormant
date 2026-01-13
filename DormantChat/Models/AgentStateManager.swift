import Foundation
import SwiftUI

/// Manages the wake/sleep state of LLM agents and coordinates their interactions
@MainActor
class AgentStateManager: ObservableObject {
    @Published var agents: [LLMAgent] = []
    
    // Private state for managing agent contexts and operations
    private var agentContexts: [UUID: LLMContext] = [:]
    private var activeOperations: [UUID: Task<Void, Error>] = [:]
    
    // Dependencies
    private let contextBuilder: ContextBuilder
    private let providerFactory: LLMProviderFactory
    private let keyVault: SecureKeyVault
    private let dataManager: LocalDataManager
    
    init(
        contextBuilder: ContextBuilder = ContextBuilder(),
        providerFactory: LLMProviderFactory = LLMProviderFactory.shared,
        keyVault: SecureKeyVault = SecureKeyVault.shared,
        dataManager: LocalDataManager = LocalDataManager.shared
    ) {
        self.contextBuilder = contextBuilder
        self.providerFactory = providerFactory
        self.keyVault = keyVault
        self.dataManager = dataManager
        
        // Load agents from persistent storage
        loadAgentsFromStorage()
    }
    
    // MARK: - Agent Management
    
    /// Load agents from persistent storage
    private func loadAgentsFromStorage() {
        do {
            agents = try dataManager.loadAgents()
        } catch {
            print("Failed to load agents from storage: \(error)")
            agents = []
        }
    }
    
    /// Save agents to persistent storage
    private func saveAgentsToStorage() {
        do {
            try dataManager.saveAgents(agents)
        } catch {
            print("Failed to save agents to storage: \(error)")
        }
    }
    
    /// Add a new agent to the manager
    func addAgent(_ agent: LLMAgent) {
        agents.append(agent)
        saveAgentsToStorage()
    }
    
    /// Remove an agent from the manager
    func removeAgent(withId id: UUID) {
        // Cancel any active operations for this agent
        activeOperations[id]?.cancel()
        activeOperations.removeValue(forKey: id)
        
        // Clear context
        agentContexts.removeValue(forKey: id)
        
        // Remove from agents array
        agents.removeAll { $0.id == id }
        saveAgentsToStorage()
    }
    
    /// Update an existing agent
    func updateAgent(_ updatedAgent: LLMAgent) {
        if let index = agents.firstIndex(where: { $0.id == updatedAgent.id }) {
            agents[index] = updatedAgent
            saveAgentsToStorage()
        }
    }
    
    // MARK: - State Management
    
    /// Wake an agent with the provided context
    /// - Parameters:
    ///   - agentId: The ID of the agent to wake
    ///   - context: The conversation messages to provide as context
    func wakeAgent(_ agentId: UUID, context: [ChatMessage]) async {
        guard let agentIndex = agents.firstIndex(where: { $0.id == agentId }) else {
            print("Warning: Attempted to wake unknown agent \(agentId)")
            return
        }
        
        // Update agent state to awake
        agents[agentIndex].state = .awake
        agents[agentIndex].lastWakeTime = Date()
        saveAgentsToStorage()
        
        // Build context for the agent
        let llmContext = contextBuilder.buildContext(for: agents[agentIndex], from: context)
        agentContexts[agentId] = llmContext
        
        print("Agent \(agents[agentIndex].name) awakened with \(context.count) messages in context")
    }
    
    /// Wake an agent without context (simple version)
    /// - Parameter agentId: The ID of the agent to wake
    func wakeAgent(_ agentId: UUID) {
        guard let agentIndex = agents.firstIndex(where: { $0.id == agentId }) else {
            print("Warning: Attempted to wake unknown agent \(agentId)")
            return
        }
        
        // Update agent state to awake
        agents[agentIndex].state = .awake
        agents[agentIndex].lastWakeTime = Date()
        saveAgentsToStorage()
        
        print("Agent \(agents[agentIndex].name) awakened")
    }
    
    /// Put an agent to sleep and clear its context
    /// - Parameter agentId: The ID of the agent to put to sleep
    func sleepAgent(_ agentId: UUID) {
        guard let agentIndex = agents.firstIndex(where: { $0.id == agentId }) else {
            print("Warning: Attempted to sleep unknown agent \(agentId)")
            return
        }
        
        // Cancel any active operations
        activeOperations[agentId]?.cancel()
        activeOperations.removeValue(forKey: agentId)
        
        // Update agent state to dormant
        agents[agentIndex].state = .dormant
        saveAgentsToStorage()
        
        // Clear context
        contextBuilder.clearContext(for: agentId)
        agentContexts.removeValue(forKey: agentId)
        
        print("Agent \(agents[agentIndex].name) returned to dormant state")
    }
    
    /// Check if an agent is currently awake
    /// - Parameter agentId: The ID of the agent to check
    /// - Returns: True if the agent is awake or thinking
    func isAgentAwake(_ agentId: UUID) -> Bool {
        guard let agent = agents.first(where: { $0.id == agentId }) else {
            return false
        }
        return agent.state.isActive
    }
    
    /// Get all currently awake agents
    /// - Returns: Array of awake LLM agents
    func getAwakeAgents() -> [LLMAgent] {
        return agents.filter { $0.state.isActive }
    }
    
    /// Get all dormant agents
    /// - Returns: Array of dormant LLM agents
    func getDormantAgents() -> [LLMAgent] {
        return agents.filter { $0.state == .dormant }
    }
    
    // MARK: - Agent Response Generation
    
    /// Generate a response from an awake agent
    /// - Parameters:
    ///   - agentId: The ID of the agent to generate response from
    ///   - onChunk: Callback for each response chunk
    ///   - onComplete: Callback when response is complete
    /// - Returns: The complete response content
    @discardableResult
    func generateResponse(
        from agentId: UUID,
        onChunk: @escaping (String) -> Void = { _ in },
        onComplete: @escaping (String) -> Void = { _ in }
    ) async throws -> String {
        guard let agentIndex = agents.firstIndex(where: { $0.id == agentId }) else {
            throw LLMProviderError.invalidConfiguration
        }
        
        guard isAgentAwake(agentId) else {
            throw LLMProviderError.invalidConfiguration
        }
        
        guard let context = agentContexts[agentId] else {
            throw LLMProviderError.invalidConfiguration
        }
        
        let agent = agents[agentIndex]
        
        // Update state to thinking
        agents[agentIndex].state = .thinking
        
        do {
            // Get API key for the provider
            guard let apiKey = try keyVault.retrieveAPIKey(for: agent.provider) else {
                throw LLMProviderError.invalidAPIKey
            }
            
            // Get provider implementation
            let provider = try providerFactory.createProvider(for: agent.provider)
            
            // Generate response
            var completeResponse = ""
            let responseStream = try await provider.generateResponse(
                context: context,
                agent: agent,
                apiKey: apiKey
            )
            
            // Create task to handle the streaming response
            let responseTask = Task<Void, Error> {
                do {
                    for try await chunk in responseStream {
                        completeResponse += chunk
                        onChunk(chunk)
                    }
                    onComplete(completeResponse)
                } catch {
                    print("Error in response stream: \(error)")
                    throw error
                }
            }
            
            // Store the active operation
            activeOperations[agentId] = responseTask
            
            // Wait for completion
            try await responseTask.value
            
            // Clean up
            activeOperations.removeValue(forKey: agentId)
            
            // Return agent to awake state (not dormant yet - that happens after message is sent)
            agents[agentIndex].state = .awake
            
            return completeResponse
            
        } catch {
            // Return agent to awake state on error
            agents[agentIndex].state = .awake
            throw error
        }
    }
    
    // MARK: - Batch Operations
    
    /// Wake multiple agents simultaneously
    /// - Parameters:
    ///   - agentIds: Array of agent IDs to wake
    ///   - context: The conversation context to provide to all agents
    func wakeAgents(_ agentIds: [UUID], context: [ChatMessage]) async {
        await withTaskGroup(of: Void.self) { group in
            for agentId in agentIds {
                group.addTask {
                    await self.wakeAgent(agentId, context: context)
                }
            }
        }
    }
    
    /// Put multiple agents to sleep simultaneously
    /// - Parameter agentIds: Array of agent IDs to put to sleep
    func sleepAgents(_ agentIds: [UUID]) {
        for agentId in agentIds {
            sleepAgent(agentId)
        }
    }
    
    /// Put all awake agents to sleep
    func sleepAllAgents() {
        let awakeAgentIds = getAwakeAgents().map { $0.id }
        sleepAgents(awakeAgentIds)
    }
    
    // MARK: - Context Management
    
    /// Get the current context for an agent
    /// - Parameter agentId: The ID of the agent
    /// - Returns: The agent's current context, or nil if not awake
    func getContext(for agentId: UUID) -> LLMContext? {
        return agentContexts[agentId]
    }
    
    /// Update the context for an awake agent (e.g., when new messages arrive)
    /// - Parameters:
    ///   - agentId: The ID of the agent
    ///   - newMessages: New messages to add to context
    func updateContext(for agentId: UUID, with newMessages: [ChatMessage]) {
        guard let agent = agents.first(where: { $0.id == agentId }),
              isAgentAwake(agentId) else {
            return
        }
        
        // Get existing context messages
        let existingMessages = agentContexts[agentId]?.conversationHistory ?? []
        let allMessages = existingMessages + newMessages
        
        // Rebuild context with updated messages
        let updatedContext = contextBuilder.buildContext(for: agent, from: allMessages)
        agentContexts[agentId] = updatedContext
    }
    
    // MARK: - Utility Methods
    
    /// Get agent by ID
    /// - Parameter id: The agent ID
    /// - Returns: The agent if found
    func getAgent(withId id: UUID) -> LLMAgent? {
        return agents.first { $0.id == id }
    }
    
    /// Get agent by name (case-insensitive)
    /// - Parameter name: The agent name
    /// - Returns: The agent if found
    func getAgent(withName name: String) -> LLMAgent? {
        return agents.first { $0.name.lowercased() == name.lowercased() }
    }
    
    /// Cancel all active operations (useful for cleanup)
    func cancelAllOperations() {
        for (_, task) in activeOperations {
            task.cancel()
        }
        activeOperations.removeAll()
    }
}

// MARK: - Extensions for Testing

extension AgentStateManager {
    /// Get the number of active operations (for testing)
    var activeOperationCount: Int {
        return activeOperations.count
    }
    
    /// Check if an agent has context (for testing)
    func hasContext(for agentId: UUID) -> Bool {
        return agentContexts[agentId] != nil
    }
}