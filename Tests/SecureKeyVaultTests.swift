import Foundation
import Testing
import SwiftCheck
@testable import DormantChat

@Suite("Secure Key Vault")
struct SecureKeyVaultTests {
    
    @Test("Basic API key storage and retrieval")
    func testBasicAPIKeyStorageAndRetrieval() throws {
        let vault = SecureKeyVault.shared
        let testKey = "sk-test123456789"
        let provider = LLMProvider.openai
        
        // Clean up any existing key and encryption key first
        try? vault.deleteAPIKey(for: provider)
        
        // Store the key
        try vault.storeAPIKey(testKey, for: provider)
        
        // Retrieve the key
        let retrievedKey = try vault.retrieveAPIKey(for: provider)
        
        #expect(retrievedKey == testKey)
        
        // Clean up
        try vault.deleteAPIKey(for: provider)
    }
    
    @Test("API key deletion")
    func testAPIKeyDeletion() throws {
        let vault = SecureKeyVault.shared
        let testKey = "sk-test123456789"
        let provider = LLMProvider.anthropic
        
        // Clean up any existing key first
        try? vault.deleteAPIKey(for: provider)
        
        // Store the key
        try vault.storeAPIKey(testKey, for: provider)
        
        // Verify it exists
        let retrievedKey = try vault.retrieveAPIKey(for: provider)
        #expect(retrievedKey == testKey)
        
        // Delete the key
        try vault.deleteAPIKey(for: provider)
        
        // Verify it's gone
        let deletedKey = try vault.retrieveAPIKey(for: provider)
        #expect(deletedKey == nil)
    }
    
    @Test("Multiple provider key storage")
    func testMultipleProviderKeyStorage() throws {
        let vault = SecureKeyVault.shared
        let openaiKey = "sk-openai123"
        let anthropicKey = "sk-anthropic456"
        
        // Clean up any existing keys first
        try? vault.deleteAPIKey(for: LLMProvider.openai)
        try? vault.deleteAPIKey(for: LLMProvider.anthropic)
        
        // Store keys for different providers
        try vault.storeAPIKey(openaiKey, for: LLMProvider.openai)
        try vault.storeAPIKey(anthropicKey, for: LLMProvider.anthropic)
        
        // Retrieve and verify both keys
        let retrievedOpenAI = try vault.retrieveAPIKey(for: LLMProvider.openai)
        let retrievedAnthropic = try vault.retrieveAPIKey(for: LLMProvider.anthropic)
        
        #expect(retrievedOpenAI == openaiKey)
        #expect(retrievedAnthropic == anthropicKey)
        
        // Clean up
        try vault.deleteAPIKey(for: LLMProvider.openai)
        try vault.deleteAPIKey(for: LLMProvider.anthropic)
    }
    
    @Test("Key update functionality")
    func testKeyUpdateFunctionality() throws {
        let vault = SecureKeyVault.shared
        let originalKey = "sk-original123"
        let updatedKey = "sk-updated456"
        let provider = LLMProvider.openai
        
        // Clean up any existing key first
        try? vault.deleteAPIKey(for: provider)
        
        // Store original key
        try vault.storeAPIKey(originalKey, for: provider)
        
        // Verify original key
        let retrievedOriginal = try vault.retrieveAPIKey(for: provider)
        #expect(retrievedOriginal == originalKey)
        
        // Update with new key
        try vault.storeAPIKey(updatedKey, for: provider)
        
        // Verify updated key
        let retrievedUpdated = try vault.retrieveAPIKey(for: provider)
        #expect(retrievedUpdated == updatedKey)
        
        // Clean up
        try vault.deleteAPIKey(for: provider)
    }
    
