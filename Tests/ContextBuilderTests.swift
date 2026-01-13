import Testing
import Foundation
@testable import DormantChat

@Suite("Context Builder")
struct ContextBuilderTests {
    
    @Test("Context builder creates valid context")
    func testContextBuilding() async throws {
        let builder = ContextBuilder()
        
        // Create test agent
        let agent = LLMAgent(
            name: "TestAgent",
            provider: .openai,
            model: "gpt-4",
            personality: "You are a helpful assistant"
        )
        
        // Create test messages
        let roomId = UUID()
        let messages = [
            ChatMessage(
                content: "Hello everyone!",
                sender: .human(userId: "user1", username: "Alice"),
                timestamp: Date().addingTimeInterval(-60),
                roomId: roomId
            ),
            ChatMessage(
                content: "@TestAgent can you help?",
                sender: .human(userId: "user2", username: "Bob"),
                timestamp: Date(),
                roomId: roomId
            )
        ]
        
        // Build context
        let context = builder.buildContext(for: agent, from: messages)
        
        // Verify context structure
        #expect(!context.systemPrompt.isEmpty)
        #expect(context.systemPrompt.contains("TestAgent"))
        #expect(context.systemPrompt.contains("helpful assistant"))
        #expect(context.conversationHistory.count == 2)
        #expect(context.metadata.agentId == agent.id)
        #expect(context.metadata.roomId == roomId)
        #expect(context.metadata.totalMessages == 2)
        
        // Verify messages are sorted by timestamp
        let sortedMessages = context.conversationHistory
        #expect(sortedMessages[0].timestamp <= sortedMessages[1].timestamp)
    }
    
    @Test("System prompt formatting includes personality")
    func testSystemPromptFormatting() async throws {
        let builder = ContextBuilder()
        
        let agent = LLMAgent(
            name: "CreativeBot",
            provider: .anthropic,
            model: "claude-3-sonnet",
            personality: "You are a creative writing assistant who loves poetry and storytelling."
        )
        
        let systemPrompt = builder.formatSystemPrompt(for: agent)
        
        #expect(systemPrompt.contains("CreativeBot"))
        #expect(systemPrompt.contains("creative writing assistant"))
        #expect(systemPrompt.contains("poetry and storytelling"))
        #expect(systemPrompt.contains("claude-3-sonnet"))
        #expect(systemPrompt.contains("Anthropic"))
        #expect(systemPrompt.contains("@CreativeBot"))
    }
    
    @Test("Context builder handles empty message list")
    func testEmptyMessageList() async throws {
        let builder = ContextBuilder()
        
        let agent = LLMAgent(
            name: "EmptyBot",
            provider: .openai,
            model: "gpt-3.5-turbo"
        )
        
        let context = builder.buildContext(for: agent, from: [])
        
        #expect(!context.systemPrompt.isEmpty)
        #expect(context.conversationHistory.isEmpty)
        #expect(context.metadata.totalMessages == 0)
        #expect(context.metadata.agentId == agent.id)
    }
    
    @Test("Context builder sorts messages chronologically")
    func testMessageSorting() async throws {
        let builder = ContextBuilder()
        let agent = LLMAgent(name: "SortBot", provider: .openai, model: "gpt-4")
        let roomId = UUID()
        
        let now = Date()
        let messages = [
            ChatMessage(
                content: "Third message",
                sender: .human(userId: "user1", username: "Alice"),
                timestamp: now.addingTimeInterval(120), // +2 minutes
                roomId: roomId
            ),
            ChatMessage(
                content: "First message",
                sender: .human(userId: "user2", username: "Bob"),
                timestamp: now.addingTimeInterval(-60), // -1 minute
                roomId: roomId
            ),
            ChatMessage(
                content: "Second message",
                sender: .human(userId: "user3", username: "Charlie"),
                timestamp: now, // now
                roomId: roomId
            )
        ]
        
        let context = builder.buildContext(for: agent, from: messages)
        
        #expect(context.conversationHistory.count == 3)
        #expect(context.conversationHistory[0].content == "First message")
        #expect(context.conversationHistory[1].content == "Second message")
        #expect(context.conversationHistory[2].content == "Third message")
    }
    
    @Test("Context builder includes different message types")
    func testDifferentMessageTypes() async throws {
        let builder = ContextBuilder()
        let agent = LLMAgent(name: "TypeBot", provider: .openai, model: "gpt-4")
        let roomId = UUID()
        
        let messages = [
            ChatMessage(
                content: "Human message",
                sender: .human(userId: "user1", username: "Alice"),
                roomId: roomId
            ),
            ChatMessage(
                content: "LLM response",
                sender: .llm(agentId: UUID(), agentName: "OtherBot", provider: .anthropic),
                roomId: roomId
            ),
            ChatMessage(
                content: "System notification",
                sender: .system(type: .agentWake),
                roomId: roomId
            )
        ]
        
        let context = builder.buildContext(for: agent, from: messages)
        
        #expect(context.conversationHistory.count == 3)
        
        // Verify all message types are included
        let senders = context.conversationHistory.map { $0.sender }
        #expect(senders.contains { $0.isHuman })
        #expect(senders.contains { $0.isLLM })
        #expect(senders.contains { $0.isSystem })
    }
}