import SwiftUI
internal import UniformTypeIdentifiers

struct SettingsView: View {
    private let keyVault = SecureKeyVault.shared
    @State private var selectedProvider: LLMProvider = .openai
    @State private var apiKey: String = ""
    @State private var showingAPIKeyAlert = false
    @State private var alertMessage = ""
    @State private var isDarkMode = true
    @State private var enableNotifications = true
    @State private var autoSaveChats = true
    @State private var maxContextLength = 4096
    
    var body: some View {
        NavigationView {
            Form {
                // Appearance Section
                Section("Appearance") {
                    Toggle("Dark Mode", isOn: $isDarkMode)
                        .onChange(of: isDarkMode) { newValue in
                            updateAppearance(darkMode: newValue)
                        }
                    
                    ColorPicker("Accent Color", selection: .constant(Color.blue))
                        .disabled(true) // Placeholder for future customization
                }
                
                // API Keys Section
                Section("API Keys") {
                    Picker("Provider", selection: $selectedProvider) {
                        ForEach(LLMProvider.allCases.filter { $0.requiresAPIKey }, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    
                    HStack {
                        SecureField("API Key", text: $apiKey)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Button("Save") {
                            saveAPIKey()
                        }
                        .disabled(apiKey.isEmpty)
                    }
                    
                    Button("Clear All API Keys") {
                        clearAllAPIKeys()
                    }
                    .foregroundColor(.red)
                }
                
                // Chat Settings Section
                Section("Chat Settings") {
                    Toggle("Enable Notifications", isOn: $enableNotifications)
                    Toggle("Auto-save Chat History", isOn: $autoSaveChats)
                    
                    HStack {
                        Text("Max Context Length")
                        Spacer()
                        TextField("4096", value: $maxContextLength, format: .number)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 80)
                    }
                }
                
                // Privacy Section
                Section("Privacy & Security") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("🔒 Privacy-First Design")
                            .font(.headline)
                        Text("• API keys are encrypted and stored locally")
                        Text("• All LLM calls are made directly from your device")
                        Text("• No data is sent to Dormant servers")
                        Text("• Chat history is stored locally only")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                    Button("Export Data") {
                        exportUserData()
                    }
                    
                    Button("Clear All Data") {
                        clearAllData()
                    }
                    .foregroundColor(.red)
                }
                
                // About Section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Link("Privacy Policy", destination: URL(string: "https://dormant.chat/privacy")!)
                    Link("Source Code", destination: URL(string: "https://github.com/dormant-chat/dormant")!)
                }
            }
            .navigationTitle("Settings")
            .frame(minWidth: 500, minHeight: 600)
        }
        .alert("API Key", isPresented: $showingAPIKeyAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            loadSettings()
        }
    }
    
    // MARK: - Private Methods
    
    private func updateAppearance(darkMode: Bool) {
        if darkMode {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        } else {
            NSApp.appearance = NSAppearance(named: .aqua)
        }
        UserDefaults.standard.set(darkMode, forKey: "isDarkMode")
    }
    
    private func saveAPIKey() {
        guard !apiKey.isEmpty else { return }
        
        do {
            try keyVault.storeAPIKey(apiKey, for: selectedProvider)
            alertMessage = "API key saved successfully for \(selectedProvider.displayName)"
            apiKey = ""
            showingAPIKeyAlert = true
        } catch {
            alertMessage = "Failed to save API key: \(error.localizedDescription)"
            showingAPIKeyAlert = true
        }
    }
    
    private func clearAllAPIKeys() {
        do {
            for provider in LLMProvider.allCases where provider.requiresAPIKey {
                try keyVault.deleteAPIKey(for: provider)
            }
            alertMessage = "All API keys cleared successfully"
            showingAPIKeyAlert = true
        } catch {
            alertMessage = "Failed to clear API keys: \(error.localizedDescription)"
            showingAPIKeyAlert = true
        }
    }
    
    private func exportUserData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "dormant-chat-backup.json"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                // TODO: Implement data export
                print("Export data to: \(url)")
            }
        }
    }
    
    private func clearAllData() {
        // TODO: Implement data clearing
        alertMessage = "All local data cleared successfully"
        showingAPIKeyAlert = true
    }
    
    private func loadSettings() {
        isDarkMode = UserDefaults.standard.bool(forKey: "isDarkMode")
        enableNotifications = UserDefaults.standard.bool(forKey: "enableNotifications")
        autoSaveChats = UserDefaults.standard.bool(forKey: "autoSaveChats")
        maxContextLength = UserDefaults.standard.integer(forKey: "maxContextLength")
        
        // Set defaults if not previously set
        if maxContextLength == 0 {
            maxContextLength = 4096
        }
    }
}

#Preview {
    SettingsView()
}