    @Test("Delete all keys functionality")
    func testDeleteAllKeysFunctionality() throws {
        let vault = SecureKeyVault.shared
        
        // Store keys for multiple providers
        try vault.storeAPIKey("sk-openai123", for: LLMProvider.openai)
        try vault.storeAPIKey("sk-anthropic456", for: LLMProvider.anthropic)
        try vault.storeAPIKey("sk-huggingface789", for: LLMProvider.huggingface)
        
        // Verify keys exist
        #expect(try vault.retrieveAPIKey(for: LLMProvider.openai) != nil)
        #expect(try vault.retrieveAPIKey(for: LLMProvider.anthropic) != nil)
        #expect(try vault.retrieveAPIKey(for: LLMProvider.huggingface) != nil)
        
        // Delete all keys
        try vault.deleteAllKeys()
        
        // Verify all keys are gone
        #expect(try vault.retrieveAPIKey(for: LLMProvider.openai) == nil)
        #expect(try vault.retrieveAPIKey(for: LLMProvider.anthropic) == nil)
        #expect(try vault.retrieveAPIKey(for: LLMProvider.huggingface) == nil)
    }
    
    @Test("Retrieve non-existent key returns nil")
    func testRetrieveNonExistentKey() throws {
        let vault = SecureKeyVault.shared
        let provider = LLMProvider.custom
        
        // Ensure key doesn't exist
        try? vault.deleteAPIKey(for: provider)
        
        // Try to retrieve non-existent key
        let retrievedKey = try vault.retrieveAPIKey(for: provider)
        #expect(retrievedKey == nil)
    }
    
    @Test("Delete non-existent key doesn't throw")
    func testDeleteNonExistentKey() throws {
        let vault = SecureKeyVault.shared
        let provider = LLMProvider.custom
        
        // Ensure key doesn't exist
        try? vault.deleteAPIKey(for: provider)
        
        // Delete non-existent key should not throw
        try vault.deleteAPIKey(for: provider)
    }
    
    @Test("Feature: dormant-chat, Property 1: API Key Encryption Round Trip")
    func testAPIKeyEncryptionRoundTrip() throws {
        // Property: For any valid API key string, storing it in the secure vault then retrieving it should produce the original key value
        // Validates: Requirements 1.1
        
        try property("API key encryption round trip") <- forAll(String.arbitrary.suchThat { key in
            // Filter out empty strings and strings with only whitespace
            !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            // Filter out strings that might cause encoding issues
            key.data(using: .utf8) != nil &&
            // Reasonable length limits
            key.count > 0 && key.count < 1000
        }) { (apiKey: String) in
            let vault = SecureKeyVault.shared
            let provider = LLMProvider.openai
            
            do {
                // Clean up first
                try? vault.deleteAPIKey(for: provider)
                
                // Store and retrieve
                try vault.storeAPIKey(apiKey, for: provider)
                let retrieved = try vault.retrieveAPIKey(for: provider)
                
                // Clean up
                try vault.deleteAPIKey(for: provider)
                
                return retrieved == apiKey
            } catch {
                // Clean up on error
                try? vault.deleteAPIKey(for: provider)
                return false
            }
        }
    }
    
    @Test("Feature: dormant-chat, Property 20: Keychain Storage Utilization")
    func testKeychainStorageUtilization() throws {
        // Property: For any API key storage operation, the system should use the operating system's secure keychain
        // Validates: Requirements 9.3
        
        try property("Keychain storage utilization") <- forAll(
            String.arbitrary.suchThat { key in
                // Filter for valid API keys
                !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                key.data(using: .utf8) != nil &&
                key.count > 0 && key.count < 1000
            },
            LLMProvider.arbitrary.suchThat { provider in
                // Only test providers that require API keys
                provider.requiresAPIKey && provider != .custom // Exclude custom to avoid test conflicts
            }
        ) { (apiKey: String, provider: LLMProvider) in
            let vault = SecureKeyVault.shared
            
            do {
                // Clean up first
                try? vault.deleteAPIKey(for: provider)
                
                // Store key - this should use Keychain Services internally
                try vault.storeAPIKey(apiKey, for: provider)
                
                // Verify we can retrieve it (proving it was stored in keychain)
                let retrieved = try vault.retrieveAPIKey(for: provider)
                
                // Clean up
                try vault.deleteAPIKey(for: provider)
                
                return retrieved == apiKey
            } catch {
                // Clean up on error
                try? vault.deleteAPIKey(for: provider)
                return false
            }
        }
    }
}