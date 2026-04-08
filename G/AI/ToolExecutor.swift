import Foundation
import UIKit

/// Dispatches tool calls from Claude to the appropriate data provider.
/// This is the bridge between AI decisions and real phone data.
class ToolExecutor {
    private let messages = MessageProvider()
    private let contacts = ContactProvider()
    private let calendar = CalendarProvider()
    private let reminders = ReminderProvider()
    private let email = EmailProvider()

    func execute(tool: String, input: [String: Any]) async -> String {
        do {
            switch tool {
            case "read_messages":
                let contact = input["contact"] as? String
                let limit = input["limit"] as? Int ?? 20
                return try await messages.readMessages(contact: contact, limit: limit)

            case "search_contacts":
                guard let query = input["query"] as? String else {
                    return "Error: missing 'query' parameter"
                }
                return try await contacts.search(query: query)

            case "read_calendar":
                let daysAhead = input["days_ahead"] as? Int ?? 7
                let query = input["query"] as? String
                return try await calendar.readEvents(daysAhead: daysAhead, query: query)

            case "create_calendar_event":
                guard let title = input["title"] as? String,
                      let date = input["date"] as? String else {
                    return "Error: missing required parameters (title, date)"
                }
                let time = input["time"] as? String
                let duration = input["duration_minutes"] as? Int ?? 60
                return try await calendar.createEvent(
                    title: title, date: date, time: time, durationMinutes: duration
                )

            case "read_reminders":
                let list = input["list"] as? String
                let includeCompleted = input["include_completed"] as? Bool ?? false
                return try await reminders.readReminders(list: list, includeCompleted: includeCompleted)

            case "create_reminder":
                guard let title = input["title"] as? String else {
                    return "Error: missing 'title' parameter"
                }
                let dueDate = input["due_date"] as? String
                let notes = input["notes"] as? String
                return try await reminders.createReminder(title: title, dueDate: dueDate, notes: notes)

            case "read_emails":
                let limit = input["limit"] as? Int ?? 10
                let unreadOnly = input["unread_only"] as? Bool ?? false
                return try await email.readEmails(limit: limit, unreadOnly: unreadOnly)

            case "open_app":
                guard let app = input["app"] as? String else {
                    return "Error: missing 'app' parameter"
                }
                return await openApp(app)

            case "web_search":
                guard let query = input["query"] as? String else {
                    return "Error: missing 'query' parameter"
                }
                return await webSearch(query)

            case "get_device_info":
                return getDeviceInfo()

            default:
                return "Unknown tool: \(tool)"
            }
        } catch {
            return "Error executing \(tool): \(error.localizedDescription)"
        }
    }

    // MARK: - App Launching

    private func openApp(_ app: String) async -> String {
        let schemes: [String: String] = [
            "messages": "sms://",
            "mail": "mailto:",
            "safari": "https://www.google.com",
            "maps": "maps://",
            "calendar": "calshow://",
            "photos": "photos-redirect://",
            "settings": "app-settings://",
            "phone": "tel://",
            "notes": "mobilenotes://",
            "reminders": "x-apple-reminderkit://",
            "music": "music://",
            "weather": "weather://"
        ]

        guard let scheme = schemes[app.lowercased()],
              let url = URL(string: scheme) else {
            return "I don't know how to open '\(app)'"
        }

        return await MainActor.run {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return "Opened \(app)"
            } else {
                return "Can't open \(app) — the URL scheme isn't available"
            }
        }
    }

    // MARK: - Web Search

    private func webSearch(_ query: String) async -> String {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://www.google.com/search?q=\(encoded)") else {
            return "Error: could not build search URL"
        }

        return await MainActor.run {
            UIApplication.shared.open(url)
            return "Opened Google search for: \(query)"
        }
    }

    // MARK: - Device Info

    private func getDeviceInfo() -> String {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true

        let batteryLevel = device.batteryLevel >= 0
            ? "\(Int(device.batteryLevel * 100))%"
            : "Unknown"
        let batteryState: String = switch device.batteryState {
        case .charging: "Charging"
        case .full: "Full"
        case .unplugged: "Unplugged"
        default: "Unknown"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d 'at' h:mm a"
        let timeString = formatter.string(from: Date())

        return """
        Device: \(device.name) (\(device.model))
        iOS: \(device.systemVersion)
        Time: \(timeString)
        Battery: \(batteryLevel) (\(batteryState))
        """
    }
}
