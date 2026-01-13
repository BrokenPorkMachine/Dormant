import Foundation

/// Simple agent validator for basic validation
struct AgentValidator {
    
    /// Check if an agent configuration is valid
    /// - Parameter agent: The agent to validate
    /// - Returns: True if the agent is valid
    static func isValid(_ agent: LLMAgent) -> Bool {
        // Basic validation - name and model cannot be empty
        guard !agent.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        
        guard !agent.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        
        // Temperature should be reasonable
        guard agent.temperature >= 0.0 && agent.temperature <= 2.0 else {
            return false
        }
        
        // Max tokens should be positive
        guard agent.maxTokens > 0 else {
            return false
        }
        
        return true
    }
}