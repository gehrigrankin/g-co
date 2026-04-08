import Foundation

/// Persists conversation history across app sessions.
/// Stores messages as JSON in the app's documents directory.
/// Keeps the last N conversations so the app doesn't bloat over time.
class ConversationStore {
    static let shared = ConversationStore()

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = .prettyPrinted
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private let maxSessions = 50
    private let maxMessagesPerSession = 200

    // MARK: - Data Types

    struct StoredConversation: Codable, Identifiable {
        let id: UUID
        let startedAt: Date
        var lastMessageAt: Date
        var messages: [StoredMessage]
        var messageCount: Int { messages.count }

        init() {
            self.id = UUID()
            self.startedAt = Date()
            self.lastMessageAt = Date()
            self.messages = []
        }
    }

    struct StoredMessage: Codable, Identifiable {
        let id: UUID
        let role: String  // "user" or "assistant"
        let text: String
        let action: String?
        let timestamp: Date

        init(from message: ConversationMessage) {
            self.id = message.id
            self.role = message.role == .user ? "user" : "assistant"
            self.text = message.text
            self.action = message.action
            self.timestamp = message.timestamp
        }

        func toConversationMessage() -> ConversationMessage {
            ConversationMessage(
                role: role == "user" ? .user : .assistant,
                text: text,
                action: action
            )
        }
    }

    // MARK: - Current Session

    private var currentSession: StoredConversation?
    private var allSessions: [StoredConversation] = []

    private init() {
        loadSessions()
    }

    /// Start a new conversation session (called on app launch).
    func startNewSession() -> [ConversationMessage] {
        // If the last session was recent (< 30 min ago) and has messages, continue it
        if let last = allSessions.first,
           Date().timeIntervalSince(last.lastMessageAt) < 1800,
           !last.messages.isEmpty {
            currentSession = last
            return last.messages.map { $0.toConversationMessage() }
        }

        // Otherwise start fresh
        let session = StoredConversation()
        currentSession = session
        return []
    }

    /// Add a message to the current session.
    func addMessage(_ message: ConversationMessage) {
        guard var session = currentSession else { return }

        let stored = StoredMessage(from: message)
        session.messages.append(stored)
        session.lastMessageAt = Date()

        // Trim if too many messages
        if session.messages.count > maxMessagesPerSession {
            session.messages = Array(session.messages.suffix(maxMessagesPerSession))
        }

        currentSession = session

        // Update in all sessions
        if let index = allSessions.firstIndex(where: { $0.id == session.id }) {
            allSessions[index] = session
        } else {
            allSessions.insert(session, at: 0)
        }

        save()
    }

    /// Get recent conversation context for the AI (last N messages from previous sessions).
    /// This gives G continuity even across separate sessions.
    func getRecentContext(maxMessages: Int = 20) -> String {
        var contextMessages: [StoredMessage] = []

        // Get messages from recent sessions (skip current)
        for session in allSessions {
            if session.id == currentSession?.id { continue }
            contextMessages.append(contentsOf: session.messages)
            if contextMessages.count >= maxMessages { break }
        }

        if contextMessages.isEmpty { return "" }

        let lines = contextMessages.suffix(maxMessages).map { msg in
            let role = msg.role == "user" ? "Gehrig" : "G"
            return "\(role): \(msg.text)"
        }

        return "RECENT CONVERSATION HISTORY:\n" + lines.joined(separator: "\n")
    }

    /// Clear the current session (user tapped "Clear Conversation").
    func clearCurrentSession() {
        currentSession = StoredConversation()
        save()
    }

    /// All stored sessions for browsing.
    var sessions: [StoredConversation] { allSessions }

    // MARK: - Persistence

    private var storageURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("g_conversations.json")
    }

    private func save() {
        if let data = try? encoder.encode(allSessions) {
            try? data.write(to: storageURL)
        }
    }

    private func loadSessions() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? decoder.decode([StoredConversation].self, from: data) else {
            return
        }
        // Keep only recent sessions
        allSessions = Array(decoded.prefix(maxSessions))
    }
}
