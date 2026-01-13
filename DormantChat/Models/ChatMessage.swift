import Foundation

/// Chat message model
struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let content: String
    let sender: MessageSender
    let timestamp: Date
    let roomId: UUID
    
    init(
        id: UUID = UUID(),
        content: String,
        sender: MessageSender,
        timestamp: Date = Date(),
        roomId: UUID
    ) {
        self.id = id
        self.content = content
        self.sender = sender
        self.timestamp = timestamp
        self.roomId = roomId
    }
    
    /// Check if this message contains mentions
    var containsMentions: Bool {
        return content.contains("@")
    }
    
    /// Extract @mentions from message content using MentionScanner
    func extractMentions() -> [String] {
        let scanner = MentionScanner()
        return scanner.extractMentions(from: content)
    }
}