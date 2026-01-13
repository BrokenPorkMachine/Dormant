import SwiftUI
import Combine

struct ContentView: View {
    var body: some View {
        MainWindowView()
    }
}

// MARK: - Chat View Model

@MainActor
class ChatViewModel: ObservableObject {
    @Published var availableAgents: [LLMAgent] = []
    
    private let errorHandler = ErrorHandler.shared
    private let logger = DormantLogger.shared
    
    init() {
        setupSampleAgents()
    }
    
    private func setupSampleAgents() {
        availableAgents = [
            LLMAgent(
                name: "Claude",
                provider: .anthropic,
                model: "claude-3-sonnet",
                personality: "Helpful and thoughtful AI assistant with a focus on accuracy and nuance.",
                state: .dormant
            ),
            LLMAgent(
                name: "GPT-4",
                provider: .openai,
                model: "gpt-4",
                personality: "Creative and analytical AI assistant that excels at problem-solving.",
                state: .dormant
            ),
            LLMAgent(
                name: "Gemini",
                provider: .gemini,
                model: "gemini-1.5-pro",
                personality: "Knowledgeable AI assistant with strong reasoning capabilities.",
                state: .dormant
            ),
            LLMAgent(
                name: "Grok",
                provider: .grok,
                model: "grok-beta",
                personality: "Witty and direct AI assistant with a unique perspective.",
                state: .dormant
            ),
            LLMAgent(
                name: "Llama",
                provider: .ollama,
                model: "llama3",
                personality: "Local AI assistant focused on privacy and offline capabilities.",
                state: .dormant
            )
        ]
        
        logger.info("Initialized \(availableAgents.count) sample agents", category: .general)
    }
    
    func sendMessage(_ content: String, roomId: UUID, agentManager: AgentStateManager) {
        logger.logUserAction("Send message", context: "Room: \(roomId)")
        
        let message = ChatMessage(
            content: content,
            sender: .human(userId: "current-user", username: "You"),
            roomId: roomId
        )
        
        // Post notification for the timeline to pick up
        NotificationCenter.default.post(
            name: .newChatMessage,
            object: message
        )
        
        // Check for mentions and wake agents
        let mentions = message.extractMentions()
        logger.debug("Found \(mentions.count) mentions in message", category: .llm)
        
        for mention in mentions {
            if let agent = agentManager.agents.first(where: { $0.name.lowercased() == mention.lowercased() }) {
                Task {
                    await wakeAgent(agent, in: roomId, agentManager: agentManager, triggeringMessage: message)
                }
            } else {
                logger.warning("Mentioned agent '\(mention)' not found", category: .llm)
                errorHandler.handle(
                    .validation(.invalidInput("Agent '\(mention)' not found")),
                    context: "Agent mention",
                    showToUser: false
                )
            }
        }
    }
    
    private func wakeAgent(_ agent: LLMAgent, in roomId: UUID, agentManager: AgentStateManager, triggeringMessage: ChatMessage) async {
        logger.info("Waking agent: \(agent.name)", category: .llm)
        
        // Update agent state
        agentManager.wakeAgent(agent.id)
        
        // Send system message
        let systemMessage = ChatMessage(
            content: "\(agent.name) has been awakened",
            sender: .system(type: .agentWake),
            roomId: roomId
        )
        
        NotificationCenter.default.post(
            name: .newChatMessage,
            object: systemMessage
        )
        
        // Get conversation history for context
        let conversationHistory = await getConversationHistory(for: roomId)
        
        // Generate actual LLM response
        do {
            let response = try await generateLLMResponse(
                agent: agent,
                conversationHistory: conversationHistory,
                roomId: roomId
            )
            
            // Post the response
            NotificationCenter.default.post(
                name: .newChatMessage,
                object: response
            )
            
            // Check for cascading mentions in the response
            let cascadeMentions = response.extractMentions()
            if !cascadeMentions.isEmpty {
                logger.info("Found \(cascadeMentions.count) cascade mentions from \(agent.name)", category: .llm)
                
                for mention in cascadeMentions {
                    if let cascadeAgent = agentManager.agents.first(where: { $0.name.lowercased() == mention.lowercased() }),
                       cascadeAgent.id != agent.id { // Don't cascade to self
                        Task {
                            await wakeAgent(cascadeAgent, in: roomId, agentManager: agentManager, triggeringMessage: response)
                        }
                    }
                }
            }
            
        } catch {
            logger.error("Failed to generate LLM response for \(agent.name): \(error)", category: .llm)
            errorHandler.handle(error, context: "LLM response generation for \(agent.name)")
            
            // Send error message
            let errorMessage = ChatMessage(
                content: "Sorry, I encountered an error and couldn't respond. Please try again.",
                sender: .llm(agentId: agent.id, agentName: agent.name, provider: agent.provider),
                roomId: roomId
            )
            
            NotificationCenter.default.post(
                name: .newChatMessage,
                object: errorMessage
            )
        }
        
        // Return agent to dormant state after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            agentManager.sleepAgent(agent.id)
            self.logger.info("Agent \(agent.name) returned to dormant state", category: .llm)
        }
    }
    
    private func generateLLMResponse(agent: LLMAgent, conversationHistory: [ChatMessage], roomId: UUID) async throws -> ChatMessage {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Build context
        let contextBuilder = ContextBuilder()
        let context = contextBuilder.buildContext(for: agent, from: conversationHistory)
        
        // Get API key
        let keyVault = SecureKeyVault.shared
        guard let apiKey = try? keyVault.retrieveAPIKey(for: agent.provider) else {
            throw DormantError.authentication(.invalidAPIKey)
        }
        
        // Create provider
        let providerFactory = LLMProviderFactory.shared
        let provider = try providerFactory.createProvider(for: agent.provider)
        
        logger.logLLMRequest(
            provider: agent.provider,
            model: agent.model,
            tokenCount: provider.estimateTokens(context.systemPrompt + context.conversationHistory.map { $0.content }.joined())
        )
        
        // Generate response
        var responseContent = ""
        let responseStream = try await provider.generateResponse(
            context: context,
            agent: agent,
            apiKey: apiKey
        )
        
        for try await chunk in responseStream {
            responseContent += chunk
        }
        
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        logger.logLLMResponse(
            provider: agent.provider,
            responseTime: duration,
            tokenCount: provider.estimateTokens(responseContent)
        )
        
        return ChatMessage(
            content: responseContent.trimmingCharacters(in: .whitespacesAndNewlines),
            sender: .llm(agentId: agent.id, agentName: agent.name, provider: agent.provider),
            roomId: roomId
        )
    }
    
    private func getConversationHistory(for roomId: UUID) async -> [ChatMessage] {
        // In a real implementation, this would fetch from local storage
        // For now, we'll use a simple in-memory approach
        
        // This is a placeholder - in the real app, we'd fetch from LocalDataManager
        return []
    }
}

#Preview {
    ContentView()
}
