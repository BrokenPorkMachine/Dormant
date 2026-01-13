import Foundation

/// Agent state enumeration
enum AgentState: String, Codable, CaseIterable {
    case dormant
    case awake
    case thinking
    
    var displayName: String {
        switch self {
        case .dormant:
            return "Dormant"
        case .awake:
            return "Awake"
        case .thinking:
            return "Thinking"
        }
    }
    
    var isActive: Bool {
        switch self {
        case .dormant:
            return false
        case .awake, .thinking:
            return true
        }
    }
}