import Foundation
import CryptoKit
import Combine

/// Local data manager for persisting agents, messages, and rooms using JSON files
class LocalDataManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = LocalDataManager()
    
    // MARK: - File URLs
    
    private let documentsDirectory: URL
    private let agentsFileURL: URL
    private let roomsFileURL: URL
    private let messagesDirectoryURL: URL
    
    // MARK: - Encryption
    
    private let encryptionKey: SymmetricKey
    
    init() {
        // Get documents directory
        documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        // Create DormantChat directory
        let dormantDirectory = documentsDirectory.appendingPathComponent("DormantChat")
        try? FileManager.default.createDirectory(at: dormantDirectory, withIntermediateDirectories: true)
        
        // Set up file URLs
        agentsFileURL = dormantDirectory.appendingPathComponent("agents.json")
        roomsFileURL = dormantDirectory.appendingPathComponent("rooms.json")
        messagesDirectoryURL = dormantDirectory.appendingPathComponent("messages")
        
        // Create messages directory
        try? FileManager.default.createDirectory(at: messagesDirectoryURL, withIntermediateDirectories: true)
        
        // Initialize encryption key
        encryptionKey = Self.getOrCreateEncryptionKey()
    }
    
    // MARK: - Encryption Key Management
    
    private static func getOrCreateEncryptionKey() -> SymmetricKey {
        let keychain = SecureKeyVault.shared
        
        // Try to retrieve existing key
        if let keyData = try? keychain.retrieveAPIKey(for: LLMProvider.custom),
           let data = Data(base64Encoded: keyData),
           data.count == 32 {
            return SymmetricKey(data: data)
        }
        
        // Create new key
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        let keyString = keyData.base64EncodedString()
        
        try? keychain.storeAPIKey(keyString, for: LLMProvider.custom)
        
        return newKey
    }
    
    // MARK: - Encryption Helpers
    
    private func encrypt<T: Codable>(_ object: T) throws -> Data {
        let jsonData = try JSONEncoder().encode(object)
        let sealedBox = try AES.GCM.seal(jsonData, using: encryptionKey)
        guard let combined = sealedBox.combined else {
            throw LocalDataError.encryptionFailed
        }
        return combined
    }
    
    private func decrypt<T: Codable>(_ data: Data, as type: T.Type) throws -> T {
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        let decryptedData = try AES.GCM.open(sealedBox, using: encryptionKey)
        return try JSONDecoder().decode(type, from: decryptedData)
    }
    
    // MARK: - Agent Persistence
    
    func saveAgents(_ agents: [LLMAgent]) throws {
        let encryptedData = try encrypt(agents)
        try encryptedData.write(to: agentsFileURL)
    }
    
    func loadAgents() throws -> [LLMAgent] {
        guard FileManager.default.fileExists(atPath: agentsFileURL.path) else {
            return []
        }
        
        let encryptedData = try Data(contentsOf: agentsFileURL)
        return try decrypt(encryptedData, as: [LLMAgent].self)
    }
    
    func saveAgent(_ agent: LLMAgent) throws {
        var agents = try loadAgents()
        
        if let index = agents.firstIndex(where: { $0.id == agent.id }) {
            agents[index] = agent
        } else {
            agents.append(agent)
        }
        
        try saveAgents(agents)
    }
    
    func deleteAgent(withId agentId: UUID) throws {
        var agents = try loadAgents()
        agents.removeAll { $0.id == agentId }
        try saveAgents(agents)
    }
    
    // MARK: - Room Persistence
    
    func saveRooms(_ rooms: [ChatRoom]) throws {
        let encryptedData = try encrypt(rooms)
        try encryptedData.write(to: roomsFileURL)
    }
    
    func loadRooms() throws -> [ChatRoom] {
        guard FileManager.default.fileExists(atPath: roomsFileURL.path) else {
            return []
        }
        
        let encryptedData = try Data(contentsOf: roomsFileURL)
        return try decrypt(encryptedData, as: [ChatRoom].self)
    }
    
    func saveRoom(_ room: ChatRoom) throws {
        var rooms = try loadRooms()
        
        if let index = rooms.firstIndex(where: { $0.id == room.id }) {
            rooms[index] = room
        } else {
            rooms.append(room)
        }
        
        try saveRooms(rooms)
    }
    
    func deleteRoom(withId roomId: UUID) throws {
        var rooms = try loadRooms()
        rooms.removeAll { $0.id == roomId }
        try saveRooms(rooms)
        
        // Also delete messages for this room
        try deleteMessages(for: roomId)
    }
    
    // MARK: - Message Persistence
    
    private func messagesFileURL(for roomId: UUID) -> URL {
        return messagesDirectoryURL.appendingPathComponent("\(roomId.uuidString).json")
    }
    
    func saveMessages(_ messages: [ChatMessage], for roomId: UUID) throws {
        let encryptedData = try encrypt(messages)
        try encryptedData.write(to: messagesFileURL(for: roomId))
    }
    
    func loadMessages(for roomId: UUID, limit: Int = 100) throws -> [ChatMessage] {
        let fileURL = messagesFileURL(for: roomId)
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        
        let encryptedData = try Data(contentsOf: fileURL)
        let allMessages = try decrypt(encryptedData, as: [ChatMessage].self)
        
        // Return the most recent messages up to the limit
        let sortedMessages = allMessages.sorted { $0.timestamp < $1.timestamp }
        return Array(sortedMessages.suffix(limit))
    }
    
    func saveMessage(_ message: ChatMessage) throws {
        var messages = try loadMessages(for: message.roomId, limit: 1000) // Load more for saving
        messages.append(message)
        
        // Keep only the most recent 1000 messages per room
        let sortedMessages = messages.sorted { $0.timestamp < $1.timestamp }
        let recentMessages = Array(sortedMessages.suffix(1000))
        
        try saveMessages(recentMessages, for: message.roomId)
    }
    
    func deleteMessages(for roomId: UUID) throws {
        let fileURL = messagesFileURL(for: roomId)
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
    
    // MARK: - Data Export/Import
    
    func exportData() throws -> Data {
        let agents = try loadAgents()
        let rooms = try loadRooms()
        
        // Load messages for all rooms
        var allMessages: [UUID: [ChatMessage]] = [:]
        for room in rooms {
            let messages = try loadMessages(for: room.id, limit: 1000)
            if !messages.isEmpty {
                allMessages[room.id] = messages
            }
        }
        
        let exportData = ExportData(
            agents: agents,
            rooms: rooms,
            messages: allMessages,
            exportDate: Date(),
            version: "1.0"
        )
        
        return try JSONEncoder().encode(exportData)
    }
    
    func importData(_ data: Data) throws {
        let importData = try JSONDecoder().decode(ExportData.self, from: data)
        
        // Import agents
        try saveAgents(importData.agents)
        
        // Import rooms
        try saveRooms(importData.rooms)
        
        // Import messages
        for (roomId, messages) in importData.messages {
            try saveMessages(messages, for: roomId)
        }
    }
    
    func clearAllData() throws {
        // Delete agents file
        if FileManager.default.fileExists(atPath: agentsFileURL.path) {
            try FileManager.default.removeItem(at: agentsFileURL)
        }
        
        // Delete rooms file
        if FileManager.default.fileExists(atPath: roomsFileURL.path) {
            try FileManager.default.removeItem(at: roomsFileURL)
        }
        
        // Delete all message files
        if FileManager.default.fileExists(atPath: messagesDirectoryURL.path) {
            try FileManager.default.removeItem(at: messagesDirectoryURL)
            try FileManager.default.createDirectory(at: messagesDirectoryURL, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Utility Methods
    
    func getStorageSize() -> Int64 {
        var totalSize: Int64 = 0
        
        // Calculate size of all files
        let urls = [agentsFileURL, roomsFileURL]
        
        for url in urls {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attributes[.size] as? Int64 {
                totalSize += size
            }
        }
        
        // Add message files
        if let messageFiles = try? FileManager.default.contentsOfDirectory(at: messagesDirectoryURL, includingPropertiesForKeys: [.fileSizeKey]) {
            for messageFile in messageFiles {
                if let attributes = try? FileManager.default.attributesOfItem(atPath: messageFile.path),
                   let size = attributes[.size] as? Int64 {
                    totalSize += size
                }
            }
        }
        
        return totalSize
    }
}

// MARK: - Error Types

enum LocalDataError: Error, LocalizedError {
    case encryptionFailed
    case decryptionFailed
    case fileNotFound
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .encryptionFailed:
            return "Failed to encrypt data"
        case .decryptionFailed:
            return "Failed to decrypt data"
        case .fileNotFound:
            return "Data file not found"
        case .invalidData:
            return "Invalid data format"
        }
    }
}

// MARK: - Export Data Structure

struct ExportData: Codable {
    let agents: [LLMAgent]
    let rooms: [ChatRoom]
    let messages: [UUID: [ChatMessage]]
    let exportDate: Date
    let version: String
}
