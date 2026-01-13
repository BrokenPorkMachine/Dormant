import SwiftUI

struct MainWindowView: View {
    @StateObject private var chatViewModel = ChatViewModel()
    @StateObject private var agentManager = AgentStateManager()
    @StateObject private var webSocketManager = WebSocketManager()
    @StateObject private var errorHandler = ErrorHandler.shared
    @State private var currentRoomId = UUID()
    @State private var showingSettings = false
    @State private var showingAbout = false
    @State private var showingErrorHistory = false
    @State private var selectedRoom: ChatRoom?
    @State private var rooms: [ChatRoom] = []
    @State private var errorToasts: [DormantError] = []
    
    var body: some View {
        NavigationSplitView {
            // Left sidebar - Navigation and LLM roster
            VStack(spacing: 0) {
                // Header with app title and controls
                HStack {
                    Text("Dormant")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Menu {
                        Button("Settings") {
                            showingSettings = true
                        }
                        
                        Button("Error History") {
                            showingErrorHistory = true
                        }
                        
                        Button("About") {
                            showingAbout = true
                        }
                        
                        Divider()
                        
                        Button("Quit Dormant") {
                            NSApplication.shared.terminate(nil)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    .menuStyle(BorderlessButtonMenuStyle())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // Room selection (placeholder for future multi-room support)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Rooms")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button(action: createNewRoom) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Current room
                    HStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        
                        Text("General")
                            .font(.subheadline)
                        
                        Spacer()
                        
                        Text("\(agentManager.getAwakeAgents().count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                Divider()
                
                // LLM Roster Panel
                LLMRosterPanel(agentManager: agentManager)
                
                Spacer()
                
                // Connection status
                HStack {
                    Circle()
                        .fill(webSocketManager.connectionState == .connected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    
                    Text(webSocketManager.connectionState == .connected ? "Connected" : "Disconnected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .frame(minWidth: 250, maxWidth: 300)
            .background(Color(NSColor.controlBackgroundColor))
        } detail: {
            // Main chat area
            ChatAreaView(
                chatViewModel: chatViewModel,
                agentManager: agentManager,
                webSocketManager: webSocketManager,
                currentRoomId: currentRoomId
            )
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .sheet(isPresented: $showingErrorHistory) {
            ErrorHistoryView()
        }
        .alert("Error", isPresented: $errorHandler.showingErrorAlert) {
            if let error = errorHandler.currentError {
                let recoveryActions = errorHandler.getRecoveryActions(for: error)
                
                ForEach(recoveryActions.indices, id: \.self) { index in
                    let action = recoveryActions[index]
                    Button(action.title) {
                        action.action()
                        errorHandler.clearCurrentError()
                    }
                }
                
                Button("Dismiss") {
                    errorHandler.clearCurrentError()
                }
            }
        } message: {
            if let error = errorHandler.currentError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error.localizedDescription)
                    
                    if let suggestion = error.recoverySuggestion {
                        Text(suggestion)
                            .font(.caption)
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            // Error toasts
            VStack(spacing: 8) {
                ForEach(errorToasts, id: \.id) { error in
                    ErrorToastView(error: error) {
                        withAnimation {
                            errorToasts.removeAll { $0.id == error.id }
                        }
                    }
                }
            }
            .padding(.top, 60)
            .padding(.trailing, 20)
        }
        .onAppear {
            setupApplication()
        }
        .onReceive(errorHandler.$currentError) { error in
            // Show toast for low/medium severity errors instead of alert
            if let error = error, error.severity == .low || error.severity == .medium {
                withAnimation {
                    errorToasts.append(error)
                }
                errorHandler.clearCurrentError()
            }
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }
    
    // MARK: - Computed Properties
    
    private var isDarkMode: Bool {
        UserDefaults.standard.bool(forKey: "isDarkMode")
    }
    
    // MARK: - Private Methods
    
    private func setupApplication() {
        logInfo("Application starting up", category: .ui)
        
        // Initialize with sample agents if none exist
        if agentManager.agents.isEmpty {
            agentManager.agents = chatViewModel.availableAgents
            logInfo("Initialized with \(agentManager.agents.count) sample agents", category: .general)
        }
        
        // Connect to WebSocket with error handling
        Task {
            do {
                try await webSocketManager.connect(to: URL(string: "ws://localhost:8080")!)
                logInfo("WebSocket connected successfully", category: .network)
            } catch {
                logError("Failed to connect to WebSocket: \(error.localizedDescription)", category: .network)
                errorHandler.handle(error, context: "WebSocket connection", showToUser: false)
            }
        }
        
        // Apply saved appearance
        updateAppearance()
        logInfo("Application setup complete", category: .ui)
    }
    
    private func updateAppearance() {
        let isDark = UserDefaults.standard.bool(forKey: "isDarkMode")
        if isDark {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        } else {
            NSApp.appearance = NSAppearance(named: .aqua)
        }
        logDebug("Updated appearance to \(isDark ? "dark" : "light") mode", category: .ui)
    }
    
    private func createNewRoom() {
        logInfo("User requested new room creation", category: .ui)
        // TODO: Implement room creation
        errorHandler.handle(
            .system(.configurationError),
            context: "Room creation not yet implemented",
            showToUser: true
        )
    }
}

// MARK: - Chat Area View

struct ChatAreaView: View {
    @ObservedObject var chatViewModel: ChatViewModel
    @ObservedObject var agentManager: AgentStateManager
    @ObservedObject var webSocketManager: WebSocketManager
    let currentRoomId: UUID
    
    var body: some View {
        VStack(spacing: 0) {
            // Chat header with room info
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("General Chat")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("\(agentManager.agents.count) agents • \(agentManager.getAwakeAgents().count) awake")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Quick actions
                HStack(spacing: 12) {
                    Button(action: wakeAllAgents) {
                        Image(systemName: "bell.fill")
                            .foregroundColor(.orange)
                    }
                    .help("Wake all agents")
                    
                    Button(action: sleepAllAgents) {
                        Image(systemName: "moon.fill")
                            .foregroundColor(.blue)
                    }
                    .help("Sleep all agents")
                    
                    Button(action: clearChat) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .help("Clear chat history")
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(NSColor.separatorColor)),
                alignment: .bottom
            )
            
            // Chat timeline
            ChatTimelineView(
                currentUserId: "current-user",
                roomId: currentRoomId
            )
            
            // Message input
            MessageInputBar(
                availableAgents: agentManager.agents,
                onSendMessage: { message in
                    chatViewModel.sendMessage(message, roomId: currentRoomId, agentManager: agentManager)
                }
            )
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(NSColor.separatorColor)),
                alignment: .top
            )
        }
    }
    
    // MARK: - Private Methods
    
    private func wakeAllAgents() {
        for agent in agentManager.agents {
            agentManager.wakeAgent(agent.id)
        }
    }
    
    private func sleepAllAgents() {
        for agent in agentManager.agents {
            agentManager.sleepAgent(agent.id)
        }
    }
    
    private func clearChat() {
        // TODO: Implement chat clearing
        print("Clear chat history")
    }
}

// MARK: - About View

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            // App icon and title
            VStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)
                
                Text("Dormant Chat")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Privacy-First AI Chat Platform")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            
            // Version info
            VStack(spacing: 8) {
                Text("Version 1.0.0")
                    .font(.subheadline)
                
                Text("Built with SwiftUI")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Features
            VStack(alignment: .leading, spacing: 8) {
                Text("Features:")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("• Privacy-first architecture")
                    Text("• Multiple LLM provider support")
                    Text("• Real-time collaborative chat")
                    Text("• AI agent wake/sleep lifecycle")
                    Text("• End-to-end encryption")
                    Text("• Local data storage")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            
            // Links
            HStack(spacing: 20) {
                Link("Website", destination: URL(string: "https://dormant.chat")!)
                Link("GitHub", destination: URL(string: "https://github.com/dormant-chat/dormant")!)
                Link("Privacy Policy", destination: URL(string: "https://dormant.chat/privacy")!)
            }
            .font(.subheadline)
            
            Spacer()
        }
        .padding(40)
        .frame(width: 400, height: 500)
    }
}

#Preview {
    MainWindowView()
}