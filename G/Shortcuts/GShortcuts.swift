import AppIntents

// MARK: - "Ask G" Shortcut

/// Lets users trigger G from Siri or Shortcuts.
/// "Hey Siri, ask G if I have anything on my calendar today"
struct AskGIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask G"
    static var description = IntentDescription("Ask G a question or tell it to do something.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Question")
    var question: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let brain = GBrain()
        let response = try await brain.processRequest(question)
        return .result(dialog: IntentDialog(stringLiteral: response))
    }
}

// MARK: - "Forward Message to G" Shortcut

/// Users add this as a Shortcuts automation:
/// Trigger: "When I receive a message"
/// Action: "Forward to G"
///
/// This is how G gets access to incoming messages on iOS.
struct ForwardMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "Forward Message to G"
    static var description = IntentDescription("Forward a message to G so it can track your conversations.")

    @Parameter(title: "Sender Name")
    var sender: String

    @Parameter(title: "Message Text")
    var messageText: String

    func perform() async throws -> some IntentResult {
        MessageStore.shared.addMessage(sender: sender, text: messageText)
        return .result()
    }
}

// MARK: - "Forward Email to G" Shortcut

struct ForwardEmailIntent: AppIntent {
    static var title: LocalizedStringResource = "Forward Email to G"
    static var description = IntentDescription("Forward an email summary to G.")

    @Parameter(title: "Sender")
    var sender: String

    @Parameter(title: "Subject")
    var subject: String

    @Parameter(title: "Preview")
    var preview: String

    func perform() async throws -> some IntentResult {
        EmailStore.shared.addEmail(sender: sender, subject: subject, preview: preview)
        return .result()
    }
}

// MARK: - Shortcuts Provider

/// Registers all of G's shortcuts so they appear in the Shortcuts app.
struct GShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskGIntent(),
            phrases: [
                "Ask \(.applicationName) \(\.$question)",
                "Hey \(.applicationName), \(\.$question)",
                "Tell \(.applicationName) \(\.$question)"
            ],
            shortTitle: "Ask G",
            systemImageName: "bubble.left.and.bubble.right"
        )
    }
}
