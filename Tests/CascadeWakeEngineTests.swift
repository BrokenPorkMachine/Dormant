import Testing
import Foundation
@testable import DormantChat

@Suite("Cascade Wake Engine")
struct CascadeWakeEngineTests {
    
    @Test("Cascade engine detects mentions in LLM responses")
    @MainActor
    func testCascadeDetection() async throws {
        let agentStateManager = AgentStateManager()
        let cascadeEngine = CascadeWakeEngine(agentStateManager: agentStateManager)
        
        // Add test agents
        let agent1 = LLMAgent(name: "Agent1", provider: .openai, model: "gpt-4")
        let agent2 = LLMAgent(name: "Agent2", provider: .anthropic, model: "claude-3-sonnet")
        let triggerAgent = LLMAgent(name: "TriggerAgent", provider: .openai, model: "gpt-4")
        
        agentStateManager.addAgent(agent1)
        agentStateManager.addAgent(agent2)
        agentStateManager.addAgent(triggerAgent)
        
        // Create message with mentions
        let roomId = UUID()
        let triggerMessage = ChatMessage(
            content: "Hey @Agent1 and @Agent2, can you help with this?",
            sender: .llm(agentId: triggerAgent.id, agentName: "TriggerAgent", provider: .openai),
            roomId: roomId
        )
        
        let conversationContext = [
            ChatMessage(
                content: "Previous message",
                sender: .human(userId: "user1", username: "Alice"),
                roomId: roomId
            )
        ]
        
        // Process cascade
        let awakenedAgents = await cascadeEngine.processCascadeTriggers(
            from: triggerMessage,
            conversationContext: conversationContext
        )
        
        // Verify results
        #expect(awakenedAgents.count == 2)
        #expect(awakenedAgents.contains { $0.name == "Agent1" })
        #expect(awakenedAgents.contains { $0.name == "Agent2" })
        
        // Verify agents are now awake
        #expect(agentStateManager.isAgentAwake(agent1.id))
        #expect(agentStateManager.isAgentAwake(agent2.id))
        
        // Verify cascade history
        #expect(cascadeEngine.cascadeHistoryCount == 1)
        
        let lastEvent = cascadeEngine.lastCascadeEvent
        #expect(lastEvent != nil)
        #expect(lastEvent?.mentions.contains("Agent1") == true)
        #expect(lastEvent?.mentions.contains("Agent2") == true)
        #expect(lastEvent?.cascadeDepth == 0)
    }
    
    @Test("Cascade engine ignores human messages")
    @MainActor
    func testIgnoresHumanMessages() async throws {
        let agentStateManager = AgentStateManager()
        let cascadeEngine = CascadeWakeEngine(agentStateManager: agentStateManager)
        
        // Add test agent
        let agent = LLMAgent(name: "TestAgent", provider: .openai, model: "gpt-4")
        agentStateManager.addAgent(agent)
        
        // Create human message with mention
        let humanMessage = ChatMessage(
            content: "Hey @TestAgent, can you help?",
            sender: .human(userId: "user1", username: "Alice"),
            roomId: UUID()
        )
        
        // Process cascade
        let awakenedAgents = await cascadeEngine.processCascadeTriggers(
            from: humanMessage,
            conversationContext: []
        )
        
        // Verify no cascade occurred
        #expect(awakenedAgents.isEmpty)
        #expect(!agentStateManager.isAgentAwake(agent.id))
        #expect(cascadeEngine.cascadeHistoryCount == 0)
    }
    
    @Test("Cascade engine prevents self-wake")
    @MainActor
    func testPreventsSelfWake() async throws {
        let agentStateManager = AgentStateManager()
        let cascadeEngine = CascadeWakeEngine(agentStateManager: agentStateManager)
        
        // Add test agent
        let agent = LLMAgent(name: "SelfAgent", provider: .openai, model: "gpt-4")
        agentStateManager.addAgent(agent)
        
        // Create message where agent mentions itself
        let selfMessage = ChatMessage(
            content: "I think @SelfAgent should handle this",
            sender: .llm(agentId: agent.id, agentName: "SelfAgent", provider: .openai),
            roomId: UUID()
        )
        
        // Process cascade
        let awakenedAgents = await cascadeEngine.processCascadeTriggers(
            from: selfMessage,
            conversationContext: []
        )
        
        // Verify no self-wake occurred
        #expect(awakenedAgents.isEmpty)
        #expect(cascadeEngine.cascadeHistoryCount == 1) // Event is recorded but no agents awakened
        
        let lastEvent = cascadeEngine.lastCascadeEvent
        #expect(lastEvent?.targetAgentIds.isEmpty == true)
    }
    
