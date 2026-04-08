import Foundation

/// HTTP client for the Claude API. Uses URLSession — no third-party deps needed.
actor ClaudeClient {
    private let session = URLSession.shared
    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiVersion = "2023-06-01"

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    /// Send a message to Claude with optional tool definitions and get a response.
    func send(
        system: String,
        messages: [ClaudeMessage],
        tools: [ClaudeTool]? = nil
    ) async throws -> ClaudeResponse {
        let apiKey = Settings.shared.claudeAPIKey
        guard !apiKey.isEmpty else {
            throw GError.noAPIKey
        }

        let request = ClaudeRequest(
            system: system,
            messages: messages,
            tools: tools
        )

        var httpRequest = URLRequest(url: apiURL)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        httpRequest.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        httpRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        httpRequest.timeoutInterval = 60

        httpRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await session.data(for: httpRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GError.apiError(httpResponse.statusCode, body)
        }

        return try decoder.decode(ClaudeResponse.self, from: data)
    }
}

// MARK: - Errors

enum GError: LocalizedError {
    case noAPIKey
    case networkError(String)
    case apiError(Int, String)
    case toolExecutionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key set. Add your Claude API key in Settings."
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .apiError(let code, let body):
            return "Claude API error \(code): \(body.prefix(200))"
        case .toolExecutionFailed(let msg):
            return "Tool failed: \(msg)"
        }
    }
}

// MARK: - Settings

class Settings: ObservableObject {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    @Published var claudeAPIKey: String {
        didSet { defaults.set(claudeAPIKey, forKey: "claude_api_key") }
    }

    @Published var voiceResponseEnabled: Bool {
        didSet { defaults.set(voiceResponseEnabled, forKey: "voice_response") }
    }

    @Published var hapticFeedbackEnabled: Bool {
        didSet { defaults.set(hapticFeedbackEnabled, forKey: "haptic_feedback") }
    }

    private init() {
        self.claudeAPIKey = defaults.string(forKey: "claude_api_key") ?? ""
        self.voiceResponseEnabled = defaults.bool(forKey: "voice_response")
        self.hapticFeedbackEnabled = defaults.object(forKey: "haptic_feedback") as? Bool ?? true

        // Check if voice_response was never set (default to true)
        if defaults.object(forKey: "voice_response") == nil {
            self.voiceResponseEnabled = true
        }
    }
}
