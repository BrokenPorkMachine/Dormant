import SwiftUI

/// Reusable error alert view with recovery actions
struct ErrorAlertView: View {
    let error: DormantError
    let onDismiss: () -> Void
    let onRecoveryAction: ((RecoveryAction) -> Void)?
    
    @State private var showingDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Error header
            HStack {
                Image(systemName: iconName)
                    .foregroundColor(error.severity.color)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(error.category.rawValue)
                        .font(.headline)
                        .foregroundColor(error.severity.color)
                    
                    Text(error.severity.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Details") {
                    showingDetails.toggle()
                }
                .font(.caption)
            }
            
            // Error message
            Text(error.localizedDescription)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            
            // Recovery suggestion
            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Details (expandable)
            if showingDetails {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    
                    HStack {
                        Text("Error Code:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(error.code)")
                            .font(.caption.monospaced())
                    }
                    
                    HStack {
                        Text("Category:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(error.category.rawValue)
                            .font(.caption)
                    }
                    
                    HStack {
                        Text("Severity:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(error.severity.displayName)
                            .font(.caption)
                            .foregroundColor(error.severity.color)
                    }
                }
                .padding(.top, 8)
            }
            
            // Recovery actions
            let recoveryActions = ErrorHandler.shared.getRecoveryActions(for: error)
            if !recoveryActions.isEmpty {
                Divider()
                
                HStack {
                    ForEach(recoveryActions.indices, id: \.self) { index in
                        let action = recoveryActions[index]
                        Button(action.title) {
                            action.action()
                            onRecoveryAction?(action)
                        }
                        .buttonStyle(.bordered)
                        
                        if index < recoveryActions.count - 1 {
                            Spacer()
                        }
                    }
                }
            }
            
            // Dismiss button
            HStack {
                Spacer()
                Button("Dismiss") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(maxWidth: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 10)
    }
    
    private var iconName: String {
        switch error.severity {
        case .low:
            return "info.circle.fill"
        case .medium:
            return "exclamationmark.triangle.fill"
        case .high:
            return "xmark.circle.fill"
        case .critical:
            return "exclamationmark.octagon.fill"
        }
    }
}

/// Error toast notification for non-critical errors
struct ErrorToastView: View {
    let error: DormantError
    let onDismiss: () -> Void
    
    @State private var isVisible = false
    
    var body: some View {
        HStack {
            Image(systemName: iconName)
                .foregroundColor(error.severity.color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(error.category.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                
                Text(error.localizedDescription)
                    .font(.caption)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 2)
        .scaleEffect(isVisible ? 1.0 : 0.8)
        .opacity(isVisible ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.2)) {
                isVisible = true
            }
            
            // Auto-dismiss after 5 seconds for low severity errors
            if error.severity == .low {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    dismissWithAnimation()
                }
            }
        }
    }
    
    private var iconName: String {
        switch error.severity {
        case .low:
            return "info.circle"
        case .medium:
            return "exclamationmark.triangle"
        case .high:
            return "xmark.circle"
        case .critical:
            return "exclamationmark.octagon"
        }
    }
    
    private func dismissWithAnimation() {
        withAnimation(.easeIn(duration: 0.2)) {
            isVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }
}

/// Error history view for debugging
struct ErrorHistoryView: View {
    @ObservedObject private var errorHandler = ErrorHandler.shared
    
    var body: some View {
        NavigationView {
            List {
                ForEach(errorHandler.errorHistory.reversed()) { entry in
                    ErrorHistoryRowView(entry: entry)
                }
            }
            .navigationTitle("Error History")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear") {
                        errorHandler.clearHistory()
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

struct ErrorHistoryRowView: View {
    let entry: ErrorLogEntry
    
    @State private var showingDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(entry.error.severity.color)
                    .frame(width: 8, height: 8)
                
                Text(entry.error.category.rawValue)
                    .font(.headline)
                
                Spacer()
                
                Text(entry.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(entry.error.localizedDescription)
                .font(.subheadline)
                .lineLimit(showingDetails ? nil : 2)
            
            if !entry.context.isEmpty {
                Text("Context: \(entry.context)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(showingDetails ? nil : 1)
            }
            
            if showingDetails {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Error Code: \(entry.error.code)")
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                    
                    if let suggestion = entry.error.recoverySuggestion {
                        Text("Suggestion: \(suggestion)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                showingDetails.toggle()
            }
        }
    }
}

#Preview("Error Alert") {
    ErrorAlertView(
        error: .network(.connectionFailed),
        onDismiss: {},
        onRecoveryAction: nil
    )
}

#Preview("Error Toast") {
    ErrorToastView(
        error: .validation(.invalidInput("API Key")),
        onDismiss: {}
    )
}

#Preview("Error History") {
    ErrorHistoryView()
}