import Foundation
import Speech
import AVFoundation

/// G's voice — handles wake word detection, speech recognition, and text-to-speech.
///
/// Two listening modes:
/// 1. **Passive** — always-on (while app is open), continuously listens for "hey g" or "g,"
///    using on-device recognition. Low overhead, no network. When wake word is detected,
///    transitions to active mode.
/// 2. **Active** — captures the full command after wake word trigger (or manual mic tap).
///    Sends the transcription (minus the wake word) to the assistant.
@MainActor
class VoiceEngine: ObservableObject {
    // MARK: - Published State

    @Published var listeningMode: ListeningMode = .off
    @Published var isAuthorized = false
    @Published var currentTranscription = ""

    enum ListeningMode: Equatable {
        case off                // not listening at all
        case passive            // always-on, waiting for "hey g"
        case active             // wake word detected or manual trigger, capturing command
        case processing         // command captured, being processed
    }

    /// Callback when a full command is recognized (wake word stripped)
    var onSpeechResult: ((String) -> Void)?

    // MARK: - Speech Recognition

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // MARK: - Text-to-Speech

    private let synthesizer = AVSpeechSynthesizer()

    // MARK: - Wake Word Config

    /// Phrases that activate G. Matched case-insensitively against the start of transcription.
    private let wakePhrases = ["hey g", "hey g,", "hey g.", "hey ji", "heyg", "a g,", "a g"]
    /// Single "g" at the start followed by a comma or clear pause
    private let shortWakePhrases = ["g,", "g.", "gee,", "gee."]

    /// How long to wait for speech after wake word before giving up (seconds)
    private let activeTimeoutSeconds: TimeInterval = 8.0
    private var activeTimeoutTask: Task<Void, Never>?

    /// Track whether we already fired for this recognition session
    private var hasFiredResult = false

    /// Track the last partial transcription to detect wake word mid-stream
    private var lastPartialText = ""

    // MARK: - Audio feedback

    private var activationSoundID: SystemSoundID = 0

