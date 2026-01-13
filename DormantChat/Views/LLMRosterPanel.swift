import SwiftUI

/// LLM roster panel showing all configured agents and their states
struct LLMRosterPanel: View {
    @ObservedObject var agentManager: AgentStateManager
    @State private var selectedAgent: LLMAgent?
    @State private var showingAgentConfig: Bool = false
    @State private var hoveredAgent: UUID?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("AI Agents")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: {
                    showingAgentConfig = true
                }) {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("Add new AI agent")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(NSColor.separatorColor)),
                alignment: .bottom
            )
            
            // Agent list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(agentManager.agents) { agent in
                        AgentRowView(
                            agent: agent,
                            isHovered: hoveredAgent == agent.id,
                            onTap: {
                                selectedAgent = agent
                                showingAgentConfig = true
                            }
                        )
                        .onHover { isHovering in
                            hoveredAgent = isHovering ? agent.id : nil
                        }
                        
                        if agent.id != agentManager.agents.last?.id {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            
            Spacer()
            
            // Footer with status
            HStack {
                let awakeCount = agentManager.agents.filter { $0.state == .awake }.count
                let totalCount = agentManager.agents.count
                
                Text("\(awakeCount) of \(totalCount) awake")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Circle()
                    .fill(awakeCount > 0 ? Color.green : Color.gray.opacity(0.5))
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(NSColor.separatorColor)),
                alignment: .top
            )
        }
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingAgentConfig) {
            AgentConfigurationView(
                agent: selectedAgent,
                onSave: { agent in
                    if selectedAgent != nil {
                        agentManager.updateAgent(agent)
                    } else {
                        agentManager.addAgent(agent)
                    }
                    selectedAgent = nil
                },
                onCancel: {
                    selectedAgent = nil
                }
            )
        }
    }
}

// MARK: - Agent Row View

struct AgentRowView: View {
    let agent: LLMAgent
    let isHovered: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Status indicator
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.2))
                        .frame(width: 32, height: 32)
                    
                    Circle()
                        .fill(statusColor)
                        .frame(width: agent.state == .awake ? 16 : 12, height: agent.state == .awake ? 16 : 12)
                        .scaleEffect(agent.state == .thinking ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: agent.state == .thinking)
                    
                    if agent.state == .awake {
                        Circle()
                            .stroke(statusColor, lineWidth: 2)
                            .frame(width: 24, height: 24)
                            .opacity(0.6)
                    }
                }
                
                // Agent info
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text("\(agent.provider.displayName) • \(agent.model)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    if let lastWake = agent.lastWakeTime {
                        Text("Last active: \(formatRelativeTime(lastWake))")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
                
                Spacer()
                
                // State badge
                if agent.state != .dormant {
                    Text(agent.state.displayName.uppercased())
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(statusColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(statusColor.opacity(0.1))
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Rectangle()
                    .fill(isHovered ? Color(NSColor.controlAccentColor).opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var statusColor: Color {
        switch agent.state {
        case .dormant:
            return Color.gray.opacity(0.6)
        case .awake:
            return Color.green
        case .thinking:
            return Color.blue
        }
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Agent Configuration View

struct AgentConfigurationView: View {
    @State private var name: String
    @State private var provider: LLMProvider
    @State private var model: String
    @State private var personality: String
    @State private var temperature: Double
    @State private var maxTokens: Int
    
    let agent: LLMAgent?
    let onSave: (LLMAgent) -> Void
    let onCancel: () -> Void
    
    init(agent: LLMAgent?, onSave: @escaping (LLMAgent) -> Void, onCancel: @escaping () -> Void) {
        self.agent = agent
        self.onSave = onSave
        self.onCancel = onCancel
        
        // Initialize state from agent or defaults
        _name = State(initialValue: agent?.name ?? "")
        _provider = State(initialValue: agent?.provider ?? .openai)
        _model = State(initialValue: agent?.model ?? "")
        _personality = State(initialValue: agent?.personality ?? "")
        _temperature = State(initialValue: agent?.temperature ?? 0.7)
        _maxTokens = State(initialValue: agent?.maxTokens ?? 1000)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Basic Information") {
                    TextField("Agent Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                    
                    Picker("Provider", selection: $provider) {
                        ForEach(LLMProvider.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .onChange(of: provider) { newProvider in
                        // Update model to first default for new provider
                        if let firstModel = newProvider.defaultModels.first {
                            model = firstModel
                        }
                    }
                    
                    if provider.defaultModels.isEmpty {
                        TextField("Model", text: $model)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Picker("Model", selection: $model) {
                            ForEach(provider.defaultModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                    }
                }
                
                Section("Personality") {
                    TextField("Personality prompt", text: $personality, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                }
                
                Section("Parameters") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Temperature")
                            Spacer()
                            Text(String(format: "%.1f", temperature))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $temperature, in: 0...2, step: 0.1)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Max Tokens")
                            Spacer()
                            Text("\(maxTokens)")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(maxTokens) },
                            set: { maxTokens = Int($0) }
                        ), in: 100...4000, step: 100)
                    }
                }
            }
            .padding()
            .navigationTitle(agent == nil ? "Add Agent" : "Edit Agent")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let newAgent = LLMAgent(
                            id: agent?.id ?? UUID(),
                            name: name,
                            provider: provider,
                            model: model,
                            personality: personality,
                            temperature: temperature,
                            maxTokens: maxTokens,
                            state: agent?.state ?? .dormant,
                            lastWakeTime: agent?.lastWakeTime
                        )
                        onSave(newAgent)
                    }
                    .disabled(name.isEmpty || model.isEmpty)
                }
            }
        }
        .frame(width: 500, height: 600)
    }
}

// MARK: - Preview

#Preview {
    let agentManager = AgentStateManager()
    
    // Add some sample agents
    agentManager.agents = [
        LLMAgent(
            name: "Claude",
            provider: .anthropic,
            model: "claude-3-sonnet",
            personality: "Helpful and thoughtful AI assistant",
            state: .awake,
            lastWakeTime: Date().addingTimeInterval(-300) // 5 minutes ago
        ),
        LLMAgent(
            name: "GPT-4",
            provider: .openai,
            model: "gpt-4",
            personality: "Creative and analytical AI assistant",
            state: .thinking,
            lastWakeTime: Date().addingTimeInterval(-60) // 1 minute ago
        ),
        LLMAgent(
            name: "Llama",
            provider: .ollama,
            model: "llama2",
            personality: "Local AI assistant focused on privacy",
            state: .dormant,
            lastWakeTime: Date().addingTimeInterval(-3600) // 1 hour ago
        )
    ]
    
    return LLMRosterPanel(agentManager: agentManager)
        .frame(width: 250, height: 600)
}