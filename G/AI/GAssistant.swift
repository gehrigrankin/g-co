import Foundation
import SwiftUI
import Combine

/// The main coordinator that ties everything together.
/// Owns the brain, voice engine, and conversation state.
/// Persists conversations across sessions and updates the Live Activity.
@MainActor
class GAssistant: ObservableObject {
    // MARK: - Published State

    @Published var messages: [ConversationMessage] = []
    @Published var isProcessing = false
    @Published var currentAction: String?

    // MARK: - Components

    let voiceEngine = VoiceEngine()
    private let brain = GBrain()
    private let liveActivity = GLiveActivityManager.shared
    private let conversationStore = ConversationStore.shared

    init() {
        // Restore previous conversation or start fresh
        let restored = conversationStore.startNewSession()
        if restored.isEmpty {
            // First launch or new session — G greets based on what it knows
            let memory = GMemory.shared
            let greeting: String
            if memory.memories.isEmpty {
                greeting = "Hey, I'm G. I'm your assistant — I'll learn about you as we go. What do you need?"
            } else {
                greeting = "Hey Gehrig. What's up?"
            }
            let msg = ConversationMessage(role: .assistant, text: greeting)
            messages.append(msg)
            conversationStore.addMessage(msg)
        } else {
            messages = restored
            // Welcome back message
            let wb = ConversationMessage(role: .assistant, text: "I'm back. Where were we?")
            messages.append(wb)
            conversationStore.addMessage(wb)
        }

        // Wire up voice input
        voiceEngine.onSpeechResult = { [weak self] text in
            Task { @MainActor in
                self?.liveActivity.update(status: .thinking)
                await self?.send(text)
            }
        }

        // Request speech authorization, then start passive listening
        voiceEngine.requestAuthorization()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Settings.shared.wakeWordEnabled && self.voiceEngine.isAuthorized {
                self.voiceEngine.startPassiveListening()
            }
        }
    }

    // MARK: - Send Message

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isProcessing else { return }

        // Add user message
        let userMessage = ConversationMessage(role: .user, text: trimmed)
        messages.append(userMessage)
        conversationStore.addMessage(userMessage)

        isProcessing = true
        currentAction = "Thinking..."
        liveActivity.update(status: .thinking)

        if Settings.shared.hapticFeedbackEnabled {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }

        do {
            let response = try await brain.processRequest(trimmed)

            let assistantMessage = ConversationMessage(role: .assistant, text: response)
            messages.append(assistantMessage)
            conversationStore.addMessage(assistantMessage)

            let preview = String(response.prefix(100))
            liveActivity.update(status: .speaking, lastResponse: preview)

            voiceEngine.speak(response)

        } catch {
            let errorMessage = ConversationMessage(
                role: .assistant,
                text: "Something went wrong — \(error.localizedDescription)"
            )
            messages.append(errorMessage)
            conversationStore.addMessage(errorMessage)
            liveActivity.update(status: .ready, lastResponse: "Error occurred")
        }

        isProcessing = false
        currentAction = nil

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
        conversationStore.clearCurrentSession()
        liveActivity.update(status: .ready, lastResponse: nil)
    }
}
