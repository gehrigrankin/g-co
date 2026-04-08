import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Live Activity Attributes

/// Defines the data model for G's Lock Screen Live Activity.
/// The Live Activity shows G's status and provides a push-to-talk button.
struct GActivityAttributes: ActivityAttributes {
    /// Static data that doesn't change during the activity's lifetime
    public struct ContentState: Codable, Hashable {
        var status: GStatus
        var lastResponse: String?
        var isListening: Bool

        enum GStatus: String, Codable, Hashable {
            case ready = "Ready"
            case listening = "Listening..."
            case thinking = "Thinking..."
            case speaking = "Speaking..."
        }
    }
}

// MARK: - Live Activity Widget

/// The widget that renders on the Lock Screen and Dynamic Island.
struct GLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GActivityAttributes.self) { context in
            // Lock Screen / notification banner presentation
            lockScreenView(context: context)
        } dynamicIsland: { context in
            // Dynamic Island presentation
            DynamicIsland {
                // Expanded view
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor(context.state.status))
                            .frame(width: 8, height: 8)
                        Text("G")
                            .font(.headline.bold())
                            .foregroundColor(.white)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.status.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if let response = context.state.lastResponse {
                            Text(response)
                                .font(.subheadline)
                                .lineLimit(2)
                                .foregroundColor(.white)
                        }
                        Spacer()
                        // Push-to-talk button via deep link
                        Link(destination: URL(string: "g-assistant://talk")!) {
                            Image(systemName: context.state.isListening ? "mic.fill" : "mic")
                                .font(.title2)
                                .foregroundColor(context.state.isListening ? .red : .cyan)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(context.state.isListening
                                            ? Color.red.opacity(0.2)
                                            : Color.cyan.opacity(0.15))
                                )
                        }
                    }
                }
            } compactLeading: {
                // Compact leading (left pill)
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor(context.state.status))
                        .frame(width: 6, height: 6)
                    Text("G")
                        .font(.caption.bold())
                }
            } compactTrailing: {
                // Compact trailing (right pill)
                Image(systemName: context.state.isListening ? "mic.fill" : "mic")
                    .font(.caption)
                    .foregroundColor(context.state.isListening ? .red : .cyan)
            } minimal: {
                // Minimal (just the dot)
                Circle()
                    .fill(statusColor(context.state.status))
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Lock Screen View

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<GActivityAttributes>) -> some View {
        HStack(spacing: 12) {
            // Status
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor(context.state.status))
                        .frame(width: 8, height: 8)
                    Text("G")
                        .font(.headline.bold())
                        .foregroundColor(.white)
                    Text(context.state.status.rawValue)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if let response = context.state.lastResponse {
                    Text(response)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(2)
                }
            }

            Spacer()

            // Push-to-talk button — opens app and starts listening
            Link(destination: URL(string: "g-assistant://talk")!) {
                Image(systemName: context.state.isListening ? "mic.fill" : "mic.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(context.state.isListening ? .red : .cyan)
                    .frame(width: 50, height: 50)
            }
        }
        .padding(16)
        .background(Color(red: 0.06, green: 0.06, blue: 0.10))
    }

    private func statusColor(_ status: GActivityAttributes.ContentState.GStatus) -> Color {
        switch status {
        case .ready: return .green
        case .listening: return .red
        case .thinking: return .yellow
        case .speaking: return .cyan
        }
    }
}
