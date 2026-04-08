import SwiftUI

@main
struct GApp: App {
    @StateObject private var assistant = GAssistant()
    @StateObject private var liveActivityManager = GLiveActivityManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(assistant)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onAppear {
                    // Start the Lock Screen Live Activity
                    liveActivityManager.start()
                }
        }
    }

    /// Handle deep links from the Live Activity's push-to-talk button.
    /// URL: g-assistant://talk
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "g-assistant" else { return }

        switch url.host {
        case "talk":
            // Start active listening immediately
            assistant.voiceEngine.startActiveListening()
            liveActivityManager.update(status: .listening, isListening: true)
        default:
            break
        }
    }
}
