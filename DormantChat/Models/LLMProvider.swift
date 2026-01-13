import Foundation

/// LLM Provider enumeration
enum LLMProvider: String, CaseIterable, Codable {
    case openai = "OpenAI"
    case anthropic = "Anthropic"
    case huggingface = "Hugging Face"
    case ollama = "Ollama"
    case gemini = "Google Gemini"
    case grok = "xAI Grok"
    case cohere = "Cohere"
    case mistral = "Mistral AI"
    case perplexity = "Perplexity"
    case together = "Together AI"
    case replicate = "Replicate"
    case groq = "Groq"
    case custom = "Custom"
    
    var displayName: String {
        return self.rawValue
    }
    
    var requiresAPIKey: Bool {
        switch self {
        case .ollama:
            return false
        case .openai, .anthropic, .huggingface, .gemini, .grok, .cohere, .mistral, .perplexity, .together, .replicate, .groq, .custom:
            return true
        }
    }
    
    var defaultModels: [String] {
        switch self {
        case .openai:
            return ["gpt-4", "gpt-4-turbo", "gpt-3.5-turbo", "gpt-4o", "gpt-4o-mini"]
        case .anthropic:
            return ["claude-3-opus", "claude-3-sonnet", "claude-3-haiku", "claude-3-5-sonnet"]
        case .huggingface:
            return ["microsoft/DialoGPT-medium", "facebook/blenderbot-400M-distill", "EleutherAI/gpt-j-6B"]
        case .ollama:
            return ["llama2", "codellama", "mistral", "llama3", "phi3", "gemma"]
        case .gemini:
            return ["gemini-pro", "gemini-pro-vision", "gemini-1.5-pro", "gemini-1.5-flash"]
        case .grok:
            return ["grok-beta", "grok-vision-beta"]
        case .cohere:
            return ["command", "command-light", "command-nightly", "command-r", "command-r-plus"]
        case .mistral:
            return ["mistral-tiny", "mistral-small", "mistral-medium", "mistral-large", "mixtral-8x7b"]
        case .perplexity:
            return ["llama-3-sonar-small-32k-chat", "llama-3-sonar-large-32k-chat", "llama-3-70b-instruct"]
        case .together:
            return ["meta-llama/Llama-2-70b-chat-hf", "mistralai/Mixtral-8x7B-Instruct-v0.1", "NousResearch/Nous-Hermes-2-Mixtral-8x7B-DPO"]
        case .replicate:
            return ["meta/llama-2-70b-chat", "mistralai/mixtral-8x7b-instruct-v0.1", "meta/codellama-34b-instruct"]
        case .groq:
            return ["llama3-8b-8192", "llama3-70b-8192", "mixtral-8x7b-32768", "gemma-7b-it"]
        case .custom:
            return []
        }
    }
    
    var baseURL: String {
        switch self {
        case .openai:
            return "https://api.openai.com/v1"
        case .anthropic:
            return "https://api.anthropic.com/v1"
        case .huggingface:
            return "https://api-inference.huggingface.co/models"
        case .ollama:
            return "http://localhost:11434/api"
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta"
        case .grok:
            return "https://api.x.ai/v1"
        case .cohere:
            return "https://api.cohere.ai/v1"
        case .mistral:
            return "https://api.mistral.ai/v1"
        case .perplexity:
            return "https://api.perplexity.ai"
        case .together:
            return "https://api.together.xyz/v1"
        case .replicate:
            return "https://api.replicate.com/v1"
        case .groq:
            return "https://api.groq.com/openai/v1"
        case .custom:
            return ""
        }
    }
}

#if canImport(SwiftCheck)
import SwiftCheck

extension LLMProvider: Arbitrary {
    public static var arbitrary: Gen<LLMProvider> {
        return Gen.fromElements(of: LLMProvider.allCases)
    }
}
#endif