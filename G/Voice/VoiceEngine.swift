import Foundation
import Speech
import AVFoundation

/// G's voice — handles speech recognition (listening) and text-to-speech (speaking).
/// Uses Apple's on-device Speech framework and AVSpeechSynthesizer.
@MainActor
class VoiceEngine: ObservableObject {
    // MARK: - State

    @Published var isListening = false
    @Published var isAuthorized = false
    @Published var currentTranscription = ""

    /// Callback when final speech is recognized
    var onSpeechResult: ((String) -> Void)?

    // MARK: - Speech Recognition

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // MARK: - Text-to-Speech

    private let synthesizer = AVSpeechSynthesizer()

    // MARK: - Setup

    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.isAuthorized = (status == .authorized)
            }
        }
    }

    // MARK: - Listening

    /// Start listening for voice input.
    func startListening() {
        guard !isListening else { return }
        guard speechRecognizer?.isAvailable == true else { return }

        // Stop any current speech output
        synthesizer.stopSpeaking(at: .immediate)

        do {
            // Configure audio session
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let request = recognitionRequest else { return }
            request.shouldReportPartialResults = true

            // Use on-device recognition when available (faster, private)
            if #available(iOS 13, *) {
                request.requiresOnDeviceRecognition = speechRecognizer?.supportsOnDeviceRecognition ?? false
            }

            recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
                guard let self = self else { return }

                if let result = result {
                    let text = result.bestTranscription.formattedString
                    Task { @MainActor in
                        self.currentTranscription = text

                        if result.isFinal {
                            self.stopListening()
                            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                                self.onSpeechResult?(text)
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

            // Connect audio input
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                self.recognitionRequest?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            isListening = true
            currentTranscription = ""

        } catch {
            print("Failed to start listening: \(error)")
        }
    }

    /// Stop listening.
    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
    }

    // MARK: - Speaking

    /// Speak text aloud.
    func speak(_ text: String) {
        guard Settings.shared.voiceResponseEnabled else { return }

        // Configure audio for playback
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .default)
        try? audioSession.setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.52  // slightly faster than default
        utterance.pitchMultiplier = 0.95  // slightly lower for assistant feel
        utterance.volume = 1.0

        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }

    /// Stop speaking.
    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    var isSpeaking: Bool {
        synthesizer.isSpeaking
    }
}
