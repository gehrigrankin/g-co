import Foundation
import EventKit

/// Reads and creates calendar events.
/// Uses EventKit — full read/write access with user permission.
class CalendarProvider {
    private let store = EKEventStore()

    /// Request calendar access.
    func requestAccess() async -> Bool {
        do {
            if #available(iOS 17.0, *) {
                return try await store.requestFullAccessToEvents()
            } else {
                return try await store.requestAccess(to: .event)
            }
        } catch {
            return false
        }
    }

    /// Read upcoming calendar events.
    func readEvents(daysAhead: Int, query: String?) async throws -> String {
        let granted = await requestAccess()
        guard granted else {
            return "I don't have permission to access your calendar. Grant access in Settings → G → Calendars."
        }

        let startDate = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: daysAhead, to: startDate)!

        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        var events = store.events(matching: predicate)

        // Filter by query if provided
        if let query = query {
            events = events.filter {
                $0.title?.localizedCaseInsensitiveContains(query) == true
            }
        }

        if events.isEmpty {
            let range = daysAhead == 1 ? "today" : "the next \(daysAhead) days"
            return query != nil
                ? "No events matching '\(query!)' in \(range)."
                : "No events in \(range). Your schedule is clear."
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, MMM d"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"

        // Group by day
        var byDay: [String: [EKEvent]] = [:]
        for event in events {
            let dayKey = dateFormatter.string(from: event.startDate)
            byDay[dayKey, default: []].append(event)
        }

        return byDay.sorted(by: { $0.value[0].startDate < $1.value[0].startDate })
            .map { day, dayEvents in
                let eventLines = dayEvents.map { event in
                    let time = event.isAllDay
                        ? "All day"
                        : "\(timeFormatter.string(from: event.startDate)) - \(timeFormatter.string(from: event.endDate))"
                    let location = event.location.map { " @ \($0)" } ?? ""
                    return "  - \(time): \(event.title ?? "Untitled")\(location)"
                }.joined(separator: "\n")
                return "\(day):\n\(eventLines)"
            }.joined(separator: "\n\n")
    }

    /// Create a new calendar event.
    func createEvent(title: String, date: String, time: String?, durationMinutes: Int) async throws -> String {
        let granted = await requestAccess()
        guard granted else {
            return "I don't have permission to create calendar events."
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        guard let eventDate = dateFormatter.date(from: date) else {
            return "Invalid date format. Use YYYY-MM-DD."
        }

        var startDate = eventDate
        if let time = time {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "yyyy-MM-dd HH:mm"
            if let dateTime = timeFormatter.date(from: "\(date) \(time)") {
                startDate = dateTime
            }
        }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = Calendar.current.date(byAdding: .minute, value: durationMinutes, to: startDate)
        event.calendar = store.defaultCalendarForNewEvents

        do {
            try store.save(event, span: .thisEvent)
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "EEEE, MMM d 'at' h:mm a"
            return "Created event: \(title) on \(displayFormatter.string(from: startDate))"
        } catch {
            return "Failed to create event: \(error.localizedDescription)"
        }
    }
}
