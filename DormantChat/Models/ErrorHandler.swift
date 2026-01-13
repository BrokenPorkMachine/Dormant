import Foundation
import SwiftUI
import os.log

/// Centralized error handling system for the Dormant Chat application
@MainActor
class ErrorHandler: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = ErrorHandler()
    
    private init() {}
    
    // MARK: - Published Properties
    
    @Published var currentError: DormantError?
    @Published var showingErrorAlert = false
    @Published var errorHistory: [ErrorLogEntry] = []
    
    // MARK: - Logging
    
    private let logger = Logger(subsystem: "com.dormant.chat", category: "ErrorHandler")
    
    // MARK: - Error Handling
    
    /// Handle an error with user-friendly messaging and logging
    /// - Parameters:
    ///   - error: The error to handle
    ///   - context: Additional context about where the error occurred
    ///   - showToUser: Whether to show the error to the user (default: true)
    func handle(_ error: Error, context: String = "", showToUser: Bool = true) {
        let dormantError = DormantError.from(error, context: context)
        
        // Log the error
        logError(dormantError, context: context)
        
        // Add to error history
        let logEntry = ErrorLogEntry(
            error: dormantError,
            context: context,
            timestamp: Date()
        )
        errorHistory.append(logEntry)
        
        // Keep only last 100 errors
        if errorHistory.count > 100 {
            errorHistory.removeFirst()
        }
        
        // Show to user if requested
        if showToUser {
            currentError = dormantError
            showingErrorAlert = true
        }
    }
    
    /// Handle a specific DormantError
    /// - Parameters:
    ///   - error: The DormantError to handle
    ///   - context: Additional context
    ///   - showToUser: Whether to show to user
    func handle(_ error: DormantError, context: String = "", showToUser: Bool = true) {
        logError(error, context: context)
        
        let logEntry = ErrorLogEntry(
            error: error,
            context: context,
            timestamp: Date()
        )
        errorHistory.append(logEntry)
        
        if errorHistory.count > 100 {
            errorHistory.removeFirst()
        }
        
        if showToUser {
            currentError = error
            showingErrorAlert = true
        }
    }
    
    /// Clear the current error
    func clearCurrentError() {
        currentError = nil
        showingErrorAlert = false
    }
    
    /// Clear error history
    func clearHistory() {
        errorHistory.removeAll()
    }
    
    // MARK: - Recovery Actions
    
    /// Get recovery actions for a specific error
    /// - Parameter error: The error to get recovery actions for
    /// - Returns: Array of recovery actions
    func getRecoveryActions(for error: DormantError) -> [RecoveryAction] {
        switch error.category {
        case .network:
            return [
                RecoveryAction(title: "Retry", action: { /* Retry logic */ }),
                RecoveryAction(title: "Check Connection", action: { /* Connection check */ }),
                RecoveryAction(title: "Check Network Settings", action: { /* Network settings */ })
            ]
        case .authentication:
            return [
                RecoveryAction(title: "Update API Key", action: { /* Open settings */ }),
                RecoveryAction(title: "Check Provider Status", action: { /* Check status */ })
            ]
        case .llmProvider:
            return [
                RecoveryAction(title: "Try Different Model", action: { /* Model selection */ }),
                RecoveryAction(title: "Check Provider Limits", action: { /* Limits check */ })
            ]
        case .storage:
            return [
                RecoveryAction(title: "Clear Cache", action: { /* Clear cache */ }),
                RecoveryAction(title: "Reset Storage", action: { /* Reset storage */ })
            ]
        case .validation:
            return [
                RecoveryAction(title: "Fix Input", action: { /* Input validation */ })
            ]
        case .system:
            return [
                RecoveryAction(title: "Restart App", action: { /* Restart */ }),
                RecoveryAction(title: "Report Bug", action: { /* Bug report */ })
            ]
        }
    }
    
    // MARK: - Private Methods
    
    private func logError(_ error: DormantError, context: String) {
        let message = context.isEmpty ? error.localizedDescription : "\(context): \(error.localizedDescription)"
        
        switch error.severity {
        case .low:
            logger.info("\(message)")
        case .medium:
            logger.notice("\(message)")
        case .high:
            logger.error("\(message)")
        case .critical:
            logger.critical("\(message)")
        }
    }
}

// MARK: - Error Types

/// Comprehensive error type for Dormant Chat
enum DormantError: Error, LocalizedError, Identifiable {
    case network(NetworkError)
    case authentication(AuthenticationError)
    case llmProvider(LLMProviderError)
    case storage(StorageError)
    case validation(ValidationError)
    case system(SystemError)
    
    var id: String {
        return "\(category.rawValue)_\(code)"
    }
    
    var category: ErrorCategory {
        switch self {
        case .network: return .network
        case .authentication: return .authentication
        case .llmProvider: return .llmProvider
        case .storage: return .storage
        case .validation: return .validation
        case .system: return .system
        }
    }
    
