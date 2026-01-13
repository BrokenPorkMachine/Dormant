import Foundation
import Combine

/// Handles cascading wake operations when LLM agents mention other agents
@MainActor
class CascadeWakeEngine: ObservableObject {
    
    // Dependencies
    private let mentionScanner: MentionScanner
    private let agentStateManager: AgentStateManager
    
    // Configuration
    private let maxCascadeDepth: Int
    private let cascadeDelay: TimeInterval
    
    // State tracking
    private var cascadeHistory: [CascadeEvent] = []
    private var activeCascades: Set<UUID> = []
    
    init(
        mentionScanner: MentionScanner = MentionScanner(),
        agentStateManager: AgentStateManager,
        maxCascadeDepth: Int = 5,
        cascadeDelay: TimeInterval = 0.1
    ) {
        self.mentionScanner = mentionScanner
        self.agentStateManager = agentStateManager
        self.maxCascadeDepth = maxCascadeDepth
        self.cascadeDelay = cascadeDelay
    }
    
    // MARK: - Cascade Detection and Processing
    
    /// Process a message for potential cascade triggers
    /// - Parameters:
    ///   - message: The message to process (typically from an LLM agent)
    ///   - conversationContext: Current conversation context for newly awakened agents
    ///   - cascadeDepth: Current cascade depth to prevent infinite loops
    /// - Returns: Array of agents that were awakened by this cascade
    @discardableResult
    func processCascadeTriggers(
        from message: ChatMessage,
        conversationContext: [ChatMessage],
        cascadeDepth: Int = 0
    ) async -> [LLMAgent] {
        // Prevent infinite cascade loops
        guard cascadeDepth < maxCascadeDepth else {
            print("Warning: Maximum cascade depth (\(maxCascadeDepth)) reached, stopping cascade")
            return []
        }
        
        // Only process messages from LLM agents (not humans or system)
        guard case .llm(let triggeringAgentId, let triggeringAgentName, _) = message.sender else {
            return []
        }
        
        // Extract mentions from the message
        let mentions = mentionScanner.extractMentions(from: message.content)
        guard !mentions.isEmpty else {
            return []
        }
        
        print("Cascade trigger detected: \(triggeringAgentName) mentioned \(mentions.joined(separator: ", "))")
        
        // Find agents to wake based on mentions
        let agentsToWake = findAgentsToWake(from: mentions, excludingAgentId: triggeringAgentId)
        
        // Create cascade event for tracking (even if no agents to wake)
        let cascadeEvent = CascadeEvent(
            id: UUID(),
            triggeringMessage: message,
            triggeringAgentId: triggeringAgentId,
            targetAgentIds: agentsToWake.map { $0.id },
            mentions: mentions,
            cascadeDepth: cascadeDepth,
            timestamp: Date()
        )
        
        // Add to cascade history
        cascadeHistory.append(cascadeEvent)
        
        guard !agentsToWake.isEmpty else {
            print("No valid agents found for mentions: \(mentions.joined(separator: ", "))")
            return []
        }
        
        // Wake the mentioned agents
        let awakenedAgents = await wakeAgentsInCascade(
            agents: agentsToWake,
            conversationContext: conversationContext + [message], // Include triggering message
            cascadeEvent: cascadeEvent
        )
        
        print("Cascade completed: awakened \(awakenedAgents.count) agents")
        return awakenedAgents
    }
    
    /// Process multiple cascade triggers simultaneously
    /// - Parameters:
    ///   - messages: Array of messages that might contain cascade triggers
    ///   - conversationContext: Current conversation context
    /// - Returns: All agents awakened by any of the cascades
    func processMultipleCascadeTriggers(
        from messages: [ChatMessage],
        conversationContext: [ChatMessage]
    ) async -> [LLMAgent] {
        var allAwakenedAgents: [LLMAgent] = []
        
        // Process cascades in parallel
        await withTaskGroup(of: [LLMAgent].self) { group in
            for message in messages {
                group.addTask {
                    await self.processCascadeTriggers(
                        from: message,
                        conversationContext: conversationContext
                    )
                }
            }
            
            for await awakenedAgents in group {
                allAwakenedAgents.append(contentsOf: awakenedAgents)
            }
        }
        
        // Remove duplicates (in case multiple messages mention the same agent)
        let uniqueAgents = Array(Set(allAwakenedAgents.map { $0.id }))
            .compactMap { agentId in
                allAwakenedAgents.first { $0.id == agentId }
            }
        
        return uniqueAgents
    }
    
    // MARK: - Agent Wake Coordination
    
    /// Wake multiple agents as part of a cascade operation
    /// - Parameters:
    ///   - agents: Agents to wake
    ///   - conversationContext: Context to provide to awakened agents
    ///   - cascadeEvent: The cascade event that triggered this wake
    /// - Returns: Successfully awakened agents
    private func wakeAgentsInCascade(
        agents: [LLMAgent],
        conversationContext: [ChatMessage],
        cascadeEvent: CascadeEvent
    ) async -> [LLMAgent] {
        var awakenedAgents: [LLMAgent] = []
        
        // Mark cascade as active
        activeCascades.insert(cascadeEvent.id)
        
        // Wake agents in parallel with slight delay to prevent overwhelming
        await withTaskGroup(of: (UUID, Bool).self) { group in
            for (index, agent) in agents.enumerated() {
                group.addTask {
                    // Add slight delay for each agent to prevent overwhelming
                    if index > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(self.cascadeDelay * Double(index) * 1_000_000_000))
                    }
                    
                    await self.agentStateManager.wakeAgent(agent.id, context: conversationContext)
                    return (agent.id, true)
                }
            }
            
