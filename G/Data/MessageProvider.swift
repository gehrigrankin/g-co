import Foundation
import MessageUI

/// Reads SMS/iMessage conversations.
///
/// iOS Limitation: Apple doesn't provide a public API to directly read the Messages database.
/// On a real device, this requires either:
/// 1. A Messages extension that the user interacts with
/// 2. Reading from a synced backup/CloudKit
/// 3. The user forwarding messages via Shortcuts automation
///
/// For the MVP, we use a notification-forwarding approach + Shortcuts integration,
/// and provide the ability to COMPOSE messages via MFMessageComposeViewController.
///
/// When running on a real device with full access (enterprise/MDM or jailbreak),
/// the SQLite database at ~/Library/SMS/sms.db can be queried directly.
class MessageProvider {

    /// Read recent messages. On iOS, this returns messages forwarded to G via Shortcuts,
    /// plus any messages G has been notified about.
    func readMessages(contact: String?, limit: Int) async throws -> String {
        // Check if we have cached/forwarded messages
        let messages = MessageStore.shared.recentMessages

        if messages.isEmpty {
            return """
            I don't have direct access to your Messages app (Apple doesn't allow this).

            To let me read your messages, set up this Shortcut:
            1. Open Shortcuts app
            2. Create an Automation: "When I receive a message"
            3. Action: "Run Shortcut" → "Forward to G"

            Alternatively, I can help you compose and send a message — just ask!
            """
        }

        var filtered = messages
        if let contact = contact {
            filtered = messages.filter {
                $0.sender.localizedCaseInsensitiveContains(contact)
            }
        }

        let limited = Array(filtered.prefix(limit))

        if limited.isEmpty {
            return contact != nil
                ? "No recent messages from \(contact!)."
                : "No recent messages."
        }

        return limited.enumerated().map { i, msg in
            "[\(i+1)] \(msg.sender) (\(msg.timeAgo)): \(msg.text)"
        }.joined(separator: "\n")
    }
}

// MARK: - Message Store (receives forwarded messages)

class MessageStore: ObservableObject {
    static let shared = MessageStore()

    struct StoredMessage: Identifiable {
        let id = UUID()
        let sender: String
        let text: String
        let timestamp: Date

        var timeAgo: String {
            let interval = Date().timeIntervalSince(timestamp)
            if interval < 60 { return "just now" }
            if interval < 3600 { return "\(Int(interval / 60))m ago" }
            if interval < 86400 { return "\(Int(interval / 3600))h ago" }
            return "\(Int(interval / 86400))d ago"
        }
    }

    @Published var recentMessages: [StoredMessage] = []

    /// Called when a message is forwarded to G via Shortcuts or notification
    func addMessage(sender: String, text: String) {
        let msg = StoredMessage(sender: sender, text: text, timestamp: Date())
        recentMessages.insert(msg, at: 0)

        // Keep last 200
        if recentMessages.count > 200 {
            recentMessages = Array(recentMessages.prefix(200))
        }
    }
}