    @Test("Cascade engine handles unknown mentions")
    @MainActor
    func testHandlesUnknownMentions() async throws {
        let agentStateManager = AgentStateManager()
        let cascadeEngine = CascadeWakeEngine(agentStateManager: agentStateManager)
        
        // Add one known agent
        let knownAgent = LLMAgent(name: "KnownAgent", provider: .openai, model: "gpt-4")
        agentStateManager.addAgent(knownAgent)
        
        // Create message mentioning known and unknown agents
        let triggerAgent = LLMAgent(name: "TriggerAgent", provider: .openai, model: "gpt-4")
        let message = ChatMessage(
            content: "Hey @KnownAgent and @UnknownAgent, help please!",
            sender: .llm(agentId: triggerAgent.id, agentName: "TriggerAgent", provider: .openai),
            roomId: UUID()
        )
        
        // Process cascade
        let awakenedAgents = await cascadeEngine.processCascadeTriggers(
            from: message,
            conversationContext: []
        )
        
        // Verify only known agent was awakened
        #expect(awakenedAgents.count == 1)
        #expect(awakenedAgents[0].name == "KnownAgent")
        #expect(agentStateManager.isAgentAwake(knownAgent.id))
    }
    
    @Test("Cascade engine respects maximum depth")
    @MainActor
    func testRespectsMaximumDepth() async throws {
        let agentStateManager = AgentStateManager()
        let cascadeEngine = CascadeWakeEngine(
            agentStateManager: agentStateManager,
            maxCascadeDepth: 2 // Set low limit for testing
        )
        
        // Add test agent
        let agent = LLMAgent(name: "TestAgent", provider: .openai, model: "gpt-4")
        agentStateManager.addAgent(agent)
        
        // Create message at maximum depth
        let triggerAgent = LLMAgent(name: "TriggerAgent", provider: .openai, model: "gpt-4")
        let message = ChatMessage(
            content: "Hey @TestAgent, help!",
            sender: .llm(agentId: triggerAgent.id, agentName: "TriggerAgent", provider: .openai),
            roomId: UUID()
        )
        
        // Process cascade at max depth
        let awakenedAgents = await cascadeEngine.processCascadeTriggers(
            from: message,
            conversationContext: [],
            cascadeDepth: 2 // At max depth
        )
        
        // Verify cascade was blocked
        #expect(awakenedAgents.isEmpty)
        #expect(!agentStateManager.isAgentAwake(agent.id))
        #expect(cascadeEngine.cascadeHistoryCount == 0)
    }
    
    @Test("Cascade engine handles parallel cascades")
    @MainActor
    func testHandlesParallelCascades() async throws {
        let agentStateManager = AgentStateManager()
        let cascadeEngine = CascadeWakeEngine(agentStateManager: agentStateManager)
        
        // Add test agents
        let agent1 = LLMAgent(name: "Agent1", provider: .openai, model: "gpt-4")
        let agent2 = LLMAgent(name: "Agent2", provider: .anthropic, model: "claude-3-sonnet")
        let agent3 = LLMAgent(name: "Agent3", provider: .openai, model: "gpt-3.5-turbo")
        
        agentStateManager.addAgent(agent1)
        agentStateManager.addAgent(agent2)
        agentStateManager.addAgent(agent3)
        
        // Create multiple messages with different mentions
        let roomId = UUID()
        let triggerAgent1 = LLMAgent(name: "Trigger1", provider: .openai, model: "gpt-4")
        let triggerAgent2 = LLMAgent(name: "Trigger2", provider: .openai, model: "gpt-4")
        
        let messages = [
            ChatMessage(
                content: "Hey @Agent1, can you help?",
                sender: .llm(agentId: triggerAgent1.id, agentName: "Trigger1", provider: .openai),
                roomId: roomId
            ),
            ChatMessage(
                content: "Also @Agent2 and @Agent3, please assist!",
                sender: .llm(agentId: triggerAgent2.id, agentName: "Trigger2", provider: .openai),
                roomId: roomId
            )
        ]
        
        // Process multiple cascades
        let awakenedAgents = await cascadeEngine.processMultipleCascadeTriggers(
            from: messages,
            conversationContext: []
        )
        
        // Verify all agents were awakened
        #expect(awakenedAgents.count == 3)
        #expect(agentStateManager.isAgentAwake(agent1.id))
        #expect(agentStateManager.isAgentAwake(agent2.id))
        #expect(agentStateManager.isAgentAwake(agent3.id))
        
        // Verify cascade history shows multiple events
        #expect(cascadeEngine.cascadeHistoryCount == 2)
    }
    
