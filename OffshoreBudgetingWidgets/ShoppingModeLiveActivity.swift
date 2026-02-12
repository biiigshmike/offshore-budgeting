import SwiftUI
import WidgetKit

#if canImport(ActivityKit)
import ActivityKit

// MARK: - ShoppingModeLiveActivity

struct ShoppingModeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShoppingModeActivityAttributes.self) { context in
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color("OffshoreBrand"))

                VStack(spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "sailboat.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Excursion Mode")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text("Active until \(context.state.endDate, format: .dateTime.hour().minute())")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.88))
                        }

                        Spacer()
                    }

                    HStack(spacing: 14) {
                        CountdownRing(
                            startDate: context.attributes.startDate,
                            endDate: context.state.endDate
                        )
                        .frame(width: 56, height: 56)

                        Text(context.state.endDate, style: .timer)
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)

                        Spacer()
                    }

                    HStack(spacing: 10) {
                        if let stopURL = ExcursionDeepLink.stopURL {
                            Link(destination: stopURL) {
                                Label("Stop", systemImage: "stop.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(.black.opacity(0.28), in: Capsule())
                                    .foregroundStyle(.white)
                            }
                        }

                        if let extendURL = ExcursionDeepLink.extendThirtyURL {
                            Link(destination: extendURL) {
                                Label("30 min", systemImage: "plus")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(.black.opacity(0.28), in: Capsule())
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }
                .padding(14)
            }
            .activityBackgroundTint(Color("OffshoreBrand"))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "sailboat.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.endDate, style: .timer)
                        .monospacedDigit()
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        Text("Excursion Mode")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                        Spacer()

                        if let stopURL = ExcursionDeepLink.stopURL {
                            Link(destination: stopURL) {
                                Label("Stop", systemImage: "stop.fill")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .frame(minWidth: 64, minHeight: 33)
                                    .background(.white.opacity(0.18), in: Capsule())
                                    .foregroundStyle(.white)
                                    .contentShape(Rectangle())
                            }
                        }
                        if let extendURL = ExcursionDeepLink.extendThirtyURL {
                            Link(destination: extendURL) {
                                Label("30 min", systemImage: "plus")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .frame(minWidth: 64, minHeight: 33)
                                    .background(.white.opacity(0.18), in: Capsule())
                                    .foregroundStyle(.white)
                                    .contentShape(Rectangle())
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Image(systemName: "sailboat.fill")
                        .font(.caption.weight(.semibold))
                    CompactCountdownText(endDate: context.state.endDate)
                }
                .foregroundStyle(.white)
            } compactTrailing: {
                EmptyView()
            } minimal: {
                ViewThatFits {
                    HStack(spacing: 2) {
                        Image(systemName: "sailboat.fill")
                            .font(.caption2.weight(.semibold))
                        MinimalCountdownText(endDate: context.state.endDate)
                    }
                    .foregroundStyle(.white)

                    Image(systemName: "sailboat.fill")
                        .foregroundStyle(.white)

                    MinimalCountdownText(endDate: context.state.endDate)
                }
            }
        }
    }
}

// MARK: - ExcursionDeepLink

private enum ExcursionDeepLink {
    static let scheme = "offshore"

    static var stopURL: URL? {
        URL(string: "\(scheme)://action/excursion/stop")
    }

    static var extendThirtyURL: URL? {
        URL(string: "\(scheme)://action/excursion/extend30")
    }
}

// MARK: - CountdownRing

private struct CountdownRing: View {
    let startDate: Date
    let endDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let progress = ringProgress(now: context.date)

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.35), lineWidth: 6)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color.white,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
    }

    private func ringProgress(now: Date) -> CGFloat {
        let total = max(1, endDate.timeIntervalSince(startDate))
        let remaining = max(0, endDate.timeIntervalSince(now))
        let elapsed = total - remaining
        return CGFloat(min(max(elapsed / total, 0), 1))
    }
}

// MARK: - MinimalCountdownText

private struct MinimalCountdownText: View {
    let endDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(shortRemainingText(now: context.date))
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func shortRemainingText(now: Date) -> String {
        let remaining = max(0, endDate.timeIntervalSince(now))
        let totalMinutes = max(0, Int(ceil(remaining / 60)))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            let minuteText = minutes < 10 ? "0\(minutes)" : "\(minutes)"
            return "\(hours):\(minuteText)"
        }
        return "\(minutes)m"
    }
}

// MARK: - CompactCountdownText

private struct CompactCountdownText: View {
    let endDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(compactRemainingText(now: context.date))
                .monospacedDigit()
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.white)
        }
    }

    private func compactRemainingText(now: Date) -> String {
        let remaining = max(0, endDate.timeIntervalSince(now))
        let totalSeconds = Int(remaining.rounded(.up))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            let minuteText = minutes < 10 ? "0\(minutes)" : "\(minutes)"
            return "\(hours):\(minuteText)"
        }

        let secondText = seconds < 10 ? "0\(seconds)" : "\(seconds)"
        return "\(minutes):\(secondText)"
    }
}
#endif