    // MARK: - Setup

    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.isAuthorized = (status == .authorized)
            }
        }
    }

    // ========================================================================
    // MARK: - Passive Listening (Wake Word Detection)
    // ========================================================================

    /// Start always-on passive listening for the wake word.
    /// Call this when the app becomes active / user enables the feature.
    func startPassiveListening() {
        guard listeningMode == .off || listeningMode == .processing else { return }
        guard speechRecognizer?.isAvailable == true else { return }
        guard isAuthorized else { return }

        // Clean up any previous session
        tearDownAudioSession()

        do {
            let audioSession = AVAudioSession.sharedInstance()
            // Use playAndRecord so we can also speak responses without switching categories
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let request = recognitionRequest else { return }
            request.shouldReportPartialResults = true
            // On-device for privacy and speed — wake word detection doesn't need the cloud
            request.requiresOnDeviceRecognition = speechRecognizer?.supportsOnDeviceRecognition ?? false

            hasFiredResult = false
            lastPartialText = ""

            recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
                guard let self = self else { return }

                if let result = result {
                    let text = result.bestTranscription.formattedString
                    Task { @MainActor in
                        self.handlePassiveTranscription(text, isFinal: result.isFinal)
                    }
                }

                if error != nil {
                    Task { @MainActor in
                        // Speech recognizer timed out or errored — restart passive listening
                        self.restartPassiveListening()
                    }
                }
            }

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                self.recognitionRequest?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            listeningMode = .passive
            currentTranscription = ""

        } catch {
            print("[VoiceEngine] Failed to start passive listening: \(error)")
        }
    }

    /// Handles partial transcriptions during passive mode, looking for wake words.
    private func handlePassiveTranscription(_ text: String, isFinal: Bool) {
        guard listeningMode == .passive else { return }
        guard !hasFiredResult else { return }

        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)

        // Check if the transcription starts with a wake phrase
        if let command = extractCommandAfterWakeWord(lower) {
            if !command.isEmpty {
                // Wake word + command in one go (e.g., "Hey G, what's on my calendar?")
                // Wait a beat to see if more words come, or fire if final
                currentTranscription = command
                if isFinal || command.split(separator: " ").count >= 3 {
                    fireWakeWordActivation(withCommand: command)
                } else {
                    // Transition to active mode to capture the rest
                    transitionToActive(initialCommand: command)
                }
            } else if isFinal {
                // Just "Hey G" with nothing after — transition to active listening
                transitionToActive(initialCommand: nil)
            } else {
                // "Hey G" detected in partial — wait for more
                transitionToActive(initialCommand: nil)
            }
        }

        lastPartialText = lower

        // iOS speech recognition times out after ~60s of continuous listening.
        // If it finalizes without a wake word, restart.
        if isFinal && !hasFiredResult {
            restartPassiveListening()
        }
    }

    /// Extract the user's command from text that starts with a wake phrase.
    /// Returns nil if no wake phrase found, empty string if wake phrase but no command yet.
    private func extractCommandAfterWakeWord(_ text: String) -> String? {
        // Check long phrases first ("hey g")
        for phrase in wakePhrases {
            if text.hasPrefix(phrase) {
                let remainder = String(text.dropFirst(phrase.count))
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ",."))
                    .trimmingCharacters(in: .whitespaces)
                return remainder
            }
        }
        // Check short phrases ("g,")
        for phrase in shortWakePhrases {
            if text.hasPrefix(phrase) {
                let remainder = String(text.dropFirst(phrase.count))
                    .trimmingCharacters(in: .whitespaces)
                return remainder
            }
        }
        return nil
    }

    /// Transition from passive → active after wake word detected.
    private func transitionToActive(initialCommand: String?) {
        guard !hasFiredResult else { return }

        listeningMode = .active
        currentTranscription = initialCommand ?? ""

        // Haptic + sound feedback so user knows G is listening
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // Timeout: if no speech comes within N seconds, go back to passive
        activeTimeoutTask?.cancel()
        activeTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(activeTimeoutSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if self.listeningMode == .active {
                // If we have some text, fire it. Otherwise, go back to passive.
                let cmd = self.currentTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cmd.isEmpty {
                    self.fireWakeWordActivation(withCommand: cmd)
                } else {
                    self.restartPassiveListening()
                }
            }
        }

        // Now continue the same recognition session — subsequent partials
        // go through handleActiveTranscription
    }

    // ========================================================================
    // MARK: - Active Listening (Capturing Command)
    // ========================================================================

    /// Start active listening (manual trigger — user tapped mic button).
    func startActiveListening() {
        guard listeningMode != .active else { return }
        guard speechRecognizer?.isAvailable == true else { return }

        // If we're in passive mode, we need to tear down and restart in active mode
        tearDownAudioSession()

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let request = recognitionRequest else { return }
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = speechRecognizer?.supportsOnDeviceRecognition ?? false

            hasFiredResult = false

            recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
                guard let self = self else { return }

                if let result = result {
                    let text = result.bestTranscription.formattedString
                    Task { @MainActor in
                        // In manual active mode, strip any wake word if present
                        let cleaned = self.stripWakeWord(text)
                        self.currentTranscription = cleaned

                        if result.isFinal {
                            self.stopListening()
                            let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty && !self.hasFiredResult {
                                self.hasFiredResult = true
                                self.onSpeechResult?(trimmed)
                            }
                        }
                    }
                }

                if error != nil {
                    Task { @MainActor in
                        self.stopListening()
                    }
                }
            }

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                self.recognitionRequest?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            listeningMode = .active
            currentTranscription = ""

            // Haptic
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            // Timeout
            activeTimeoutTask?.cancel()
            activeTimeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(activeTimeoutSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                if self.listeningMode == .active {
                    let cmd = self.currentTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cmd.isEmpty && !self.hasFiredResult {
                        self.hasFiredResult = true
                        self.stopListening()
                        self.onSpeechResult?(cmd)
                    } else {
                        self.stopListening()
                    }
                }
            }

        } catch {
            print("[VoiceEngine] Failed to start active listening: \(error)")
        }
    }

    /// Fire the command from a wake-word-triggered session.
    private func fireWakeWordActivation(withCommand command: String) {
        guard !hasFiredResult else { return }
        hasFiredResult = true

        activeTimeoutTask?.cancel()
        listeningMode = .processing

        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onSpeechResult?(trimmed)
        }

        // Restart passive listening after a delay (let the response come first)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            // Only restart if we're still in processing and wake word is enabled
            if Settings.shared.wakeWordEnabled {
                self.startPassiveListening()
            } else {
                self.listeningMode = .off
            }
        }
    }

    /// Strip wake word from the beginning of text (for manual mic tap where user says "g, ..." out of habit)
    private func stripWakeWord(_ text: String) -> String {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        for phrase in (wakePhrases + shortWakePhrases) {
            if lower.hasPrefix(phrase) {
                return String(text.dropFirst(phrase.count))
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ",."))
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return text
    }

    // ========================================================================
    // MARK: - Stop / Restart
    // ========================================================================

    /// Stop all listening.
    func stopListening() {
        activeTimeoutTask?.cancel()
        tearDownAudioSession()
        listeningMode = .off
        currentTranscription = ""
    }

    /// Restart passive listening (after timeout, error, or wake word session ends).
    private func restartPassiveListening() {
        tearDownAudioSession()
        listeningMode = .off

        // Brief pause before restarting to avoid audio session conflicts
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            if Settings.shared.wakeWordEnabled && self.listeningMode == .off {
                self.startPassiveListening()
            }
        }
    }

    private func tearDownAudioSession() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    // ========================================================================
    // MARK: - Speaking (Text-to-Speech)
    // ========================================================================

    /// Speak text aloud.
    func speak(_ text: String) {
        guard Settings.shared.voiceResponseEnabled else { return }

        // If passively listening, pause it while speaking
        let wasPassive = listeningMode == .passive
        if wasPassive {
            tearDownAudioSession()
            listeningMode = .off
        }

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try? audioSession.setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.52
        utterance.pitchMultiplier = 0.95
        utterance.volume = 1.0

        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)

        // Resume passive listening after speech finishes
        if wasPassive || Settings.shared.wakeWordEnabled {
            Task { @MainActor in
                // Wait for speech to finish (rough estimate: ~80ms per character)
                let estimatedDuration = Double(text.count) * 0.06
                try? await Task.sleep(nanoseconds: UInt64(max(estimatedDuration, 1.0) * 1_000_000_000))
                if Settings.shared.wakeWordEnabled && self.listeningMode == .off {
                    self.startPassiveListening()
                }
            }
        }
    }

    /// Stop speaking.
    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    var isSpeaking: Bool {
        synthesizer.isSpeaking
    }

    /// Convenience: whether G is listening in any mode
    var isListening: Bool {
        listeningMode == .passive || listeningMode == .active
    }

    /// Whether wake word detection is actively running
    var isPassivelyListening: Bool {
        listeningMode == .passive
    }
}
