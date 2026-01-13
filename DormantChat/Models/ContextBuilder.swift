import Foundation

/// Builds conversation context for LLM agents when they wake up
struct ContextBuilder {
    
    // MARK: - Context Building
    
    /// Build complete context for an LLM agent from conversation messages
    /// - Parameters:
    ///   - agent: The agent to build context for
    ///   - messages: The conversation messages to include in context
    /// - Returns: Complete LLM context ready for API call
    func buildContext(for agent: LLMAgent, from messages: [ChatMessage]) -> LLMContext {
        // Sort messages by timestamp to ensure chronological order
        let sortedMessages = messages.sorted { $0.timestamp < $1.timestamp }
        
        // Build system prompt
        let systemPrompt = formatSystemPrompt(for: agent)
        
        // Create metadata
        let metadata = ContextMetadata(
            roomId: sortedMessages.first?.roomId ?? UUID(),
            agentId: agent.id,
            wakeTime: Date(),
            totalMessages: sortedMessages.count,
            contextWindowSize: getContextWindowSize(for: agent)
        )
        
        // Filter messages to fit within context window if necessary
        let contextMessages = filterMessagesForContextWindow(
            messages: sortedMessages,
            agent: agent,
            systemPromptTokens: estimateTokens(systemPrompt, for: agent)
        )
        
        return LLMContext(
            systemPrompt: systemPrompt,
            conversationHistory: contextMessages,
            metadata: metadata
        )
    }
    
    /// Format the system prompt for an agent including personality and instructions
    /// - Parameter agent: The agent to format prompt for
    /// - Returns: Complete system prompt string
    func formatSystemPrompt(for agent: LLMAgent) -> String {
        var prompt = """
        You are \(agent.name), an AI assistant participating in a chat room conversation.
        
        IMPORTANT INSTRUCTIONS:
        - You are currently AWAKE and can see and respond to messages
        - You were awakened because someone mentioned you with @\(agent.name)
        - After you respond, you will return to DORMANT state and won't see further messages until mentioned again
        - If you want to wake another AI agent, mention them with @agentname in your response
        - Be conversational and helpful while staying true to your personality
        - Keep responses concise unless specifically asked for detailed explanations
        
        """
        
        // Add personality if specified
        if !agent.personality.trimmingCharacters(in: .whitespaces).isEmpty {
            prompt += """
            PERSONALITY:
            \(agent.personality)
            
            """
        }
        
        // Add provider-specific instructions
        switch agent.provider {
        case .openai:
            prompt += """
            TECHNICAL DETAILS:
            - You are powered by OpenAI's \(agent.model) model
            - Temperature: \(agent.temperature)
            - Max tokens: \(agent.maxTokens)
            
            """
        case .anthropic:
            prompt += """
            TECHNICAL DETAILS:
            - You are powered by Anthropic's \(agent.model) model
            - Temperature: \(agent.temperature)
            - Max tokens: \(agent.maxTokens)
            
            """
        case .gemini:
            prompt += """
            TECHNICAL DETAILS:
            - You are powered by Google's \(agent.model) model
            - Temperature: \(agent.temperature)
            - Max tokens: \(agent.maxTokens)
            
            """
        case .grok:
            prompt += """
            TECHNICAL DETAILS:
            - You are powered by xAI's \(agent.model) model
            - Temperature: \(agent.temperature)
            - Max tokens: \(agent.maxTokens)
            
            """
        case .cohere:
            prompt += """
            TECHNICAL DETAILS:
            - You are powered by Cohere's \(agent.model) model
            - Temperature: \(agent.temperature)
            - Max tokens: \(agent.maxTokens)
            
            """
        case .mistral:
            prompt += """
            TECHNICAL DETAILS:
            - You are powered by Mistral AI's \(agent.model) model
            - Temperature: \(agent.temperature)
            - Max tokens: \(agent.maxTokens)
            
            """
        case .perplexity:
            prompt += """
            TECHNICAL DETAILS:
            - You are powered by Perplexity's \(agent.model) model
            - Temperature: \(agent.temperature)
            - Max tokens: \(agent.maxTokens)
            
            """
        case .together:
            prompt += """
            TECHNICAL DETAILS:
            - You are powered by Together AI's \(agent.model) model
            - Temperature: \(agent.temperature)
            - Max tokens: \(agent.maxTokens)
            
            """
        case .replicate:
            prompt += """
            TECHNICAL DETAILS:
            - You are powered by Replicate's \(agent.model) model
            - Temperature: \(agent.temperature)
            - Max tokens: \(agent.maxTokens)
            
            """
        case .groq:
            prompt += """
            TECHNICAL DETAILS:
            - You are powered by Groq's \(agent.model) model
            - Temperature: \(agent.temperature)
            - Max tokens: \(agent.maxTokens)
            
            """
        case .huggingface, .ollama, .custom:
            prompt += """
            TECHNICAL DETAILS:
            - Provider: \(agent.provider.displayName)
            - Model: \(agent.model)
            - Temperature: \(agent.temperature)
            - Max tokens: \(agent.maxTokens)
            
            """
        }
        
        prompt += """
        Now respond to the conversation below as \(agent.name):
        """
        
        return prompt
    }
    
