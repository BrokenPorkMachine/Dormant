import Foundation

/// Chat room configuration
struct ChatRoom: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var participants: [String]
    var encryptionEnabled: Bool
    var encryptionKey: Data?
    var createdAt: Date
    
    init(
        id: UUID = UUID(),
        name: String,
        participants: [String] = [],
        encryptionEnabled: Bool = false,
        encryptionKey: Data? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.participants = participants
        self.encryptionEnabled = encryptionEnabled
        self.encryptionKey = encryptionKey
        self.createdAt = createdAt
    }
    
    /// Add a participant to the room
    mutating func addParticipant(_ userId: String) {
        if !participants.contains(userId) {
            participants.append(userId)
        }
    }
    
    /// Remove a participant from the room
    mutating func removeParticipant(_ userId: String) {
        participants.removeAll { $0 == userId }
    }
    
    /// Check if a user is a participant
    func isParticipant(_ userId: String) -> Bool {
        return participants.contains(userId)
    }
}