    @Test("Cascade engine provides statistics")
    @MainActor
    func testProvidesStatistics() async throws {
        let agentStateManager = AgentStateManager()
        let cascadeEngine = CascadeWakeEngine(agentStateManager: agentStateManager)
        
        // Add test agents
        let agent1 = LLMAgent(name: "Agent1", provider: .openai, model: "gpt-4")
        let agent2 = LLMAgent(name: "Agent2", provider: .anthropic, model: "claude-3-sonnet")
        
        agentStateManager.addAgent(agent1)
        agentStateManager.addAgent(agent2)
        
        // Initial statistics
        var stats = cascadeEngine.cascadeStatistics
        #expect(stats.totalCascades == 0)
        #expect(stats.successfulCascades == 0)
        #expect(stats.activeCascades == 0)
        
        // Create successful cascade
        let triggerAgent = LLMAgent(name: "TriggerAgent", provider: .openai, model: "gpt-4")
        let successMessage = ChatMessage(
            content: "Hey @Agent1, help!",
            sender: .llm(agentId: triggerAgent.id, agentName: "TriggerAgent", provider: .openai),
            roomId: UUID()
        )
        
        await cascadeEngine.processCascadeTriggers(
            from: successMessage,
            conversationContext: []
        )
        
        // Create failed cascade (unknown agent)
        let failMessage = ChatMessage(
            content: "Hey @UnknownAgent, help!",
            sender: .llm(agentId: triggerAgent.id, agentName: "TriggerAgent", provider: .openai),
            roomId: UUID()
        )
        
        await cascadeEngine.processCascadeTriggers(
            from: failMessage,
            conversationContext: []
        )
        
        // Check updated statistics
        stats = cascadeEngine.cascadeStatistics
        #expect(stats.totalCascades == 2)
        #expect(stats.successfulCascades == 1)
        #expect(stats.successRate == 0.5)
        #expect(stats.averageCascadeDepth == 0.0)
        #expect(stats.maxDepthReached == 0)
    }
    
    @Test("Cascade engine skips already awake agents")
    @MainActor
    func testSkipsAwakeAgents() async throws {
        let agentStateManager = AgentStateManager()
        let cascadeEngine = CascadeWakeEngine(agentStateManager: agentStateManager)
        
        // Add test agents
        let agent1 = LLMAgent(name: "Agent1", provider: .openai, model: "gpt-4")
        let agent2 = LLMAgent(name: "Agent2", provider: .anthropic, model: "claude-3-sonnet")
        
        agentStateManager.addAgent(agent1)
        agentStateManager.addAgent(agent2)
        
        // Wake agent1 manually
        await agentStateManager.wakeAgent(agent1.id, context: [])
        
        // Create cascade message mentioning both agents
        let triggerAgent = LLMAgent(name: "TriggerAgent", provider: .openai, model: "gpt-4")
        let message = ChatMessage(
            content: "Hey @Agent1 and @Agent2, help!",
            sender: .llm(agentId: triggerAgent.id, agentName: "TriggerAgent", provider: .openai),
            roomId: UUID()
        )
        
        // Process cascade
        let awakenedAgents = await cascadeEngine.processCascadeTriggers(
            from: message,
            conversationContext: []
        )
        
        // Verify only the dormant agent was awakened
        #expect(awakenedAgents.count == 1)
        #expect(awakenedAgents[0].name == "Agent2")
        
        // Both should be awake now
        #expect(agentStateManager.isAgentAwake(agent1.id))
        #expect(agentStateManager.isAgentAwake(agent2.id))
    }
}