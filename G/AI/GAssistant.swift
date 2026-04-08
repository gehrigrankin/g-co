import Foundation
import SwiftUI
import Combine

/// The main coordinator that ties everything together.
/// Owns the brain, voice engine, and conversation state.
/// Updates the Lock Screen Live Activity as state changes.
@MainActor
class GAssistant: ObservableObject {
    // MARK: - Published State

    @Published var messages: [ConversationMessage] = []
    @Published var isProcessing = false
    @Published var currentAction: String?  // "Checking your calendar..."

    // MARK: - Components

    let voiceEngine = VoiceEngine()
    private let brain = GBrain()
    private let liveActivity = GLiveActivityManager.shared

    init() {
        // Greeting
        messages.append(ConversationMessage(
            role: .assistant,
            text: "Hey, I'm G. What do you need?"
        ))

        // Wire up voice input
        voiceEngine.onSpeechResult = { [weak self] text in
            Task { @MainActor in
                self?.liveActivity.update(status: .thinking)
                await self?.send(text)
            }
        }

        // Request speech authorization, then start passive listening
        voiceEngine.requestAuthorization()

        // Start wake word listening after a brief delay for auth to resolve
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Settings.shared.wakeWordEnabled && self.voiceEngine.isAuthorized {
                self.voiceEngine.startPassiveListening()
            }
        }
    }

    // MARK: - Send Message

    /// Process a user request (from text input or voice).
    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isProcessing else { return }

        // Add user message
        let userMessage = ConversationMessage(role: .user, text: trimmed)
        messages.append(userMessage)

        isProcessing = true
        currentAction = "Thinking..."

        // Update Live Activity
        liveActivity.update(status: .thinking)

        // Haptic feedback
        if Settings.shared.hapticFeedbackEnabled {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }

        do {
            let response = try await brain.processRequest(trimmed)

            let assistantMessage = ConversationMessage(role: .assistant, text: response)
            messages.append(assistantMessage)

            // Update Live Activity with response
            let preview = String(response.prefix(100))
            liveActivity.update(status: .speaking, lastResponse: preview)

            // Speak the response
            voiceEngine.speak(response)

        } catch {
            let errorMessage = ConversationMessage(
                role: .assistant,
                text: "Something went wrong — \(error.localizedDescription)"
            )
            messages.append(errorMessage)
            liveActivity.update(status: .ready, lastResponse: "Error occurred")
        }

        isProcessing = false
        currentAction = nil

        // Resume passive listening and update Live Activity
        if Settings.shared.wakeWordEnabled && !voiceEngine.isListening {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Settings.shared.wakeWordEnabled && self.voiceEngine.listeningMode == .off {
                    self.voiceEngine.startPassiveListening()
                }
                self.liveActivity.update(status: .ready)
            }
        } else {
            liveActivity.update(status: .ready)
        }
    }

    /// Clear conversation history.
    func clearConversation() async {
        messages = [ConversationMessage(role: .assistant, text: "Fresh start. What do you need?")]
        await brain.clearHistory()
        liveActivity.update(status: .ready, lastResponse: nil)
    }
}
