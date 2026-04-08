import Foundation
import EventKit

/// Reads and creates reminders.
/// Uses EventKit — full read/write access with user permission.
class ReminderProvider {
    private let store = EKEventStore()

    /// Request reminders access.
    func requestAccess() async -> Bool {
        do {
            if #available(iOS 17.0, *) {
                return try await store.requestFullAccessToReminders()
            } else {
                return try await store.requestAccess(to: .reminder)
            }
        } catch {
            return false
        }
    }

    /// Read reminders, optionally filtered by list.
    func readReminders(list: String?, includeCompleted: Bool) async throws -> String {
        let granted = await requestAccess()
        guard granted else {
            return "I don't have permission to access your reminders. Grant access in Settings → G → Reminders."
        }

        // Get calendars (reminder lists)
        var calendars = store.calendars(for: .reminder)
        if let list = list {
            calendars = calendars.filter {
                $0.title.localizedCaseInsensitiveContains(list)
            }
            if calendars.isEmpty {
                let allLists = store.calendars(for: .reminder).map { $0.title }.joined(separator: ", ")
                return "No reminder list matching '\(list)'. Available lists: \(allLists)"
            }
        }

        let predicate = store.predicateForReminders(in: calendars.isEmpty ? nil : calendars)

        let reminders = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[EKReminder], Error>) in
            store.fetchReminders(matching: predicate) { result in
                cont.resume(returning: result ?? [])
            }
        }

        var filtered = reminders
        if !includeCompleted {
            filtered = reminders.filter { !$0.isCompleted }
        }

        if filtered.isEmpty {
            return includeCompleted
                ? "No reminders found."
                : "No pending reminders. You're all caught up!"
        }

        // Group by list
        var byList: [String: [EKReminder]] = [:]
        for reminder in filtered {
            let listName = reminder.calendar?.title ?? "Other"
            byList[listName, default: []].append(reminder)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"

        return byList.map { listName, items in
            let itemLines = items.prefix(20).map { reminder in
                let check = reminder.isCompleted ? "[x]" : "[ ]"
                let due = reminder.dueDateComponents.flatMap {
                    Calendar.current.date(from: $0)
                }.map { " (due \(dateFormatter.string(from: $0)))" } ?? ""
                return "  \(check) \(reminder.title ?? "Untitled")\(due)"
            }.joined(separator: "\n")
            return "\(listName):\n\(itemLines)"
        }.joined(separator: "\n\n")
    }

    /// Create a new reminder.
    func createReminder(title: String, dueDate: String?, notes: String?) async throws -> String {
        let granted = await requestAccess()
        guard granted else {
            return "I don't have permission to create reminders."
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = store.defaultCalendarForNewReminders()
        reminder.notes = notes

        if let dueDate = dueDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: dueDate) {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day], from: date
                )
            }
        }

        do {
            try store.save(reminder, commit: true)
            let dueStr = dueDate.map { " (due \($0))" } ?? ""
            return "Created reminder: \(title)\(dueStr)"
        } catch {
            return "Failed to create reminder: \(error.localizedDescription)"
        }
    }
}