            for await (agentId, success) in group {
                if success, let agent = agents.first(where: { $0.id == agentId }) {
                    awakenedAgents.append(agent)
                }
            }
        }
        
        // Mark cascade as complete
        activeCascades.remove(cascadeEvent.id)
        
        return awakenedAgents
    }
    
    /// Find agents that should be awakened based on mentions
    /// - Parameters:
    ///   - mentions: Array of mention names
    ///   - excludingAgentId: ID of agent to exclude (the one that triggered the cascade)
    /// - Returns: Array of agents to wake
    private func findAgentsToWake(from mentions: [String], excludingAgentId: UUID) -> [LLMAgent] {
        var agentsToWake: [LLMAgent] = []
        
        for mention in mentions {
            // Find agent by name (case-insensitive)
            if let agent = agentStateManager.getAgent(withName: mention) {
                // Don't wake the agent that triggered the cascade
                guard agent.id != excludingAgentId else { continue }
                
                // Only wake dormant agents
                guard agent.state == .dormant else {
                    print("Agent \(agent.name) is already \(agent.state.displayName), skipping wake")
                    continue
                }
                
                agentsToWake.append(agent)
            } else {
                print("Warning: Mentioned agent '\(mention)' not found")
            }
        }
        
        return agentsToWake
    }
    
    // MARK: - Cascade Management
    
    /// Check if any cascades are currently active
    var hasActiveCascades: Bool {
        return !activeCascades.isEmpty
    }
    
    /// Get the number of active cascades
    var activeCascadeCount: Int {
        return activeCascades.count
    }
    
    /// Get recent cascade history
    /// - Parameter limit: Maximum number of events to return
    /// - Returns: Recent cascade events, most recent first
    func getRecentCascadeHistory(limit: Int = 10) -> [CascadeEvent] {
        return Array(cascadeHistory.suffix(limit).reversed())
    }
    
    /// Clear cascade history (useful for testing or memory management)
    func clearCascadeHistory() {
        cascadeHistory.removeAll()
    }
    
    /// Cancel all active cascades (emergency stop)
    func cancelAllActiveCascades() {
        activeCascades.removeAll()
        print("All active cascades cancelled")
    }
    
    // MARK: - Statistics and Monitoring
    
    /// Get cascade statistics
    var cascadeStatistics: CascadeStatistics {
        let totalCascades = cascadeHistory.count
        let successfulCascades = cascadeHistory.filter { !$0.targetAgentIds.isEmpty }.count
        let averageDepth = cascadeHistory.isEmpty ? 0.0 : 
            Double(cascadeHistory.map { $0.cascadeDepth }.reduce(0, +)) / Double(cascadeHistory.count)
        let averageTargets = cascadeHistory.isEmpty ? 0.0 :
            Double(cascadeHistory.map { $0.targetAgentIds.count }.reduce(0, +)) / Double(cascadeHistory.count)
        
        return CascadeStatistics(
            totalCascades: totalCascades,
            successfulCascades: successfulCascades,
            activeCascades: activeCascades.count,
            averageCascadeDepth: averageDepth,
            averageTargetsPerCascade: averageTargets,
            maxDepthReached: cascadeHistory.map { $0.cascadeDepth }.max() ?? 0
        )
    }
}

// MARK: - Supporting Types

/// Represents a single cascade event
struct CascadeEvent: Identifiable, Equatable {
    let id: UUID
    let triggeringMessage: ChatMessage
    let triggeringAgentId: UUID
    let targetAgentIds: [UUID]
    let mentions: [String]
    let cascadeDepth: Int
    let timestamp: Date
    
    static func == (lhs: CascadeEvent, rhs: CascadeEvent) -> Bool {
        return lhs.id == rhs.id
    }
}

/// Statistics about cascade operations
struct CascadeStatistics {
    let totalCascades: Int
    let successfulCascades: Int
    let activeCascades: Int
    let averageCascadeDepth: Double
    let averageTargetsPerCascade: Double
    let maxDepthReached: Int
    
    var successRate: Double {
        guard totalCascades > 0 else { return 0.0 }
        return Double(successfulCascades) / Double(totalCascades)
    }
}

// MARK: - Extensions for Testing

extension CascadeWakeEngine {
    /// Get cascade history count (for testing)
    var cascadeHistoryCount: Int {
        return cascadeHistory.count
    }
    
    /// Get the last cascade event (for testing)
    var lastCascadeEvent: CascadeEvent? {
        return cascadeHistory.last
    }
    
    /// Create a test cascade event (for testing)
    static func createTestCascadeEvent(
        triggeringAgentId: UUID = UUID(),
        targetAgentIds: [UUID] = [UUID()],
        mentions: [String] = ["TestAgent"],
        cascadeDepth: Int = 0
    ) -> CascadeEvent {
        let testMessage = ChatMessage(
            content: "Test message with @\(mentions.first ?? "TestAgent")",
            sender: .llm(agentId: triggeringAgentId, agentName: "TriggerAgent", provider: .openai),
            roomId: UUID()
        )
        
        return CascadeEvent(
            id: UUID(),
            triggeringMessage: testMessage,
            triggeringAgentId: triggeringAgentId,
            targetAgentIds: targetAgentIds,
            mentions: mentions,
            cascadeDepth: cascadeDepth,
            timestamp: Date()
        )
    }
}
