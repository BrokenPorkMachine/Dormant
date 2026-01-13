import Foundation

/// Message sender enumeration
enum MessageSender: Codable, Equatable {
    case human(userId: String, username: String)
    case llm(agentId: UUID, agentName: String, provider: LLMProvider)
    case system(type: SystemMessageType)
    
    var displayName: String {
        switch self {
        case .human(_, let username):
            return username
        case .llm(_, let agentName, _):
            return agentName
        case .system(let type):
            return type.displayName
        }
    }
    
    var isHuman: Bool {
        if case .human = self {
            return true
        }
        return false
    }
    
    var isLLM: Bool {
        if case .llm = self {
            return true
        }
        return false
    }
    
    var isSystem: Bool {
        if case .system = self {
            return true
        }
        return false
    }
}

/// System message types
enum SystemMessageType: String, Codable, CaseIterable {
    case agentWake = "agent_wake"
    case agentSleep = "agent_sleep"
    case roomJoin = "room_join"
    case roomLeave = "room_leave"
    case error = "error"
    
    var displayName: String {
        switch self {
        case .agentWake:
            return "Agent Awakened"
        case .agentSleep:
            return "Agent Dormant"
        case .roomJoin:
            return "Joined Room"
        case .roomLeave:
            return "Left Room"
        case .error:
            return "System Error"
        }
    }
}