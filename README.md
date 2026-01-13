# Dormant Chat

A privacy-first, real-time collaborative chat platform that integrates humans and multiple AI agents (LLMs) in the same environment.

## Project Structure

```
DormantChat/
├── DormantChatApp.swift          # Main app entry point
├── ContentView.swift             # Main UI view
└── Models/                       # Core data models
    ├── LLMAgent.swift           # LLM agent configuration
    ├── AgentState.swift         # Agent state enumeration
    ├── LLMProvider.swift        # LLM provider enumeration
    ├── MessageSender.swift      # Message sender types
    ├── ChatMessage.swift        # Chat message model
    └── ChatRoom.swift           # Chat room configuration

Tests/
└── DormantChatTests.swift       # Unit and property-based tests

Package.swift                     # Swift Package Manager configuration
```

## Core Models

### LLMAgent
Represents an AI agent configuration with provider, model, personality, and state management.

### ChatMessage
Represents a chat message with content, sender information, timestamp, and mention extraction capabilities.

### ChatRoom
Represents a chat room with participant management and optional encryption settings.

### Enumerations
- **AgentState**: dormant, awake, thinking
- **LLMProvider**: OpenAI, Anthropic, Hugging Face, Ollama, Custom
- **MessageSender**: human, llm, system

## Testing

The project uses Swift Testing framework with SwiftCheck for property-based testing.

Run tests with:
```bash
swift test
```

## Requirements

- macOS 14.0+
- iOS 17.0+
- iPadOS 17.0+
- Swift 5.9+