    /// Clear context for an agent (called when agent goes dormant)
    /// - Parameter agentId: The ID of the agent to clear context for
    func clearContext(for agentId: UUID) {
        // This is a placeholder for any cleanup operations
        // In the current implementation, context is managed by AgentStateManager
        // This method exists for future extensibility (e.g., if we add persistent context storage)
        print("Clearing context for agent \(agentId)")
    }
    
    // MARK: - Private Helper Methods
    
    /// Filter messages to fit within the agent's context window
    /// - Parameters:
    ///   - messages: All available messages
    ///   - agent: The agent whose context window to respect
    ///   - systemPromptTokens: Number of tokens used by system prompt
    /// - Returns: Filtered messages that fit in context window
    private func filterMessagesForContextWindow(
        messages: [ChatMessage],
        agent: LLMAgent,
        systemPromptTokens: Int
    ) -> [ChatMessage] {
        let maxContextTokens = getContextWindowSize(for: agent)
        let availableTokens = maxContextTokens - systemPromptTokens - agent.maxTokens // Reserve space for response
        
        guard availableTokens > 0 else {
            print("Warning: System prompt uses too many tokens, returning empty context")
            return []
        }
        
        var selectedMessages: [ChatMessage] = []
        var currentTokens = 0
        
        // Start from the most recent messages and work backwards
        for message in messages.reversed() {
            let messageTokens = estimateMessageTokens(message, for: agent)
            
            if currentTokens + messageTokens <= availableTokens {
                selectedMessages.insert(message, at: 0) // Insert at beginning to maintain chronological order
                currentTokens += messageTokens
            } else {
                break // Stop adding messages if we exceed context window
            }
        }
        
        if selectedMessages.count < messages.count {
            print("Context window limit reached: using \(selectedMessages.count) of \(messages.count) messages")
        }
        
        return selectedMessages
    }
    
    /// Estimate tokens for a single message
    /// - Parameters:
    ///   - message: The message to estimate tokens for
    ///   - agent: The agent (for provider-specific token estimation)
    /// - Returns: Estimated token count for the message
    private func estimateMessageTokens(_ message: ChatMessage, for agent: LLMAgent) -> Int {
        // Format the message as it would appear in the context
        let formattedMessage = formatMessageForContext(message)
        return estimateTokens(formattedMessage, for: agent)
    }
    
    /// Format a message for inclusion in LLM context
    /// - Parameter message: The message to format
    /// - Returns: Formatted message string
    private func formatMessageForContext(_ message: ChatMessage) -> String {
        let timestamp = formatTimestamp(message.timestamp)
        
        switch message.sender {
        case .human(_, let username):
            return "[\(timestamp)] \(username): \(message.content)"
        case .llm(_, let agentName, let provider):
            return "[\(timestamp)] \(agentName) (\(provider.displayName)): \(message.content)"
        case .system(let type):
            return "[\(timestamp)] System (\(type)): \(message.content)"
        }
    }
    
    /// Format timestamp for display in context
    /// - Parameter date: The date to format
    /// - Returns: Formatted timestamp string
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
    
    /// Get context window size for an agent
    /// - Parameter agent: The agent to get context window size for
    /// - Returns: Context window size in tokens
    private func getContextWindowSize(for agent: LLMAgent) -> Int {
        do {
            return try LLMProviderFactory.shared.getContextWindowSize(for: agent)
        } catch {
            print("Warning: Could not get context window size for \(agent.name), using default")
            return 4096 // Default fallback
        }
    }
    
    /// Estimate tokens for text using the agent's provider
    /// - Parameters:
    ///   - text: The text to estimate tokens for
    ///   - agent: The agent (for provider-specific estimation)
    /// - Returns: Estimated token count
    private func estimateTokens(_ text: String, for agent: LLMAgent) -> Int {
        do {
            return try LLMProviderFactory.shared.estimateTokens(text, using: agent.provider)
        } catch {
            // Fallback to simple word-based estimation
            let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            return Int(Double(words.count) * 1.3) // Rough approximation: 1.3 tokens per word
        }
    }
}

// MARK: - Extensions

extension ContextBuilder {
    /// Create a minimal context for testing purposes
    /// - Parameters:
    ///   - agent: The agent to create context for
    ///   - messageCount: Number of test messages to include
    /// - Returns: Test context
    static func createTestContext(for agent: LLMAgent, messageCount: Int = 5) -> LLMContext {
        let builder = ContextBuilder()
        let testMessages = (1...messageCount).map { i in
            ChatMessage(
                content: "Test message \(i)",
                sender: .human(userId: "test-user", username: "TestUser"),
                roomId: UUID()
            )
        }
        return builder.buildContext(for: agent, from: testMessages)
    }
}