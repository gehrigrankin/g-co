import Foundation

/// Reads emails.
///
/// iOS Limitation: Apple doesn't provide a public API to read the Mail app's inbox.
/// This provider supports two approaches:
///
/// 1. **Gmail API** (OAuth) — if the user connects their Gmail account
/// 2. **Forwarded summaries** — the user sets up a Shortcut to forward email summaries
///
/// For the MVP, this returns instructions on how to set up email access.
/// The Gmail OAuth flow can be added as a follow-up feature.
class EmailProvider {

    func readEmails(limit: Int, unreadOnly: Bool) async throws -> String {
        let cached = EmailStore.shared.recentEmails

        if cached.isEmpty {
            return """
            I can't directly read the Mail app (Apple doesn't allow this).

            Options to give me email access:
            1. **Gmail**: Go to Settings in G and connect your Gmail account
            2. **Shortcuts**: Set up a Shortcut automation to forward email summaries to G

            I can also open the Mail app for you — just ask!
            """
        }

        var emails = cached
        if unreadOnly {
            emails = emails.filter { !$0.isRead }
        }

        let limited = Array(emails.prefix(limit))

        if limited.isEmpty {
            return unreadOnly ? "No unread emails." : "No emails found."
        }

        return limited.enumerated().map { i, email in
            let readIndicator = email.isRead ? "" : " [UNREAD]"
            return "[\(i+1)]\(readIndicator) From: \(email.sender)\n  Subject: \(email.subject)\n  \(email.preview)"
        }.joined(separator: "\n\n")
    }
}

// MARK: - Email Store (receives forwarded/fetched emails)

class EmailStore: ObservableObject {
    static let shared = EmailStore()

    struct StoredEmail: Identifiable {
        let id = UUID()
        let sender: String
        let subject: String
        let preview: String
        let timestamp: Date
        var isRead: Bool
    }

    @Published var recentEmails: [StoredEmail] = []

    func addEmail(sender: String, subject: String, preview: String) {
        let email = StoredEmail(
            sender: sender, subject: subject, preview: preview,
            timestamp: Date(), isRead: false
        )
        recentEmails.insert(email, at: 0)
        if recentEmails.count > 100 {
            recentEmails = Array(recentEmails.prefix(100))
        }
    }
}
