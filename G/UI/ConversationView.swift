import SwiftUI

/// The main conversation view — chat bubbles, input field, voice button.
struct ConversationView: View {
    @EnvironmentObject var assistant: GAssistant
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(assistant.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        // Typing indicator
                        if assistant.isProcessing {
                            TypingIndicator(action: assistant.currentAction)
                                .id("typing")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: assistant.messages.count) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        if assistant.isProcessing {
                            proxy.scrollTo("typing", anchor: .bottom)
                        } else if let last = assistant.messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider().background(Color.gSurface)

            // Input bar
            HStack(spacing: 8) {
                // Voice button
                VoiceButton()

                // Text input
                TextField("Ask G anything...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.gSurface)
                    .cornerRadius(20)
                    .foregroundColor(.white)
                    .focused($inputFocused)
                    .onSubmit { sendMessage() }

                // Send button
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(inputText.isEmpty ? .gTextDim : .gAccent)
                }
                .disabled(inputText.isEmpty || assistant.isProcessing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gPrimaryDark)
        }
        .background(Color.gPrimary)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        inputFocused = false

        Task {
            await assistant.send(text)
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ConversationMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.role == .user ? "You" : "G")
                    .font(.caption.bold())
                    .foregroundColor(.gAccent)

                Text(message.text)
                    .foregroundColor(.white)
                    .font(.body)

                if let action = message.action {
                    Text(action)
                        .font(.caption)
                        .foregroundColor(.gTextDim)
                        .italic()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(message.role == .user ? Color.gUserBubble : Color.gAssistantBubble)
            .cornerRadius(16)

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    let action: String?
    @State private var dotCount = 0

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("G")
                    .font(.caption.bold())
                    .foregroundColor(.gAccent)

                HStack(spacing: 4) {
                    if let action = action {
                        Text(action)
                            .font(.body)
                            .foregroundColor(.gTextDim)
                            .italic()
                    }

                    HStack(spacing: 3) {
                        ForEach(0..<3) { i in
                            Circle()
                                .fill(Color.gAccent.opacity(dotCount == i ? 1.0 : 0.3))
                                .frame(width: 6, height: 6)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.gAssistantBubble)
            .cornerRadius(16)

            Spacer(minLength: 60)
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                dotCount = (dotCount + 1) % 3
            }
        }
    }
}

// MARK: - Voice Button

struct VoiceButton: View {
    @EnvironmentObject var assistant: GAssistant

    var body: some View {
        Button {
            if assistant.voiceEngine.isListening {
                assistant.voiceEngine.stopListening()
            } else {
                assistant.voiceEngine.startListening()
            }
        } label: {
            Image(systemName: assistant.voiceEngine.isListening ? "mic.fill" : "mic")
                .font(.title3)
                .foregroundColor(assistant.voiceEngine.isListening ? .red : .gAccent)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(assistant.voiceEngine.isListening ? Color.red.opacity(0.2) : Color.clear)
                )
        }
        .animation(.easeInOut(duration: 0.2), value: assistant.voiceEngine.isListening)
    }
}
