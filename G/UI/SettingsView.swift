import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @Environment(\.dismiss) var dismiss
    @State private var apiKeyInput = ""
    @State private var showingAPIKey = false

    var body: some View {
        NavigationStack {
            List {
                // API Key
                Section {
                    HStack {
                        if showingAPIKey {
                            TextField("sk-ant-...", text: $apiKeyInput)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(.body, design: .monospaced))
                        } else {
                            Text(maskedKey)
                                .foregroundColor(.gTextDim)
                                .font(.system(.body, design: .monospaced))
                        }

                        Button(showingAPIKey ? "Hide" : "Edit") {
                            if showingAPIKey {
                                // Save
                                if !apiKeyInput.isEmpty {
                                    settings.claudeAPIKey = apiKeyInput
                                }
                                showingAPIKey = false
                            } else {
                                apiKeyInput = settings.claudeAPIKey
                                showingAPIKey = true
                            }
                        }
                        .foregroundColor(.gAccent)
                    }
                } header: {
                    Text("Claude API Key")
                } footer: {
                    Text("Get your key at console.anthropic.com")
                }

                // Voice
                Section {
                    Toggle("\"Hey G\" wake word", isOn: $settings.wakeWordEnabled)
                    Toggle("Speak responses aloud", isOn: $settings.voiceResponseEnabled)
                    Toggle("Haptic feedback", isOn: $settings.hapticFeedbackEnabled)
                } header: {
                    Text("Voice")
                } footer: {
                    if settings.wakeWordEnabled {
                        Text("G is always listening while the app is open. Say \"Hey G\" or \"G,\" followed by your request.")
                    } else {
                        Text("Tap the mic button to talk to G.")
                    }
                }

                // Lock Screen
                Section {
                    Toggle("Lock Screen widget", isOn: .init(
                        get: { GLiveActivityManager.shared.isActive },
                        set: { enabled in
                            if enabled {
                                GLiveActivityManager.shared.start()
                            } else {
                                GLiveActivityManager.shared.stop()
                            }
                        }
                    ))
                } header: {
                    Text("Lock Screen")
                } footer: {
                    Text("Shows G on your Lock Screen with a push-to-talk button. Tap the mic to open G and start talking.")
                }

                // Permissions
                Section("Permissions") {
                    PermissionRow(
                        icon: "person.crop.circle",
                        title: "Contacts",
                        description: "Search and look up contacts"
                    )
                    PermissionRow(
                        icon: "calendar",
                        title: "Calendar",
                        description: "Read and create events"
                    )
                    PermissionRow(
                        icon: "checklist",
                        title: "Reminders",
                        description: "Read and create reminders"
                    )
                    PermissionRow(
                        icon: "mic",
                        title: "Microphone",
                        description: "Voice input"
                    )
                    PermissionRow(
                        icon: "waveform",
                        title: "Speech Recognition",
                        description: "Convert speech to text"
                    )

                    Button("Open System Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .foregroundColor(.gAccent)
                }

                // About
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("0.1.0")
                            .foregroundColor(.gTextDim)
                    }
                    HStack {
                        Text("AI Model")
                        Spacer()
                        Text("Claude Sonnet")
                            .foregroundColor(.gTextDim)
                    }
                }

                // Actions
                Section {
                    Button("Clear Conversation", role: .destructive) {
                        NotificationCenter.default.post(name: .clearConversation, object: nil)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.gAccent)
                }
            }
        }
    }

    private var maskedKey: String {
        let key = settings.claudeAPIKey
        if key.isEmpty { return "Not set" }
        return "••••••••\(key.suffix(8))"
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.gAccent)
                .frame(width: 24)
            VStack(alignment: .leading) {
                Text(title)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.gTextDim)
            }
        }
    }
}

extension Notification.Name {
    static let clearConversation = Notification.Name("clearConversation")
}
