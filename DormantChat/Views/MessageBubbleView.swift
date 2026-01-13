import SwiftUI

/// Message bubble view for displaying chat messages
struct MessageBubbleView: View {
    let message: ChatMessage
    let isFromCurrentUser: Bool
    
    init(message: ChatMessage, currentUserId: String = "current-user") {
        self.message = message
        // Determine if message is from current user based on sender
        switch message.sender {
        case .human(let userId, _):
            self.isFromCurrentUser = userId == currentUserId
        case .llm, .system:
            self.isFromCurrentUser = false
        }
    }
    
    var body: some View {
        HStack {
            if isFromCurrentUser {
                Spacer()
                humanMessageBubble
            } else {
                llmMessageBubble
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
    
    // MARK: - Human Message Bubble (Gray, Right-aligned)
    
    private var humanMessageBubble: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Text(message.content)
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.gray.opacity(0.2))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }
            
            Text(formatTimestamp(message.timestamp))
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.trailing, 8)
        }
    }
    
    // MARK: - LLM Message Bubble (Blue, Left-aligned with name tag)
    
    private var llmMessageBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Agent name tag
            if case .llm(_, let agentName, let provider) = message.sender {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.blue.opacity(0.8))
                        .frame(width: 8, height: 8)
                    
                    Text(agentName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                    
                    Text("(\(provider.displayName))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 16)
            }
            
            HStack {
                Text(message.content)
                    .font(.body)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.blue)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.blue.opacity(0.8), lineWidth: 1)
                    )
            }
            
            Text(formatTimestamp(message.timestamp))
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.leading, 16)
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatTimestamp(_ timestamp: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

// MARK: - System Message View

struct SystemMessageView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            Spacer()
            
            VStack(spacing: 4) {
                Text(message.content)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.1))
                    )
                
                Text(formatTimestamp(message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }
    
    private func formatTimestamp(_ timestamp: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

// MARK: - Typing Indicator View

struct TypingIndicatorView: View {
    let agentName: String
    let provider: LLMProvider
    @State private var animationPhase: Int = 0
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                // Agent name tag
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.blue.opacity(0.8))
                        .frame(width: 8, height: 8)
                    
                    Text(agentName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                    
                    Text("(\(provider.displayName))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 16)
                
                // Typing animation
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.blue.opacity(0.6))
                            .frame(width: 8, height: 8)
                            .scaleEffect(animationPhase == index ? 1.2 : 0.8)
                            .animation(
                                .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2),
                                value: animationPhase
                            )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.blue.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .onAppear {
            startTypingAnimation()
        }
    }
    
    private func startTypingAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
            withAnimation {
                animationPhase = (animationPhase + 1) % 3
            }
        }
    }
}

// MARK: - Preview

#Preview("Human Message") {
    let humanMessage = ChatMessage(
        content: "Hello, can you help me with this task?",
        sender: .human(userId: "current-user", username: "John"),
        roomId: UUID()
    )
    
    return MessageBubbleView(message: humanMessage, currentUserId: "current-user")
        .padding()
}

#Preview("LLM Message") {
    let llmMessage = ChatMessage(
        content: "Of course! I'd be happy to help you with that task. What specifically do you need assistance with?",
        sender: .llm(agentId: UUID(), agentName: "Claude", provider: .anthropic),
        roomId: UUID()
    )
    
    return MessageBubbleView(message: llmMessage, currentUserId: "current-user")
        .padding()
}

#Preview("System Message") {
    let systemMessage = ChatMessage(
        content: "Claude has joined the conversation",
        sender: .system(type: .agentWake),
        roomId: UUID()
    )
    
    return SystemMessageView(message: systemMessage)
        .padding()
}

#Preview("Typing Indicator") {
    return TypingIndicatorView(agentName: "GPT-4", provider: .openai)
        .padding()
}