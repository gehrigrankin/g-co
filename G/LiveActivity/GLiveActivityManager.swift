import ActivityKit
import Foundation

/// Manages G's Live Activity on the Lock Screen and Dynamic Island.
/// Start the activity when the app launches, update it as G's state changes,
/// and the user can tap the mic button to open the app and start talking.
@MainActor
class GLiveActivityManager: ObservableObject {
    static let shared = GLiveActivityManager()

    private var currentActivity: Activity<GActivityAttributes>?

    @Published var isActive = false

    /// Start the Live Activity (call on app launch or when user enables it).
    func start() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[LiveActivity] Activities not enabled")
            return
        }

        // End any existing activity
        Task {
            for activity in Activity<GActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        let initialState = GActivityAttributes.ContentState(
            status: .ready,
            lastResponse: nil,
            isListening: false
        )

        let content = ActivityContent(state: initialState, staleDate: nil)

        do {
            currentActivity = try Activity.request(
                attributes: GActivityAttributes(),
                content: content,
                pushType: nil
            )
            isActive = true
            print("[LiveActivity] Started")
        } catch {
            print("[LiveActivity] Failed to start: \(error)")
        }
    }

    /// Update the Live Activity state.
    func update(
        status: GActivityAttributes.ContentState.GStatus,
        lastResponse: String? = nil,
        isListening: Bool = false
    ) {
        guard let activity = currentActivity else { return }

        let state = GActivityAttributes.ContentState(
            status: status,
            lastResponse: lastResponse,
            isListening: isListening
        )

        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    /// End the Live Activity.
    func stop() {
        guard let activity = currentActivity else { return }

        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
            currentActivity = nil
            isActive = false
        }
    }
}
