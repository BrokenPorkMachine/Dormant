import SwiftUI

/// Message input bar with @mention autocomplete support
struct MessageInputBar: View {
    @State private var messageText: String = ""
    @State private var showingAutocomplete: Bool = false
    @State private var autocompleteAgents: [LLMAgent] = []
    @FocusState private var isTextFieldFocused: Bool
    
    let availableAgents: [LLMAgent]
    let onSendMessage: (String) -> Void
    
    private let mentionScanner = MentionScanner()
    
    var body: some View {
        VStack(spacing: 0) {
            // Autocomplete dropdown
            if showingAutocomplete && !autocompleteAgents.isEmpty {
                autocompleteView
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            
            // Input bar
            HStack(spacing: 12) {
                // Text input field
                TextField("Type a message...", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                    .focused($isTextFieldFocused)
                    .onChange(of: messageText) { newValue in
                        handleTextChange(newValue)
                    }
                    .onSubmit {
                        sendMessage()
                    }
                
                // Send button
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
    
    // MARK: - Autocomplete View
    
    private var autocompleteView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(autocompleteAgents.prefix(5).enumerated()), id: \.element.id) { index, agent in
                Button(action: {
                    selectAgent(agent)
                }) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(agent.state == .awake ? Color.green : Color.gray.opacity(0.5))
                            .frame(width: 10, height: 10)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.name)
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            Text("\(agent.provider.displayName) • \(agent.model)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if agent.state == .awake {
                            Text("AWAKE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.green.opacity(0.1)))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(NSColor.windowBackgroundColor))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                if index < min(4, autocompleteAgents.count - 1) {
                    Divider().padding(.leading, 38)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
    
    // MARK: - Text Handling
    
    private func handleTextChange(_ newValue: String) {
        // Find current cursor position and check if we're typing a mention
        if let lastAtIndex = newValue.lastIndex(of: "@") {
            let afterAt = String(newValue[newValue.index(after: lastAtIndex)...])
            
            // Check if we're still typing the mention (no spaces after @)
            if !afterAt.contains(" ") && !afterAt.isEmpty {
                let partialMention = afterAt
                updateAutocomplete(for: partialMention)
                showingAutocomplete = true
            } else if afterAt.isEmpty {
                // Just typed @, show all agents
                updateAutocomplete(for: "")
                showingAutocomplete = true
            } else {
                hideAutocomplete()
            }
        } else {
            hideAutocomplete()
        }
    }
    
    private func updateAutocomplete(for partial: String) {
        autocompleteAgents = mentionScanner.buildMentionSuggestions(
            for: partial,
            agents: availableAgents
        ).compactMap { suggestion in
            availableAgents.first { $0.name.lowercased() == suggestion.lowercased() }
        }
    }
    
    private func hideAutocomplete() {
        withAnimation(.easeOut(duration: 0.2)) {
            showingAutocomplete = false
        }
        autocompleteAgents = []
    }
    
    private func selectAgent(_ agent: LLMAgent) {
        // Find the last @ symbol and replace the partial mention
        if let lastAtIndex = messageText.lastIndex(of: "@") {
            let beforeAt = String(messageText[..<lastAtIndex])
            let afterAt = String(messageText[messageText.index(after: lastAtIndex)...])
            
            // Find where the current mention ends (space or end of string)
            let mentionEnd = afterAt.firstIndex(of: " ") ?? afterAt.endIndex
            let afterMention = String(afterAt[mentionEnd...])
            
            messageText = beforeAt + "@" + agent.name + " " + afterMention
        }
        
        hideAutocomplete()
        isTextFieldFocused = true
    }
    
    // MARK: - Message Sending
    
    private func sendMessage() {
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }
        
        onSendMessage(trimmedMessage)
        messageText = ""
        hideAutocomplete()
    }
}

// MARK: - Preview

#Preview {
    let sampleAgents = [
        LLMAgent(
            name: "Claude",
            provider: .anthropic,
            model: "claude-3-sonnet",
            state: .dormant
        ),
        LLMAgent(
            name: "GPT-4",
            provider: .openai,
            model: "gpt-4",
            state: .awake
        ),
        LLMAgent(
            name: "Llama",
            provider: .ollama,
            model: "llama2",
            state: .dormant
        )
    ]
    
    VStack {
        Spacer()
        MessageInputBar(
            availableAgents: sampleAgents,
            onSendMessage: { message in
                print("Sending message: \(message)")
            }
        )
    }
    .padding()
    .background(Color(NSColor.controlBackgroundColor))
}