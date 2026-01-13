import Foundation
import Testing
import SwiftCheck
@testable import DormantChat

@Suite("Dormant Chat Core Models")
struct DormantChatTests {
    
    @Test("LLMAgent initialization")
    func testLLMAgentInitialization() {
        let agent = LLMAgent(
            name: "TestAgent",
            provider: .openai,
            model: "gpt-4"
        )
        
        #expect(agent.name == "TestAgent")
        #expect(agent.provider == .openai)
        #expect(agent.model == "gpt-4")
        #expect(agent.state == .dormant)
        #expect(agent.temperature == 0.7)
        #expect(agent.maxTokens == 1000)
        #expect(agent.lastWakeTime == nil)
    }
    
    @Test("ChatMessage mention extraction")
    func testChatMessageMentionExtraction() {
        let message = ChatMessage(
            content: "Hey @alice and @bob, what do you think?",
            sender: .human(userId: "user1", username: "TestUser"),
            roomId: UUID()
        )
        
        let mentions = message.extractMentions()
        #expect(mentions.count == 2)
        #expect(mentions.contains("alice"))
        #expect(mentions.contains("bob"))
    }
    
    @Test("MentionScanner basic extraction")
    func testMentionScannerBasicExtraction() {
        let scanner = MentionScanner()
        
        // Test basic mention extraction
        let mentions1 = scanner.extractMentions(from: "Hello @alice and @bob!")
        #expect(mentions1.count == 2)
        #expect(mentions1.contains("alice"))
        #expect(mentions1.contains("bob"))
        
        // Test no mentions
        let mentions2 = scanner.extractMentions(from: "Hello world!")
        #expect(mentions2.isEmpty)
        
        // Test single mention
        let mentions3 = scanner.extractMentions(from: "Hey @charlie")
        #expect(mentions3.count == 1)
        #expect(mentions3.contains("charlie"))
        
        // Test mention with numbers and underscores
        let mentions4 = scanner.extractMentions(from: "Contact @user_123 please")
        #expect(mentions4.count == 1)
        #expect(mentions4.contains("user_123"))
    }
    
    @Test("MentionScanner autocomplete suggestions")
    func testMentionScannerAutocompleteSuggestions() {
        let scanner = MentionScanner()
        let agents = [
            LLMAgent(name: "alice", provider: .openai, model: "gpt-4"),
            LLMAgent(name: "bob", provider: .anthropic, model: "claude-3"),
            LLMAgent(name: "charlie", provider: .openai, model: "gpt-3.5"),
            LLMAgent(name: "alex", provider: .ollama, model: "llama2")
        ]
        
        // Test empty partial - should return all agents sorted
        let suggestions1 = scanner.buildMentionSuggestions(for: "", agents: agents)
        #expect(suggestions1.count == 4)
        #expect(suggestions1 == ["alex", "alice", "bob", "charlie"])
        
        // Test partial match - should return agents starting with "a"
        let suggestions2 = scanner.buildMentionSuggestions(for: "a", agents: agents)
        #expect(suggestions2.count == 2)
        #expect(suggestions2.contains("alice"))
        #expect(suggestions2.contains("alex"))
        
        // Test exact prefix match
        let suggestions3 = scanner.buildMentionSuggestions(for: "al", agents: agents)
        #expect(suggestions3.count == 2)
        #expect(suggestions3.contains("alice"))
        #expect(suggestions3.contains("alex"))
        
        // Test no matches
        let suggestions4 = scanner.buildMentionSuggestions(for: "xyz", agents: agents)
        #expect(suggestions4.isEmpty)
        
        // Test case insensitive matching
        let suggestions5 = scanner.buildMentionSuggestions(for: "ALICE", agents: agents)
        #expect(suggestions5.count == 1)
        #expect(suggestions5.contains("alice"))
        
        // Test single character match
        let suggestions6 = scanner.buildMentionSuggestions(for: "b", agents: agents)
        #expect(suggestions6.count == 1)
        #expect(suggestions6.contains("bob"))
    }
    
