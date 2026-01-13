import Foundation
import CryptoKit

/// Utility class for managing room encryption keys
class RoomKeyManager {
    
    // MARK: - Error Types
    
    enum KeyManagerError: Error, LocalizedError {
        case invalidShareableKey
        case keyGenerationFailed
        case keyStorageFailed
        case keyRetrievalFailed
        
        var errorDescription: String? {
            switch self {
            case .invalidShareableKey:
                return "Invalid shareable room key format"
            case .keyGenerationFailed:
                return "Failed to generate room key"
            case .keyStorageFailed:
                return "Failed to store room key"
            case .keyRetrievalFailed:
                return "Failed to retrieve room key"
            }
        }
    }
    
    // MARK: - Key Generation
    
    /// Generate a new random room key
    /// - Returns: The room key data (32 bytes)
    static func generateRoomKey() -> Data {
        let manager = E2EEncryptionManager.generateNewRoomKey()
        return manager.getRoomKeyData()
    }
    
    /// Generate a room key from a password
    /// - Parameters:
    ///   - password: The password to derive the key from
    ///   - roomId: The room ID to use as salt context
    /// - Returns: The derived room key data
    /// - Throws: KeyManagerError if key derivation fails
    static func generateRoomKey(fromPassword password: String, roomId: UUID) throws -> Data {
        // Use room ID as part of the salt to ensure unique keys per room
        let roomIdData = roomId.uuidString.data(using: .utf8)!
        let baseSalt = E2EEncryptionManager.generateSalt()
        let salt = baseSalt + roomIdData
        
        do {
            let manager = try E2EEncryptionManager.deriveFromPassword(password, salt: salt)
            return manager.getRoomKeyData()
        } catch {
            throw KeyManagerError.keyGenerationFailed
        }
    }
    
    // MARK: - Key Sharing
    
    /// Create a shareable room key string (base64 encoded)
    /// - Parameter keyData: The room key data
    /// - Returns: Base64 encoded shareable key
    /// - Throws: KeyManagerError if encoding fails
    static func createShareableKey(from keyData: Data) throws -> String {
        do {
            let manager = try E2EEncryptionManager(key: keyData)
            return manager.createShareableKey()
        } catch {
            throw KeyManagerError.invalidShareableKey
        }
    }
    
    /// Parse a shareable room key string
    /// - Parameter shareableKey: Base64 encoded room key
    /// - Returns: The room key data
    /// - Throws: KeyManagerError if parsing fails
    static func parseShareableKey(_ shareableKey: String) throws -> Data {
        do {
            let manager = try E2EEncryptionManager.fromShareableKey(shareableKey)
            return manager.getRoomKeyData()
        } catch {
            throw KeyManagerError.invalidShareableKey
        }
    }
    
    // MARK: - Key Validation
    
    /// Validate that a room key is properly formatted
    /// - Parameter keyData: The room key data to validate
    /// - Returns: True if the key is valid
    static func validateRoomKey(_ keyData: Data) -> Bool {
        guard keyData.count == 32 else { return false }
        
        do {
            let manager = try E2EEncryptionManager(key: keyData)
            return manager.verifyIntegrity()
        } catch {
            return false
        }
    }
    
    /// Test encryption/decryption with a room key
    /// - Parameter keyData: The room key data to test
    /// - Returns: True if the key works correctly
    static func testRoomKey(_ keyData: Data) -> Bool {
        do {
            let manager = try E2EEncryptionManager(key: keyData)
            return manager.verifyIntegrity()
        } catch {
            return false
        }
    }
    
    // MARK: - Key Storage (Local)
    
    private static let keychain = SecureKeyVault.shared
    private static let roomKeyPrefix = "room_key_"
    
    /// Store a room key locally
    /// - Parameters:
    ///   - keyData: The room key data
    ///   - roomId: The room ID
    /// - Throws: KeyManagerError if storage fails
    static func storeRoomKey(_ keyData: Data, for roomId: UUID) throws {
        let keyString = keyData.base64EncodedString()
        
        // We'll store room keys as custom provider entries in the keychain
        // This is a bit of a hack, but it reuses the existing secure storage
        do {
            try keychain.storeAPIKey(keyString, for: LLMProvider.custom)
        } catch {
            throw KeyManagerError.keyStorageFailed
        }
    }
    
    /// Retrieve a stored room key
    /// - Parameter roomId: The room ID
    /// - Returns: The room key data if found
    /// - Throws: KeyManagerError if retrieval fails
    static func retrieveRoomKey(for roomId: UUID) throws -> Data? {
        do {
            guard let keyString = try keychain.retrieveAPIKey(for: LLMProvider.custom),
                  let keyData = Data(base64Encoded: keyString) else {
                return nil
            }
            return keyData
        } catch {
            throw KeyManagerError.keyRetrievalFailed
        }
    }
    
    /// Delete a stored room key
    /// - Parameter roomId: The room ID
    /// - Throws: KeyManagerError if deletion fails
    static func deleteRoomKey(for roomId: UUID) throws {
        do {
            try keychain.deleteAPIKey(for: LLMProvider.custom)
        } catch {
            throw KeyManagerError.keyStorageFailed
        }
    }
}

// MARK: - Convenience Extensions

extension ChatRoom {
    
    /// Generate and set a new encryption key for this room
    /// - Throws: RoomKeyManager.KeyManagerError if key generation fails
    mutating func generateEncryptionKey() throws {
        let keyData = RoomKeyManager.generateRoomKey()
        self.encryptionKey = keyData
        self.encryptionEnabled = true
    }
    
    /// Set encryption key from a shareable key string
    /// - Parameter shareableKey: Base64 encoded room key
    /// - Throws: RoomKeyManager.KeyManagerError if parsing fails
    mutating func setEncryptionKey(from shareableKey: String) throws {
        let keyData = try RoomKeyManager.parseShareableKey(shareableKey)
        self.encryptionKey = keyData
        self.encryptionEnabled = true
    }
    
    /// Get a shareable key string for this room
    /// - Returns: Base64 encoded shareable key
    /// - Throws: RoomKeyManager.KeyManagerError if no key is set or encoding fails
    func getShareableKey() throws -> String {
        guard let keyData = encryptionKey else {
            throw RoomKeyManager.KeyManagerError.keyRetrievalFailed
        }
        return try RoomKeyManager.createShareableKey(from: keyData)
    }
    
    /// Validate that the room's encryption key is properly formatted
    /// - Returns: True if the key is valid, false if no key or invalid
    func hasValidEncryptionKey() -> Bool {
        guard let keyData = encryptionKey else { return false }
        return RoomKeyManager.validateRoomKey(keyData)
    }
}