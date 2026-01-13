import Foundation
import CryptoKit

/// End-to-end encryption manager for secure room communication
class E2EEncryptionManager {
    
    // MARK: - Error Types
    
    enum EncryptionError: Error, LocalizedError {
        case keyGenerationFailed
        case encryptionFailed
        case decryptionFailed
        case invalidKeySize
        case invalidData
        case keyDerivationFailed
        
        var errorDescription: String? {
            switch self {
            case .keyGenerationFailed:
                return "Failed to generate encryption key"
            case .encryptionFailed:
                return "Failed to encrypt data"
            case .decryptionFailed:
                return "Failed to decrypt data"
            case .invalidKeySize:
                return "Invalid encryption key size"
            case .invalidData:
                return "Invalid data format"
            case .keyDerivationFailed:
                return "Failed to derive encryption key"
            }
        }
    }
    
    // MARK: - Private Properties
    
    private let roomKey: SymmetricKey
    
    // MARK: - Initialization
    
    /// Initialize with an existing room key
    /// - Parameter key: The room encryption key
    init(key: Data) throws {
        guard key.count == 32 else { // 256 bits
            throw EncryptionError.invalidKeySize
        }
        self.roomKey = SymmetricKey(data: key)
    }
    
    /// Initialize with a new generated room key
    init() {
        self.roomKey = SymmetricKey(size: .bits256)
    }
    
    // MARK: - Key Management
    
    /// Get the room key data for sharing
    /// - Returns: The room key as Data
    func getRoomKeyData() -> Data {
        return roomKey.withUnsafeBytes { Data($0) }
    }
    
    /// Generate a new room key
    /// - Returns: A new E2EEncryptionManager with a fresh key
    static func generateNewRoomKey() -> E2EEncryptionManager {
        return E2EEncryptionManager()
    }
    
    /// Derive a room key from a password using PBKDF2
    /// - Parameters:
    ///   - password: The password to derive from
    ///   - salt: The salt for key derivation
    ///   - iterations: Number of PBKDF2 iterations (default: 100,000)
    /// - Returns: A new E2EEncryptionManager with the derived key
    /// - Throws: EncryptionError if key derivation fails
    static func deriveFromPassword(
        _ password: String,
        salt: Data,
        iterations: Int = 100_000
    ) throws -> E2EEncryptionManager {
        guard let passwordData = password.data(using: .utf8) else {
            throw EncryptionError.keyDerivationFailed
        }
        
        let derivedKey = try HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: passwordData),
            salt: salt,
            info: "DormantChat Room Key".data(using: .utf8)!,
            outputByteCount: 32
        )
        
        let keyData = derivedKey.withUnsafeBytes { Data($0) }
        return try E2EEncryptionManager(key: keyData)
    }
    
    // MARK: - Encryption/Decryption
    
    /// Encrypt data using AES-GCM
    /// - Parameter data: The data to encrypt
    /// - Returns: The encrypted data including nonce and authentication tag
    /// - Throws: EncryptionError if encryption fails
    func encrypt(_ data: Data) throws -> Data {
        do {
            let sealedBox = try AES.GCM.seal(data, using: roomKey)
            guard let combined = sealedBox.combined else {
                throw EncryptionError.encryptionFailed
            }
            return combined
        } catch {
            throw EncryptionError.encryptionFailed
        }
    }
    
    /// Decrypt data using AES-GCM
    /// - Parameter encryptedData: The encrypted data including nonce and authentication tag
    /// - Returns: The decrypted data
    /// - Throws: EncryptionError if decryption fails
    func decrypt(_ encryptedData: Data) throws -> Data {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            return try AES.GCM.open(sealedBox, using: roomKey)
        } catch {
            throw EncryptionError.decryptionFailed
        }
    }
    
    /// Encrypt a chat message
    /// - Parameter message: The chat message to encrypt
    /// - Returns: Encrypted message data
    /// - Throws: EncryptionError if encryption fails
    func encryptMessage(_ message: ChatMessage) throws -> Data {
        let messageData = try JSONEncoder().encode(message)
        return try encrypt(messageData)
    }
    
    /// Decrypt a chat message
    /// - Parameter encryptedData: The encrypted message data
    /// - Returns: The decrypted chat message
    /// - Throws: EncryptionError if decryption fails
    func decryptMessage(_ encryptedData: Data) throws -> ChatMessage {
        let decryptedData = try decrypt(encryptedData)
        do {
            return try JSONDecoder().decode(ChatMessage.self, from: decryptedData)
        } catch {
            throw EncryptionError.invalidData
        }
    }
    
    // MARK: - Utility Methods
    
    /// Generate a random salt for key derivation
    /// - Returns: A 32-byte random salt
    static func generateSalt() -> Data {
        var salt = Data(count: 32)
        _ = salt.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 32, bytes.bindMemory(to: UInt8.self).baseAddress!)
        }
        return salt
    }
    
    /// Verify that the encryption manager can encrypt and decrypt data correctly
    /// - Returns: True if the round-trip test passes
    func verifyIntegrity() -> Bool {
        let testData = "Test message for encryption integrity".data(using: .utf8)!
        
        do {
            let encrypted = try encrypt(testData)
            let decrypted = try decrypt(encrypted)
            return decrypted == testData
        } catch {
            return false
        }
    }
}

// MARK: - Room Key Sharing

extension E2EEncryptionManager {
    
    /// Create a shareable room key string (base64 encoded)
    /// - Returns: Base64 encoded room key
    func createShareableKey() -> String {
        return getRoomKeyData().base64EncodedString()
    }
    
    /// Create an encryption manager from a shareable key string
    /// - Parameter shareableKey: Base64 encoded room key
    /// - Returns: A new E2EEncryptionManager
    /// - Throws: EncryptionError if the key is invalid
    static func fromShareableKey(_ shareableKey: String) throws -> E2EEncryptionManager {
        guard let keyData = Data(base64Encoded: shareableKey) else {
            throw EncryptionError.invalidData
        }
        return try E2EEncryptionManager(key: keyData)
    }
}

// MARK: - Message Envelope

/// Encrypted message envelope for transmission
struct EncryptedMessageEnvelope: Codable {
    let encryptedData: Data
    let timestamp: Date
    let messageId: UUID
    let roomId: UUID
    
    init(encryptedData: Data, roomId: UUID) {
        self.encryptedData = encryptedData
        self.timestamp = Date()
        self.messageId = UUID()
        self.roomId = roomId
    }
}