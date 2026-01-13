import Foundation

/// Dedicated mention scanner for parsing @mentions and providing autocomplete functionality
struct MentionScanner {
    
    /// Extract @mentions from text content
    /// - Parameter text: The text to scan for mentions
    /// - Returns: Array of mention names (without the @ symbol)
    func extractMentions(from text: String) -> [String] {
        // Use word boundaries to avoid matching emails and allow hyphens in names
        let pattern = #"(?<!\w)@([\w-]+)(?!\w*\.)"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let nsString = text as NSString
        let results = regex?.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
        
        return results.compactMap { result in
            if result.numberOfRanges > 1 {
                return nsString.substring(with: result.range(at: 1))
            }
            return nil
        }
    }
    
    /// Build mention suggestions for autocomplete functionality
    /// - Parameters:
    ///   - partial: The partial mention text (without @)
    ///   - agents: Array of configured LLM agents
    /// - Returns: Array of suggested agent names that match the partial input
    func buildMentionSuggestions(for partial: String, agents: [LLMAgent]) -> [String] {
        let lowercasePartial = partial.lowercased()
        
        // If partial is empty, return all agent names
        guard !lowercasePartial.isEmpty else {
            return agents.map { $0.name }.sorted()
        }
        
        // Find agents whose names start with the partial text
        let matches = agents.filter { agent in
            agent.name.lowercased().hasPrefix(lowercasePartial)
        }.map { $0.name }
        
        // Return matches sorted
        return matches.sorted()
    }
    
    /// Validate a mention against configured agents
    /// - Parameters:
    ///   - mention: The mention name to validate (without @)
    ///   - agents: Array of configured LLM agents
    /// - Returns: The matching LLMAgent if found, nil otherwise
    func validateMention(_ mention: String, against agents: [LLMAgent]) -> LLMAgent? {
        return agents.first { agent in
            agent.name.lowercased() == mention.lowercased()
        }
    }
    
    /// Find partial mentions in text for autocomplete
    /// - Parameter text: The text to scan
    /// - Returns: Array of partial mentions found (including the @ symbol and partial text)
    func findPartialMentions(in text: String) -> [String] {
        let pattern = #"@(\w*)"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let nsString = text as NSString
        let results = regex?.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
        
        return results.compactMap { result in
            return nsString.substring(with: result.range)
        }
    }
    
    /// Get the current partial mention being typed at cursor position
    /// - Parameters:
    ///   - text: The full text
    ///   - cursorPosition: The current cursor position
    /// - Returns: The partial mention being typed, or nil if not typing a mention
    func getCurrentPartialMention(in text: String, at cursorPosition: Int) -> String? {
        guard cursorPosition <= text.count else { return nil }
        
        let textUpToCursor = String(text.prefix(cursorPosition))
        
        // Look for the last @ symbol before cursor
        guard let lastAtIndex = textUpToCursor.lastIndex(of: "@") else { return nil }
        
        let mentionText = String(textUpToCursor.suffix(from: lastAtIndex))
        
        // Check if there's any whitespace after the @ (which would end the mention)
        if mentionText.dropFirst().contains(where: { $0.isWhitespace }) {
            return nil
        }
        
        // Return the partial mention without the @ symbol
        return String(mentionText.dropFirst())
    }
    
    /// Replace a partial mention with a complete mention
    /// - Parameters:
    ///   - text: The original text
    ///   - partialMention: The partial mention to replace (with @)
    ///   - completeMention: The complete mention name (without @)
    /// - Returns: The text with the partial mention replaced
    func replaceMention(in text: String, replacing partialMention: String, with completeMention: String) -> String {
        return text.replacingOccurrences(of: partialMention, with: "@\(completeMention)")
    }
}