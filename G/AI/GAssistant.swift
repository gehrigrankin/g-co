import Foundation
import SwiftUI
import Combine

/// The main coordinator that ties everything together.
/// Owns the brain, voice engine, and conversation state.
/// This is what the UI binds to.
@MainActor
class GAssistant: ObservableObject {
    // MARK: - Published State

    @Published var messages: [ConversationMessage] = []
    @Published var isProcessing = false
    @Published var currentAction: String?  // "Checking your calendar..."

    // MARK: - Components

    let voiceEngine = VoiceEngine()
    private let brain = GBrain()

    init() {
        // Greeting
        messages.append(ConversationMessage(
            role: .assistant,
            text: "Hey, I'm G. What do you need?"
        ))

        // Wire up voice input
        voiceEngine.onSpeechResult = { [weak self] text in
            Task { @MainActor in
                await self?.send(text)
            }
        }

        // Request speech authorization
        voiceEngine.requestAuthorization()
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

        // Haptic feedback
        if Settings.shared.hapticFeedbackEnabled {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }

        do {
            let response = try await brain.processRequest(trimmed)

            let assistantMessage = ConversationMessage(role: .assistant, text: response)
            messages.append(assistantMessage)

            // Speak the response
            voiceEngine.speak(response)

        } catch {
            let errorMessage = ConversationMessage(
                role: .assistant,
                text: "Something went wrong — \(error.localizedDescription)"
            )
            messages.append(errorMessage)
        }

        isProcessing = false
        currentAction = nil
    }

    /// Clear conversation history.
    func clearConversation() async {
        messages = [ConversationMessage(role: .assistant, text: "Fresh start. What do you need?")]
        await brain.clearHistory()
    }
}
