import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Live Activity Attributes

struct WindLiveActivityAttributes: ActivityAttributes {
    // Fixed properties (set at start)
    let stationName: String
    let stationId: String

    // Dynamic state (updated in real-time)
    struct ContentState: Codable, Hashable {
        let wind: Double
        let gust: Double
        let direction: Double
        let isOnline: Bool
        let unit: String
        let lastUpdate: Date
    }
}

// MARK: - Live Activity Widget

struct AnemOuestWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WindLiveActivityAttributes.self) { context in
            // Lock screen / notification banner
            LockScreenLiveActivityView(context: context)
                .activityBackgroundTint(Color(white: 0.08))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.stationName)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        HStack(spacing: 3) {
                            Circle()
                                .fill(context.state.isOnline ? .green : .red)
                                .frame(width: 5, height: 5)
                            Text(context.state.isOnline ? "En ligne" : "Hors ligne")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 2) {
                            Text("\(Int(context.state.wind))")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(windColor(context.state.wind))
                            Text("/\(Int(context.state.gust))")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(windColor(context.state.gust).opacity(0.8))
                        }
                        Text(context.state.unit)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    EmptyView()
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        // Direction
                        HStack(spacing: 4) {
                            Image(systemName: "location.north.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.cyan)
                                .rotationEffect(.degrees(context.state.direction))
                            Text(cardinalDir(context.state.direction))
                                .font(.system(size: 13, weight: .semibold))
                        }

                        Spacer()

                        // Last update
                        Text(relTime(context.state.lastUpdate))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                // Compact: wind icon + value
                HStack(spacing: 3) {
                    Image(systemName: "wind")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.cyan)
                    Text("\(Int(context.state.wind))")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(windColor(context.state.wind))
                }
            } compactTrailing: {
                // Compact: gust + direction
                HStack(spacing: 2) {
                    Text("/\(Int(context.state.gust))")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.cyan.opacity(0.7))
                        .rotationEffect(.degrees(context.state.direction))
                }
            } minimal: {
                // Minimal: just wind speed
                Text("\(Int(context.state.wind))")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(windColor(context.state.wind))
            }
            .widgetURL(URL(string: "anemouest://station/\(context.attributes.stationId)"))
        }
    }
}

// MARK: - Lock Screen Live Activity View

struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<WindLiveActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            // Left: Station info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "wind")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.cyan)
                    Text(context.attributes.stationName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(context.state.isOnline ? .green : .red)
                        .frame(width: 5, height: 5)
                    Text(relTime(context.state.lastUpdate))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            Spacer()

            // Center: Direction
            VStack(spacing: 2) {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.cyan)
                    .rotationEffect(.degrees(context.state.direction))
                Text(cardinalDir(context.state.direction))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }

            // Right: Wind values
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(Int(context.state.wind))")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(windColor(context.state.wind))
                    Text("/\(Int(context.state.gust))")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(windColor(context.state.gust).opacity(0.8))
                }
                Text(context.state.unit)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Helpers

private func windColor(_ knots: Double) -> Color {
    switch knots {
    case ..<7:  return Color(red: 0.70, green: 0.93, blue: 1.00)
    case ..<11: return Color(red: 0.33, green: 0.85, blue: 0.92)
    case ..<17: return Color(red: 0.35, green: 0.89, blue: 0.52)
    case ..<22: return Color(red: 0.97, green: 0.90, blue: 0.33)
    case ..<28: return Color(red: 0.98, green: 0.67, blue: 0.23)
    case ..<34: return Color(red: 0.95, green: 0.22, blue: 0.26)
    case ..<41: return Color(red: 0.83, green: 0.20, blue: 0.67)
    case ..<48: return Color(red: 0.55, green: 0.24, blue: 0.78)
    default:    return Color(red: 0.39, green: 0.24, blue: 0.63)
    }
}

private func cardinalDir(_ degrees: Double) -> String {
    let dirs = ["N", "NE", "E", "SE", "S", "SO", "O", "NO"]
    let i = Int((degrees + 22.5).truncatingRemainder(dividingBy: 360) / 45)
    return dirs[max(0, min(i, 7))]
}

private func relTime(_ date: Date) -> String {
    let s = Int(-date.timeIntervalSinceNow)
    if s < 60 { return "a l'instant" }
    if s < 3600 { return "il y a \(s / 60)min" }
    return "il y a \(s / 3600)h"
}

// MARK: - Previews

#Preview("Live Activity - Banner", as: .content, using: WindLiveActivityAttributes(stationName: "Glenan", stationId: "wc_1")) {
    AnemOuestWidgetLiveActivity()
} contentStates: {
    WindLiveActivityAttributes.ContentState(wind: 22, gust: 30, direction: 275, isOnline: true, unit: "nds", lastUpdate: Date())
    WindLiveActivityAttributes.ContentState(wind: 28, gust: 38, direction: 290, isOnline: true, unit: "nds", lastUpdate: Date())
}
