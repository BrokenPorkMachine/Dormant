import Foundation
import os.log

/// Centralized logging system for Dormant Chat
class DormantLogger {
    
    // MARK: - Singleton
    
    static let shared = DormantLogger()
    
    private init() {}
    
    // MARK: - Loggers
    
    private let networkLogger = Logger(subsystem: "com.dormant.chat", category: "Network")
    private let llmLogger = Logger(subsystem: "com.dormant.chat", category: "LLM")
    private let storageLogger = Logger(subsystem: "com.dormant.chat", category: "Storage")
    private let uiLogger = Logger(subsystem: "com.dormant.chat", category: "UI")
    private let securityLogger = Logger(subsystem: "com.dormant.chat", category: "Security")
    private let generalLogger = Logger(subsystem: "com.dormant.chat", category: "General")
    
    // MARK: - Log Levels
    
    enum LogLevel {
        case debug
        case info
        case notice
        case warning
        case error
        case critical
    }
    
    enum LogCategory {
        case network
        case llm
        case storage
        case ui
        case security
        case general
    }
    
    // MARK: - Logging Methods
    
    /// Log a message with specified level and category
    /// - Parameters:
    ///   - message: The message to log
    ///   - level: The log level
    ///   - category: The log category
    ///   - file: The source file (automatically filled)
    ///   - function: The source function (automatically filled)
    ///   - line: The source line (automatically filled)
    func log(
        _ message: String,
        level: LogLevel = .info,
        category: LogCategory = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let logger = getLogger(for: category)
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let logMessage = "[\(fileName):\(line)] \(function): \(message)"
        
        switch level {
        case .debug:
            logger.debug("\(logMessage)")
        case .info:
            logger.info("\(logMessage)")
        case .notice:
            logger.notice("\(logMessage)")
        case .warning:
            logger.warning("\(logMessage)")
        case .error:
            logger.error("\(logMessage)")
        case .critical:
            logger.critical("\(logMessage)")
        }
    }
    
    // MARK: - Convenience Methods
    