    var severity: ErrorSeverity {
        switch self {
        case .network(let error): return error.severity
        case .authentication(let error): return error.severity
        case .llmProvider(let error): return error.severity
        case .storage(let error): return error.severity
        case .validation(let error): return error.severity
        case .system(let error): return error.severity
        }
    }
    
    var code: Int {
        switch self {
        case .network(let error): return error.code
        case .authentication(let error): return error.code
        case .llmProvider(let error): return error.code
        case .storage(let error): return error.code
        case .validation(let error): return error.code
        case .system(let error): return error.code
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .network(let error): return error.localizedDescription
        case .authentication(let error): return error.localizedDescription
        case .llmProvider(let error): return error.localizedDescription
        case .storage(let error): return error.localizedDescription
        case .validation(let error): return error.localizedDescription
        case .system(let error): return error.localizedDescription
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .network(let error): return error.recoverySuggestion
        case .authentication(let error): return error.recoverySuggestion
        case .llmProvider(let error): return error.recoverySuggestion
        case .storage(let error): return error.recoverySuggestion
        case .validation(let error): return error.recoverySuggestion
        case .system(let error): return error.recoverySuggestion
        }
    }
    
    /// Create a DormantError from any Error
    static func from(_ error: Error, context: String = "") -> DormantError {
        if let dormantError = error as? DormantError {
            return dormantError
        }
        
        if let llmError = error as? LLMProviderError {
            return .llmProvider(LLMProviderError.from(llmError))
        }
        
        if let urlError = error as? URLError {
            return .network(NetworkError.from(urlError))
        }
        
        // Default to system error
        return .system(SystemError.unknown(error.localizedDescription))
    }
}

// MARK: - Error Categories

enum ErrorCategory: String, CaseIterable {
    case network = "Network"
    case authentication = "Authentication"
    case llmProvider = "LLM Provider"
    case storage = "Storage"
    case validation = "Validation"
    case system = "System"
}

enum ErrorSeverity: Int, CaseIterable {
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4
    
    var displayName: String {
        switch self {
        case .low: return "Info"
        case .medium: return "Warning"
        case .high: return "Error"
        case .critical: return "Critical"
        }
    }
    
    var color: Color {
        switch self {
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        case .critical: return .purple
        }
    }
}

// MARK: - Specific Error Types

enum NetworkError: LocalizedError {
    case connectionFailed
    case timeout
    case noInternet
    case serverUnavailable
    case invalidResponse
    case rateLimited
    
    var code: Int {
        switch self {
        case .connectionFailed: return 1001
        case .timeout: return 1002
        case .noInternet: return 1003
        case .serverUnavailable: return 1004
        case .invalidResponse: return 1005
        case .rateLimited: return 1006
        }
    }
    
    var severity: ErrorSeverity {
        switch self {
        case .connectionFailed, .timeout, .noInternet: return .medium
        case .serverUnavailable, .rateLimited: return .high
        case .invalidResponse: return .medium
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Failed to connect to server"
        case .timeout:
            return "Request timed out"
        case .noInternet:
            return "No internet connection available"
        case .serverUnavailable:
            return "Server is currently unavailable"
        case .invalidResponse:
            return "Received invalid response from server"
        case .rateLimited:
            return "Too many requests - rate limit exceeded"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .connectionFailed:
            return "Check your internet connection and try again"
        case .timeout:
            return "Try again or check your connection speed"
        case .noInternet:
            return "Connect to the internet and try again"
        case .serverUnavailable:
            return "Wait a moment and try again"
        case .invalidResponse:
            return "Try again or contact support if the problem persists"
        case .rateLimited:
            return "Wait a few minutes before trying again"
        }
    }
    
    static func from(_ urlError: URLError) -> NetworkError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return .noInternet
        case .timedOut:
            return .timeout
        case .cannotConnectToHost, .cannotFindHost:
            return .connectionFailed
        case .badServerResponse:
            return .invalidResponse
        default:
            return .connectionFailed
        }
    }
}

enum AuthenticationError: LocalizedError {
    case invalidAPIKey
    case expiredAPIKey
    case insufficientPermissions
    case providerAuthFailed
    
    var code: Int {
        switch self {
        case .invalidAPIKey: return 2001
        case .expiredAPIKey: return 2002
        case .insufficientPermissions: return 2003
        case .providerAuthFailed: return 2004
        }
    }
    
    var severity: ErrorSeverity { return .high }
    
    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid API key"
        case .expiredAPIKey:
            return "API key has expired"
        case .insufficientPermissions:
            return "Insufficient permissions for this operation"
        case .providerAuthFailed:
            return "Authentication with provider failed"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .invalidAPIKey:
            return "Check your API key in settings and ensure it's correct"
        case .expiredAPIKey:
            return "Update your API key in settings"
        case .insufficientPermissions:
            return "Contact your provider to upgrade your account permissions"
        case .providerAuthFailed:
            return "Check your API key and provider settings"
        }
    }
}