    @Test("MentionScanner mention validation")
    func testMentionScannerMentionValidation() {
        let scanner = MentionScanner()
        let agents = [
            LLMAgent(name: "alice", provider: .openai, model: "gpt-4"),
            LLMAgent(name: "Bob", provider: .anthropic, model: "claude-3"),
            LLMAgent(name: "Charlie", provider: .openai, model: "gpt-3.5")
        ]
        
        // Test valid mention - exact case
        let validAgent1 = scanner.validateMention("alice", against: agents)
        #expect(validAgent1?.name == "alice")
        
        // Test valid mention - case insensitive
        let validAgent2 = scanner.validateMention("ALICE", against: agents)
        #expect(validAgent2?.name == "alice")
        
        let validAgent3 = scanner.validateMention("bob", against: agents)
        #expect(validAgent3?.name == "Bob")
        
        // Test invalid mention
        let invalidAgent = scanner.validateMention("nonexistent", against: agents)
        #expect(invalidAgent == nil)
        
        // Test empty mention
        let emptyAgent = scanner.validateMention("", against: agents)
        #expect(emptyAgent == nil)
    }
    
    @Test("MentionScanner partial mention detection")
    func testMentionScannerPartialMentionDetection() {
        let scanner = MentionScanner()
        
        // Test finding partial mentions
        let partials1 = scanner.findPartialMentions(in: "Hello @al and @bob")
        #expect(partials1.count == 2)
        #expect(partials1.contains("@al"))
        #expect(partials1.contains("@bob"))
        
        // Test incomplete mention at end
        let partials2 = scanner.findPartialMentions(in: "Hey @")
        #expect(partials2.count == 1)
        #expect(partials2.contains("@"))
        
        // Test no mentions
        let partials3 = scanner.findPartialMentions(in: "No mentions here")
        #expect(partials3.isEmpty)
    }
    
    @Test("MentionScanner current partial mention at cursor")
    func testMentionScannerCurrentPartialMentionAtCursor() {
        let scanner = MentionScanner()
        
        // Test cursor at end of partial mention
        let partial1 = scanner.getCurrentPartialMention(in: "Hello @al", at: 9)
        #expect(partial1 == "al")
        
        // Test cursor in middle of partial mention
        let partial2 = scanner.getCurrentPartialMention(in: "Hello @alice", at: 8)
        #expect(partial2 == "a")
        
        // Test cursor not in mention
        let partial3 = scanner.getCurrentPartialMention(in: "Hello @alice world", at: 15)
        #expect(partial3 == nil)
        
        // Test cursor at @ symbol
        let partial4 = scanner.getCurrentPartialMention(in: "Hello @", at: 7)
        #expect(partial4 == "")
        
        // Test no mention
        let partial5 = scanner.getCurrentPartialMention(in: "Hello world", at: 5)
        #expect(partial5 == nil)
    }
    
    @Test("MentionScanner mention replacement")
    func testMentionScannerMentionReplacement() {
        let scanner = MentionScanner()
        
        // Test replacing partial mention
        let result1 = scanner.replaceMention(in: "Hello @al", replacing: "@al", with: "alice")
        #expect(result1 == "Hello @alice")
        
        // Test replacing multiple occurrences
        let result2 = scanner.replaceMention(in: "@al says hi to @al", replacing: "@al", with: "alice")
        #expect(result2 == "@alice says hi to @alice")
        
        // Test no replacement needed
        let result3 = scanner.replaceMention(in: "Hello world", replacing: "@al", with: "alice")
        #expect(result3 == "Hello world")
    }
    
    @Test("ChatRoom participant management")
    func testChatRoomParticipantManagement() {
        var room = ChatRoom(name: "Test Room")
        
        #expect(room.participants.isEmpty)
        
        room.addParticipant("user1")
        #expect(room.participants.count == 1)
        #expect(room.isParticipant("user1"))
        
        room.addParticipant("user1") // Should not add duplicate
        #expect(room.participants.count == 1)
        
        room.addParticipant("user2")
        #expect(room.participants.count == 2)
        
        room.removeParticipant("user1")
        #expect(room.participants.count == 1)
        #expect(!room.isParticipant("user1"))
        #expect(room.isParticipant("user2"))
    }
    
    @Test("AgentState properties")
    func testAgentStateProperties() {
        #expect(AgentState.dormant.isActive == false)
        #expect(AgentState.awake.isActive == true)
        #expect(AgentState.thinking.isActive == true)
        
        #expect(AgentState.dormant.displayName == "Dormant")
        #expect(AgentState.awake.displayName == "Awake")
        #expect(AgentState.thinking.displayName == "Thinking")
    }
    
