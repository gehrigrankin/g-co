import SwiftUI

@main
struct GApp: App {
    @StateObject private var assistant = GAssistant()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(assistant)
                .preferredColorScheme(.dark)
        }
    }
}
