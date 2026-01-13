import SwiftUI
import Combine

/// Main chat timeline view displaying messages and typing indicators
struct ChatTimelineView: View {
    @StateObject private var viewModel = ChatTimelineViewModel()
    @State private var scrollProxy: ScrollViewProxy?
    
    let currentUserId: String
    let roomId: UUID
    
    init(currentUserId: String = "current-user", roomId: UUID) {
        self.currentUserId = currentUserId
        self.roomId = roomId
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Chat messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.messages) { message in
                            messageView(for: message)
                                .id(message.id)
                        }
                        
                        // Typing indicators
                        ForEach(viewModel.typingAgents, id: \.agentId) { typingAgent in
                            TypingIndicatorView(
                                agentName: typingAgent.agentName,
                                provider: typingAgent.provider
                            )
                            .id("typing-\(typingAgent.agentId)")
                        }
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                }
                .onAppear {
                    scrollProxy = proxy
                }
                .onChange(of: viewModel.messages.count) { _ in
                    scrollToBottom()
                }
                .onChange(of: viewModel.typingAgents.count) { _ in
                    scrollToBottom()
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            viewModel.loadMessages(for: roomId)
        }
    }
    
    // MARK: - Message View Builder
    
    @ViewBuilder
    private func messageView(for message: ChatMessage) -> some View {
        switch message.sender {
        case .system:
            SystemMessageView(message: message)
        case .human, .llm:
            MessageBubbleView(message: message, currentUserId: currentUserId)
        }
    }
    
    // MARK: - Helper Methods
    
    private func scrollToBottom() {
        guard let proxy = scrollProxy else { return }
        
        withAnimation(.easeOut(duration: 0.3)) {
            if let lastMessage = viewModel.messages.last {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            } else if let lastTyping = viewModel.typingAgents.last {
                proxy.scrollTo("typing-\(lastTyping.agentId)", anchor: .bottom)
            }
        }
    }
}

// MARK: - Chat Timeline View Model

@MainActor
class ChatTimelineViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var typingAgents: [TypingAgent] = []
    
    private var messageSubscription: AnyCancellable?
    
    init() {
        setupMessageSubscription()
    }
    
    // MARK: - Message Management
    
    func loadMessages(for roomId: UUID) {
        // In a real app, this would load from local storage or server
        // For now, we'll start with an empty array
        messages = []
    }
    
    func addMessage(_ message: ChatMessage) {
        messages.append(message)
    }
    
    func addSystemMessage(_ content: String, type: SystemMessageType, roomId: UUID) {
        let systemMessage = ChatMessage(
            content: content,
            sender: .system(type: type),
            roomId: roomId
        )
        addMessage(systemMessage)
    }
    
    // MARK: - Typing Indicators
    
    func startTyping(agentId: UUID, agentName: String, provider: LLMProvider) {
        let typingAgent = TypingAgent(
            agentId: agentId,
            agentName: agentName,
            provider: provider
        )
        
        if !typingAgents.contains(where: { $0.agentId == agentId }) {
            typingAgents.append(typingAgent)
        }
    }
    
    func stopTyping(agentId: UUID) {
        typingAgents.removeAll { $0.agentId == agentId }
    }
    
    func stopAllTyping() {
        typingAgents.removeAll()
    }
    
    // MARK: - Message Subscription
    
    private func setupMessageSubscription() {
        // Subscribe to new message notifications
        messageSubscription = NotificationCenter.default
            .publisher(for: .newChatMessage)
            .compactMap { $0.object as? ChatMessage }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.addMessage(message)
            }
    }
    
    deinit {
        messageSubscription?.cancel()
    }
}

// MARK: - Supporting Types

struct TypingAgent: Identifiable, Equatable {
    let id = UUID()
    let agentId: UUID
    let agentName: String
    let provider: LLMProvider
    
    static func == (lhs: TypingAgent, rhs: TypingAgent) -> Bool {
        return lhs.agentId == rhs.agentId
    }
}

// MARK: - Preview

#Preview {
    let roomId = UUID()
    
    return ChatTimelineView(currentUserId: "user-123", roomId: roomId)
        .frame(height: 600)
        .onAppear {
            // Add some sample messages for preview
            let timeline = ChatTimelineViewModel()
            
            let humanMessage = ChatMessage(
                content: "Hello! Can you help me understand how encryption works?",
                sender: .human(userId: "user-123", username: "Alice"),
                roomId: roomId
            )
            timeline.addMessage(humanMessage)
            
            let systemMessage = ChatMessage(
                content: "Claude has been awakened",
                sender: .system(type: .agentWake),
                roomId: roomId
            )
            timeline.addMessage(systemMessage)
            
            // Start typing indicator
            timeline.startTyping(
                agentId: UUID(),
                agentName: "Claude",
                provider: .anthropic
            )
        }
}