    @Test("LLMProvider properties")
    func testLLMProviderProperties() {
        #expect(LLMProvider.ollama.requiresAPIKey == false)
        #expect(LLMProvider.openai.requiresAPIKey == true)
        #expect(LLMProvider.anthropic.requiresAPIKey == true)
        
        #expect(!LLMProvider.openai.defaultModels.isEmpty)
        #expect(!LLMProvider.anthropic.defaultModels.isEmpty)
        #expect(LLMProvider.custom.defaultModels.isEmpty)
    }
    
    @Test("MessageSender type checking")
    func testMessageSenderTypeChecking() {
        let humanSender = MessageSender.human(userId: "user1", username: "Alice")
        let llmSender = MessageSender.llm(agentId: UUID(), agentName: "GPT", provider: .openai)
        let systemSender = MessageSender.system(type: .agentWake)
        
        #expect(humanSender.isHuman == true)
        #expect(humanSender.isLLM == false)
        #expect(humanSender.isSystem == false)
        
        #expect(llmSender.isHuman == false)
        #expect(llmSender.isLLM == true)
        #expect(llmSender.isSystem == false)
        
        #expect(systemSender.isHuman == false)
        #expect(systemSender.isLLM == false)
        #expect(systemSender.isSystem == true)
    }
    
    @Test("Feature: dormant-chat, Property 12: Agent Configuration Validation")
    func testAgentConfigurationValidation() throws {
        // Property: For any agent creation attempt, it should fail validation if required fields are missing
        // Validates: Requirements 4.2
        
        try property("Agent validation requires non-empty name") <- forAll(String.arbitrary, LLMProvider.arbitrary, String.arbitrary) { (name: String, provider: LLMProvider, model: String) in
            let agent = LLMAgent(name: name, provider: provider, model: model)
            let isValid = AgentValidator.isValid(agent)
            
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return !isValid
            } else if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return !isValid
            } else {
                return isValid
            }
        }
    }
    
    @Test("Feature: dormant-chat, Property 5: Mention-Based Wake Triggering")
    func testMentionBasedWakeTriggering() throws {
        // Property: For any message containing @agentName syntax, the mentioned agent should transition from dormant to awake state
        // Validates: Requirements 2.2
        
        try property("Messages with @mentions should trigger agent wake") <- forAll(String.arbitrary, String.arbitrary) { (messagePrefix: String, agentName: String) in
            let scanner = MentionScanner()
            let trimmedAgentName = agentName.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty agent names as they're invalid
            guard !trimmedAgentName.isEmpty && trimmedAgentName.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
                return true
            }
            
            let messageWithMention = "\(messagePrefix) @\(trimmedAgentName)"
            let extractedMentions = scanner.extractMentions(from: messageWithMention)
            
            // The mention should be extracted from the message
            return extractedMentions.contains(trimmedAgentName)
        }
    }
    
    @Test("Feature: dormant-chat, Property 16: Mention Autocomplete Functionality")
    func testMentionAutocompleteFunctionality() throws {
        // Property: For any partial @mention input, the system should provide relevant agent suggestions and complete correctly
        // Validates: Requirements 5.5
        
        try property("Partial mentions should provide relevant suggestions") <- forAll(String.arbitrary) { (partialMention: String) in
            let scanner = MentionScanner()
            let agents = [
                LLMAgent(name: "alice", provider: .openai, model: "gpt-4"),
                LLMAgent(name: "bob", provider: .anthropic, model: "claude-3"),
                LLMAgent(name: "charlie", provider: .openai, model: "gpt-3.5"),
                LLMAgent(name: "alex", provider: .ollama, model: "llama2")
            ]
            
            let suggestions = scanner.buildMentionSuggestions(for: partialMention, agents: agents)
            
            // All suggestions should start with the partial mention (case insensitive)
            let lowercasePartial = partialMention.lowercased()
            
            if lowercasePartial.isEmpty {
                // Empty partial should return all agents
                return suggestions.count == agents.count
            } else {
                // All suggestions should start with the partial
                return suggestions.allSatisfy { suggestion in
                    suggestion.lowercased().hasPrefix(lowercasePartial)
                }
            }
        }
    }
}