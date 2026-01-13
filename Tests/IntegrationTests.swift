import XCTest
@testable import DormantChat

/// Integration tests for core Dormant Chat functionality
@MainActor
final class IntegrationTests: XCTestCase {
    
    var agentManager: AgentStateManager!
    var chatViewModel: ChatViewModel!
    var errorHandler: ErrorHandler!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Initialize components
        agentManager = AgentStateManager()
        chatViewModel = ChatViewModel()
        errorHandler = ErrorHandler.shared
        
        // Set up test agents
        agentManager.agents = chatViewModel.availableAgents
        
        // Clear any existing errors
        errorHandler.clearCurrentError()
        errorHandler.clearHistory()
    }
    
    override func tearDown() async throws {
        agentManager = nil
        chatViewModel = nil
        try await super.tearDown()
    }
    
    // MARK: - Agent Management Tests
    
    func testAgentInitialization() throws {
        // Verify agents are properly initialized
        XCTAssertFalse(agentManager.agents.isEmpty, "Should have initialized agents")
        XCTAssertEqual(agentManager.agents.count, 5, "Should have 5 sample agents")
        
        // Verify all agents start in dormant state
        for agent in agentManager.agents {
            XCTAssertEqual(agent.state, .dormant, "Agent \(agent.name) should start dormant")
        }
        
        // Verify agent names are unique
        let names = Set(agentManager.agents.map { $0.name })
        XCTAssertEqual(names.count, agentManager.agents.count, "Agent names should be unique")
    }
    
    func testAgentWakeAndSleep() throws {
        let agent = agentManager.agents.first!
        let initialState = agent.state
        
        // Test wake
        agentManager.wakeAgent(agent.id)
        let updatedAgent = agentManager.agents.first { $0.id == agent.id }!
        XCTAssertNotEqual(updatedAgent.state, initialState, "Agent state should change after wake")
        
        // Test sleep
        agentManager.sleepAgent(agent.id)
        let sleptAgent = agentManager.agents.first { $0.id == agent.id }!
        XCTAssertEqual(sleptAgent.state, .dormant, "Agent should return to dormant state")
    }
    
    // MARK: - Message Processing Tests
    
    func testMentionExtraction() throws {
        let testCases = [
            ("Hello @Claude, how are you?", ["Claude"]),
            ("@GPT-4 and @Gemini, please help", ["GPT-4", "Gemini"]),
            ("No mentions here", []),
            ("@Claude @GPT-4 @Llama", ["Claude", "GPT-4", "Llama"]),
            ("Email test@example.com should not match", [])
        ]
        
        for (content, expectedMentions) in testCases {
            let message = ChatMessage(
                content: content,
                sender: .human(userId: "test", username: "Test"),
                roomId: UUID()
            )
            
            let mentions = message.extractMentions()
            XCTAssertEqual(
                Set(mentions),
                Set(expectedMentions),
                "Failed for content: '\(content)'"
            )
        }
    }
    
    func testMessageSending() throws {
        let roomId = UUID()
        let messageContent = "Hello @Claude, please help me with something."
        
        // Set up expectation for notification
        let expectation = XCTestExpectation(description: "Message notification")
        let observer = NotificationCenter.default.addObserver(
            forName: .newChatMessage,
            object: nil,
            queue: .main
        ) { notification in
            if let message = notification.object as? ChatMessage,
               message.content == messageContent {
                expectation.fulfill()
            }
        }
        
        // Send message
        chatViewModel.sendMessage(messageContent, roomId: roomId, agentManager: agentManager)
        
        // Wait for notification
        wait(for: [expectation], timeout: 1.0)
        
        NotificationCenter.default.removeObserver(observer)
    }
    
    // MARK: - Provider Integration Tests
    
    func testProviderFactory() throws {
        let factory = LLMProviderFactory.shared
        
        // Test all providers can be created
        for providerType in LLMProvider.allCases {
            XCTAssertNoThrow(
                try factory.createProvider(for: providerType),
                "Should be able to create provider for \(providerType)"
            )
        }
        
        // Test provider validation
        let testAgent = LLMAgent(
            name: "Test",
            provider: .openai,
            model: "gpt-4",
            personality: "Test agent",
            state: .dormant
        )
        
        XCTAssertNoThrow(
            try factory.validateAgentConfiguration(testAgent),
            "Should validate test agent configuration"
        )
    }
    
    func testContextBuilder() throws {
        let agent = agentManager.agents.first!
        let messages = [
            ChatMessage(
                content: "Hello",
                sender: .human(userId: "user1", username: "User"),
                roomId: UUID()
            ),
            ChatMessage(
                content: "Hi there!",
                sender: .llm(agentId: agent.id, agentName: agent.name, provider: agent.provider),
                roomId: UUID()
            )
        ]
        
        let contextBuilder = ContextBuilder()
        let context = contextBuilder.buildContext(for: agent, from: messages)
        
        XCTAssertFalse(context.systemPrompt.isEmpty, "System prompt should not be empty")
        XCTAssertEqual(context.conversationHistory.count, messages.count, "Should include all messages")
        XCTAssertNotNil(context.metadata, "Should have metadata")
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorHandling() throws {
        let testError = DormantError.network(.connectionFailed)
        
        // Test error handling
        errorHandler.handle(testError, context: "Test context", showToUser: false)
        
        XCTAssertFalse(errorHandler.errorHistory.isEmpty, "Should record error in history")
        
        let logEntry = errorHandler.errorHistory.last!
        XCTAssertEqual(logEntry.error.id, testError.id, "Should record correct error")
        XCTAssertEqual(logEntry.context, "Test context", "Should record context")
    }
    
    func testErrorRecoveryActions() throws {
        let networkError = DormantError.network(.connectionFailed)
        let authError = DormantError.authentication(.invalidAPIKey)
        
        let networkActions = errorHandler.getRecoveryActions(for: networkError)
        let authActions = errorHandler.getRecoveryActions(for: authError)
        
        XCTAssertFalse(networkActions.isEmpty, "Should have recovery actions for network errors")
        XCTAssertFalse(authActions.isEmpty, "Should have recovery actions for auth errors")
        
        // Verify different error types have different actions
        XCTAssertNotEqual(networkActions.count, authActions.count, "Different error types should have different actions")
    }
    
    // MARK: - Security Tests
    
    func testSecureKeyVault() throws {
        let keyVault = SecureKeyVault.shared
        let testKey = "test-api-key-12345"
        let provider = LLMProvider.openai
        
        // Test store and retrieve
        XCTAssertNoThrow(
            try keyVault.storeAPIKey(testKey, for: provider),
            "Should store API key without error"
        )
        
        let retrievedKey = try keyVault.retrieveAPIKey(for: provider)
        XCTAssertEqual(retrievedKey, testKey, "Should retrieve the same key")
        
        // Test delete
        XCTAssertNoThrow(
            try keyVault.deleteAPIKey(for: provider),
            "Should delete API key without error"
        )
        
        XCTAssertNil(
            try keyVault.retrieveAPIKey(for: provider),
            "Should return nil after deletion"
        )
    }
    
    // MARK: - Performance Tests
    
    func testAgentWakePerformance() throws {
        let agent = agentManager.agents.first!
        
        measure {
            for _ in 0..<100 {
                agentManager.wakeAgent(agent.id)
                agentManager.sleepAgent(agent.id)
            }
        }
    }
    
    func testMentionExtractionPerformance() throws {
        let longMessage = String(repeating: "Hello @Claude and @GPT-4, ", count: 100)
        let message = ChatMessage(
            content: longMessage,
            sender: .human(userId: "test", username: "Test"),
            roomId: UUID()
        )
        
        measure {
            for _ in 0..<1000 {
                _ = message.extractMentions()
            }
        }
    }
    
    // MARK: - Integration Flow Tests
    
    func testCompleteUserFlow() async throws {
        let roomId = UUID()
        
        // 1. User sends message with mention
        let expectation1 = XCTestExpectation(description: "User message sent")
        let observer1 = NotificationCenter.default.addObserver(
            forName: .newChatMessage,
            object: nil,
            queue: .main
        ) { _ in expectation1.fulfill() }
        
        chatViewModel.sendMessage("Hello @Claude!", roomId: roomId, agentManager: agentManager)
        await fulfillment(of: [expectation1], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer1)
        
        // 2. Verify agent was awakened
        let claudeAgent = agentManager.agents.first { $0.name == "Claude" }!
        XCTAssertNotEqual(claudeAgent.state, .dormant, "Claude should be awakened")
        
        // 3. Wait for agent to return to dormant state
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        let updatedClaude = agentManager.agents.first { $0.name == "Claude" }!
        XCTAssertEqual(updatedClaude.state, .dormant, "Claude should return to dormant state")
    }
}

// MARK: - Test Extensions

// Notification names are defined in WebSocketManager.swift