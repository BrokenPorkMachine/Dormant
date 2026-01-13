import Foundation
import Security
import CryptoKit

/// Secure storage for API keys using Keychain Services with AES-256 encryption
class SecureKeyVault {
    
    // MARK: - Singleton
    
    static let shared = SecureKeyVault()
    
    private init() {}
    
    // MARK: - Error Types
    
    enum KeyVaultError: Error, LocalizedError {
        case encryptionFailed
        case decryptionFailed
        case keychainStoreFailed(OSStatus)
        case keychainRetrieveFailed(OSStatus)
        case keychainDeleteFailed(OSStatus)
        case invalidData
        case keyGenerationFailed
        
        var errorDescription: String? {
            switch self {
            case .encryptionFailed:
                return "Failed to encrypt API key"
            case .decryptionFailed:
                return "Failed to decrypt API key"
            case .keychainStoreFailed(let status):
                return "Failed to store in Keychain (status: \(status))"
            case .keychainRetrieveFailed(let status):
                return "Failed to retrieve from Keychain (status: \(status))"
            case .keychainDeleteFailed(let status):
                return "Failed to delete from Keychain (status: \(status))"
            case .invalidData:
                return "Invalid data format"
            case .keyGenerationFailed:
                return "Failed to generate encryption key"
            }
        }
    }
    
    // MARK: - Private Properties
    
    private let service = "com.dormantchat.apikeys"
    private let encryptionKeyAccount = "com.dormantchat.encryptionkey"
    
    // MARK: - Public Methods
    
    /// Store an API key for a specific provider
    /// - Parameters:
    ///   - key: The API key to store
    ///   - provider: The LLM provider
    /// - Throws: KeyVaultError if storage fails
    func storeAPIKey(_ key: String, for provider: LLMProvider) throws {
        guard let keyData = key.data(using: .utf8) else {
            throw KeyVaultError.invalidData
        }
        
        let encryptedData = try encrypt(keyData, for: provider)
        let account = accountName(for: provider)
        
        // First try to update existing item
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let updateAttributes: [String: Any] = [
            kSecValueData as String: encryptedData
        ]
        
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
        
        if updateStatus == errSecItemNotFound {
            // Item doesn't exist, create new one
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: encryptedData,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw KeyVaultError.keychainStoreFailed(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeyVaultError.keychainStoreFailed(updateStatus)
        }
    }
    
    /// Retrieve an API key for a specific provider
    /// - Parameter provider: The LLM provider
    /// - Returns: The API key if found, nil otherwise
    /// - Throws: KeyVaultError if retrieval fails
    func retrieveAPIKey(for provider: LLMProvider) throws -> String? {
        let account = accountName(for: provider)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        guard status == errSecSuccess else {
            throw KeyVaultError.keychainRetrieveFailed(status)
        }
        
        guard let encryptedData = result as? Data else {
            throw KeyVaultError.invalidData
        }
        
        let decryptedData = try decrypt(encryptedData, for: provider)
        
        guard let apiKey = String(data: decryptedData, encoding: .utf8) else {
            throw KeyVaultError.invalidData
        }
        
        return apiKey
    }
    
    /// Delete an API key for a specific provider
    /// - Parameter provider: The LLM provider
    /// - Throws: KeyVaultError if deletion fails
    func deleteAPIKey(for provider: LLMProvider) throws {
        let account = accountName(for: provider)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeyVaultError.keychainDeleteFailed(status)
        }
        
        // Also delete the encryption key for this provider
        let keyAccount = "\(encryptionKeyAccount).\(provider.rawValue.lowercased().replacingOccurrences(of: " ", with: "."))"
        let encryptionKeyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keyAccount
        ]
        
        let encKeyStatus = SecItemDelete(encryptionKeyQuery as CFDictionary)
        if encKeyStatus != errSecSuccess && encKeyStatus != errSecItemNotFound {
            throw KeyVaultError.keychainDeleteFailed(encKeyStatus)
        }
    }
    
    /// Delete all stored API keys
    /// - Throws: KeyVaultError if deletion fails
    func deleteAllKeys() throws {
        // Delete all API keys
        for provider in LLMProvider.allCases where provider.requiresAPIKey {
            try deleteAPIKey(for: provider)
        }
        
        // Delete all encryption keys
        for provider in LLMProvider.allCases where provider.requiresAPIKey {
            let keyAccount = "\(encryptionKeyAccount).\(provider.rawValue.lowercased().replacingOccurrences(of: " ", with: "."))"
            let encryptionKeyQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: keyAccount
            ]
            
            let status = SecItemDelete(encryptionKeyQuery as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound {
                throw KeyVaultError.keychainDeleteFailed(status)
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Generate account name for a provider
    private func accountName(for provider: LLMProvider) -> String {
        return "apikey.\(provider.rawValue.lowercased().replacingOccurrences(of: " ", with: "."))"
    }
    
    /// Get or create the encryption key for a specific provider
    private func encryptionKey(for provider: LLMProvider) throws -> SymmetricKey {
        let keyAccount = "\(encryptionKeyAccount).\(provider.rawValue.lowercased().replacingOccurrences(of: " ", with: "."))"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            // Generate new key
            let newKey = SymmetricKey(size: .bits256)
            let keyData = newKey.withUnsafeBytes { Data($0) }
            
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: keyAccount,
                kSecValueData as String: keyData,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw KeyVaultError.keychainStoreFailed(addStatus)
            }
            
            return newKey
        }
        
        guard status == errSecSuccess else {
            throw KeyVaultError.keychainRetrieveFailed(status)
        }
        
        guard let keyData = result as? Data else {
            throw KeyVaultError.invalidData
        }
        
        return SymmetricKey(data: keyData)
    }
    
    /// Encrypt data using AES-256-GCM
    private func encrypt(_ data: Data, for provider: LLMProvider) throws -> Data {
        do {
            let key = try encryptionKey(for: provider)
            let sealedBox = try AES.GCM.seal(data, using: key)
            guard let combined = sealedBox.combined else {
                throw KeyVaultError.encryptionFailed
            }
            return combined
        } catch let keyVaultError as KeyVaultError {
            throw keyVaultError
        } catch {
            throw KeyVaultError.encryptionFailed
        }
    }
    
    /// Decrypt data using AES-256-GCM
    private func decrypt(_ data: Data, for provider: LLMProvider) throws -> Data {
        do {
            let key = try encryptionKey(for: provider)
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        } catch let keyVaultError as KeyVaultError {
            throw keyVaultError
        } catch {
            throw KeyVaultError.decryptionFailed
        }
    }
}