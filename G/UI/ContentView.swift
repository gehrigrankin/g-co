import SwiftUI

/// Root view — handles navigation between conversation and settings.
struct ContentView: View {
    @EnvironmentObject var assistant: GAssistant
    @State private var showSettings = false
    @State private var showOnboarding = false

    var body: some View {
        NavigationStack {
            ConversationView()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HStack(spacing: 8) {
                            StatusDot(
                                isActive: !Settings.shared.claudeAPIKey.isEmpty,
                                isListening: assistant.voiceEngine.isPassivelyListening
                            )
                            Text("G")
                                .font(.title2.bold())
                                .foregroundColor(.white)
                            if assistant.voiceEngine.isPassivelyListening {
                                Text("listening")
                                    .font(.caption2)
                                    .foregroundColor(.gAccentDim)
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .foregroundColor(.gAccent)
                        }
                    }
                }
                .toolbarBackground(Color.gPrimaryDark, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear {
            if Settings.shared.claudeAPIKey.isEmpty {
                showOnboarding = true
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
    }
}

// MARK: - Status Dot

struct StatusDot: View {
    let isActive: Bool
    var isListening: Bool = false

    var body: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
            .opacity(isListening ? 0.6 : 1.0)
            .animation(
                isListening
                    ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                    : .default,
                value: isListening
            )
    }

    private var dotColor: Color {
        if isListening { return .gAccent }
        return isActive ? .gStatusActive : .gStatusInactive
    }
}