enum StorageError: LocalizedError {
    case diskFull
    case permissionDenied
    case corruptedData
    case encryptionFailed
    case keychainError
    
    var code: Int {
        switch self {
        case .diskFull: return 3001
        case .permissionDenied: return 3002
        case .corruptedData: return 3003
        case .encryptionFailed: return 3004
        case .keychainError: return 3005
        }
    }
    
    var severity: ErrorSeverity {
        switch self {
        case .diskFull, .permissionDenied: return .high
        case .corruptedData, .encryptionFailed, .keychainError: return .medium
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .diskFull:
            return "Not enough disk space"
        case .permissionDenied:
            return "Permission denied for storage operation"
        case .corruptedData:
            return "Data appears to be corrupted"
        case .encryptionFailed:
            return "Failed to encrypt/decrypt data"
        case .keychainError:
            return "Keychain access error"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .diskFull:
            return "Free up disk space and try again"
        case .permissionDenied:
            return "Check app permissions in System Preferences"
        case .corruptedData:
            return "Try clearing app data or reinstalling"
        case .encryptionFailed:
            return "Try restarting the app"
        case .keychainError:
            return "Check Keychain Access permissions"
        }
    }
}

enum ValidationError: LocalizedError {
    case invalidInput(String)
    case missingRequiredField(String)
    case formatError(String)
    case lengthError(String)
    
    var code: Int {
        switch self {
        case .invalidInput: return 4001
        case .missingRequiredField: return 4002
        case .formatError: return 4003
        case .lengthError: return 4004
        }
    }
    
    var severity: ErrorSeverity { return .low }
    
    var errorDescription: String? {
        switch self {
        case .invalidInput(let field):
            return "Invalid input for \(field)"
        case .missingRequiredField(let field):
            return "\(field) is required"
        case .formatError(let field):
            return "Invalid format for \(field)"
        case .lengthError(let field):
            return "Invalid length for \(field)"
        }
    }
    
    var recoverySuggestion: String? {
        return "Please correct the input and try again"
    }
}

enum SystemError: LocalizedError {
    case memoryWarning
    case unexpectedNil
    case configurationError
    case unknown(String)
    
    var code: Int {
        switch self {
        case .memoryWarning: return 5001
        case .unexpectedNil: return 5002
        case .configurationError: return 5003
        case .unknown: return 5999
        }
    }
    
    var severity: ErrorSeverity {
        switch self {
        case .memoryWarning: return .high
        case .unexpectedNil, .configurationError: return .medium
        case .unknown: return .medium
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .memoryWarning:
            return "Low memory warning"
        case .unexpectedNil:
            return "Unexpected nil value encountered"
        case .configurationError:
            return "Configuration error"
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .memoryWarning:
            return "Close other applications to free up memory"
        case .unexpectedNil:
            return "Try restarting the app"
        case .configurationError:
            return "Check app configuration and settings"
        case .unknown:
            return "Try restarting the app or contact support"
        }
    }
}

// MARK: - Supporting Types

struct ErrorLogEntry: Identifiable {
    let id = UUID()
    let error: DormantError
    let context: String
    let timestamp: Date
}

struct RecoveryAction {
    let title: String
    let action: () -> Void
}

// MARK: - LLMProviderError Extension

extension LLMProviderError {
    static func from(_ error: LLMProviderError) -> LLMProviderError {
        return error // Already the right type
    }
    
    var severity: ErrorSeverity {
        switch self {
        case .invalidAPIKey, .invalidModel, .invalidConfiguration:
            return .high
        case .networkError, .providerUnavailable:
            return .medium
        case .rateLimitExceeded, .contentFiltered:
            return .medium
        case .contextTooLong, .streamingNotSupported:
            return .low
        case .invalidResponse, .apiError, .unknownError:
            return .medium
        }
    }
    
    var code: Int {
        switch self {
        case .invalidAPIKey: return 6001
        case .invalidModel: return 6002
        case .invalidConfiguration: return 6003
        case .networkError: return 6004
        case .rateLimitExceeded: return 6005
        case .contentFiltered: return 6006
        case .contextTooLong: return 6007
        case .providerUnavailable: return 6008
        case .streamingNotSupported: return 6009
        case .invalidResponse: return 6010
        case .apiError: return 6011
        case .unknownError: return 6999
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .invalidAPIKey:
            return "Check your API key in settings"
        case .invalidModel:
            return "Select a different model"
        case .invalidConfiguration:
            return "Review agent configuration"
        case .networkError:
            return "Check your internet connection"
        case .rateLimitExceeded:
            return "Wait before making more requests"
        case .contentFiltered:
            return "Modify your message content"
        case .contextTooLong:
            return "Reduce message length or context"
        case .providerUnavailable:
            return "Try again later or use a different provider"
        case .streamingNotSupported:
            return "Disable streaming for this provider"
        case .invalidResponse:
            return "Try again or contact provider support"
        case .apiError:
            return "Check provider status and try again"
        case .unknownError:
            return "Try again or contact support"
        }
    }
}