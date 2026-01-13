import SwiftUI

@main
struct DormantChatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
                .onAppear {
                    setupAppearance()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            // File menu
            CommandGroup(replacing: .newItem) {
                Button("New Room") {
                    // TODO: Implement new room creation
                }
                .keyboardShortcut("n")
            }
            
            // View menu
            CommandGroup(after: .windowArrangement) {
                Button("Toggle Sidebar") {
                    NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
                }
                .keyboardShortcut("s", modifiers: [.command])
                
                Divider()
                
                Button("Actual Size") {
                    // TODO: Implement zoom reset
                }
                .keyboardShortcut("0")
            }
        }
    }
    
    private func setupAppearance() {
        // Set default dark mode if not previously configured
        if UserDefaults.standard.object(forKey: "isDarkMode") == nil {
            UserDefaults.standard.set(true, forKey: "isDarkMode")
        }
        
        let isDark = UserDefaults.standard.bool(forKey: "isDarkMode")
        NSApp.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Configure window appearance
        if let window = NSApp.windows.first {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}