    func debug(_ message: String, category: LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, category: category, file: file, function: function, line: line)
    }
    
    func info(_ message: String, category: LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, category: category, file: file, function: function, line: line)
    }
    
    func notice(_ message: String, category: LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .notice, category: category, file: file, function: function, line: line)
    }
    
    func warning(_ message: String, category: LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, category: category, file: file, function: function, line: line)
    }
    
    func error(_ message: String, category: LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, category: category, file: file, function: function, line: line)
    }
    
    func critical(_ message: String, category: LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .critical, category: category, file: file, function: function, line: line)
    }
    
    // MARK: - Network Logging
    
    func logNetworkRequest(_ request: URLRequest) {
        var message = "HTTP \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "unknown")"
        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
            message += " Headers: \(headers.count)"
        }
        log(message, level: .debug, category: .network)
    }
    
    func logNetworkResponse(_ response: URLResponse?, data: Data?, error: Error?) {
        if let httpResponse = response as? HTTPURLResponse {
            let message = "HTTP \(httpResponse.statusCode) \(httpResponse.url?.absoluteString ?? "unknown") (\(data?.count ?? 0) bytes)"
            let level: LogLevel = httpResponse.statusCode >= 400 ? .error : .debug
            log(message, level: level, category: .network)
        }
        
        if let error = error {
            log("Network error: \(error.localizedDescription)", level: .error, category: .network)
        }
    }
    
    // MARK: - LLM Logging
    
    func logLLMRequest(provider: LLMProvider, model: String, tokenCount: Int) {
        log("LLM request to \(provider.displayName) (\(model)) - \(tokenCount) tokens", level: .info, category: .llm)
    }
    
    func logLLMResponse(provider: LLMProvider, responseTime: TimeInterval, tokenCount: Int) {
        log("LLM response from \(provider.displayName) - \(tokenCount) tokens in \(String(format: "%.2f", responseTime))s", level: .info, category: .llm)
    }
    
    func logLLMError(provider: LLMProvider, error: Error) {
        log("LLM error from \(provider.displayName): \(error.localizedDescription)", level: .error, category: .llm)
    }
    
    // MARK: - Storage Logging
    
    func logStorageOperation(_ operation: String, success: Bool, itemCount: Int? = nil) {
        let message = success ? 
            "Storage \(operation) succeeded" + (itemCount.map { " (\($0) items)" } ?? "") :
            "Storage \(operation) failed"
        log(message, level: success ? .debug : .error, category: .storage)
    }
    
    // MARK: - Security Logging
    
    func logSecurityEvent(_ event: String, success: Bool) {
        let message = "Security event: \(event) - \(success ? "success" : "failed")"
        log(message, level: success ? .info : .warning, category: .security)
    }
    
    func logAPIKeyOperation(_ operation: String, provider: LLMProvider, success: Bool) {
        let message = "API key \(operation) for \(provider.displayName) - \(success ? "success" : "failed")"
        log(message, level: success ? .info : .warning, category: .security)
    }
    
    // MARK: - UI Logging
    
    func logUIEvent(_ event: String, details: String? = nil) {
        let message = "UI event: \(event)" + (details.map { " - \($0)" } ?? "")
        log(message, level: .debug, category: .ui)
    }
    
    func logUserAction(_ action: String, context: String? = nil) {
        let message = "User action: \(action)" + (context.map { " (\($0))" } ?? "")
        log(message, level: .info, category: .ui)
    }
    
    // MARK: - Performance Logging
    
    func logPerformance(_ operation: String, duration: TimeInterval, details: String? = nil) {
        let message = "Performance: \(operation) took \(String(format: "%.3f", duration))s" + (details.map { " - \($0)" } ?? "")
        let level: LogLevel = duration > 1.0 ? .warning : .debug
        log(message, level: level, category: .general)
    }
    
    // MARK: - Private Methods
    
    private func getLogger(for category: LogCategory) -> Logger {
        switch category {
        case .network: return networkLogger
        case .llm: return llmLogger
        case .storage: return storageLogger
        case .ui: return uiLogger
        case .security: return securityLogger
        case .general: return generalLogger
        }
    }
}

// MARK: - Performance Measurement

/// Utility for measuring performance of operations
struct PerformanceMeasurement {
    private let startTime: CFAbsoluteTime
    private let operation: String
    private let logger = DormantLogger.shared
    
    init(_ operation: String) {
        self.operation = operation
        self.startTime = CFAbsoluteTimeGetCurrent()
        logger.debug("Started: \(operation)")
    }
    
    func finish(details: String? = nil) {
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        logger.logPerformance(operation, duration: duration, details: details)
    }
}

// MARK: - Global Logging Functions

/// Global convenience functions for logging
func logDebug(_ message: String, category: DormantLogger.LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
    DormantLogger.shared.debug(message, category: category, file: file, function: function, line: line)
}

func logInfo(_ message: String, category: DormantLogger.LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
    DormantLogger.shared.info(message, category: category, file: file, function: function, line: line)
}

func logWarning(_ message: String, category: DormantLogger.LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
    DormantLogger.shared.warning(message, category: category, file: file, function: function, line: line)
}

func logError(_ message: String, category: DormantLogger.LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
    DormantLogger.shared.error(message, category: category, file: file, function: function, line: line)
}

func logCritical(_ message: String, category: DormantLogger.LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
    DormantLogger.shared.critical(message, category: category, file: file, function: function, line: line)
}

/// Measure performance of a block of code
func measurePerformance<T>(_ operation: String, block: () throws -> T) rethrows -> T {
    let measurement = PerformanceMeasurement(operation)
    let result = try block()
    measurement.finish()
    return result
}

func measurePerformanceAsync<T>(_ operation: String, block: () async throws -> T) async rethrows -> T {
    let measurement = PerformanceMeasurement(operation)
    let result = try await block()
    measurement.finish()
    return result
}