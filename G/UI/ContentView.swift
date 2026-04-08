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
                            StatusDot(isActive: !Settings.shared.claudeAPIKey.isEmpty)
                            Text("G")
                                .font(.title2.bold())
                                .foregroundColor(.white)
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

    var body: some View {
        Circle()
            .fill(isActive ? Color.gStatusActive : Color.gStatusInactive)
            .frame(width: 8, height: 8)
    }
}
