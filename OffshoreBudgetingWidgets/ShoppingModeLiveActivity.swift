import SwiftUI
import WidgetKit
import AppIntents

private func liveActivityLocalized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

private struct ExcursionStatusTextView: View {
    let endDate: Date
    let isExpired: Bool
    let font: Font
    let foregroundStyle: Color

    var body: some View {
        ViewThatFits(in: .horizontal) {
            primaryText
            secondaryText
            compactText
            timeOnlyText
        }
    }

    private var primaryText: some View {
        statusText(isExpired ? Text(liveActivityLocalized("Session ended")) : Text("Active until \(endDate, format: .dateTime.hour().minute())"))
    }

    private var secondaryText: some View {
        statusText(isExpired ? Text(liveActivityLocalized("Session ended")) : Text("Ends \(endDate, format: .dateTime.hour().minute())"))
    }

    private var compactText: some View {
        statusText(isExpired ? Text(liveActivityLocalized("Ended")) : Text("Until \(endDate, format: .dateTime.hour().minute())"))
    }

    private var timeOnlyText: some View {
        statusText(isExpired ? Text(liveActivityLocalized("Done")) : Text(endDate, format: .dateTime.hour().minute()))
    }

    private func statusText(_ text: Text) -> some View {
        text
            .font(font)
            .foregroundStyle(foregroundStyle)
            .lineLimit(1)
            .allowsTightening(true)
            .fixedSize(horizontal: true, vertical: false)
    }
}

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit

// MARK: - ShoppingModeLiveActivity

struct ShoppingModeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShoppingModeActivityAttributes.self) { context in
            ShoppingModeLockScreenLiveActivityView(context: context)
                .activityBackgroundTint(ShoppingModeLiveActivityPalette.surface)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading, priority: 2) {
                    ShoppingModeExpandedIslandLeadingContentView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing, priority: 1) {
                    ShoppingModeExpandedIslandTimerView(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ShoppingModeExpandedIslandActionsView(endDate: context.state.endDate)
                }
            } compactLeading: {
                Image(systemName: "sailboat.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            } compactTrailing: {
                CompactCountdownText(
                    startDate: context.attributes.startDate,
                    endDate: context.state.endDate
                )
                    .foregroundStyle(.white)
                    .frame(width: 40, alignment: .trailing)
            } minimal: {
                Image(systemName: "sailboat.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - ShoppingModeLockScreenLiveActivityView

private struct ShoppingModeLockScreenLiveActivityView: View {
    let context: ActivityViewContext<ShoppingModeActivityAttributes>

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            content(now: timeline.date)
        }
    }

    private func content(now: Date) -> some View {
        let isExpired = ExcursionLiveActivityPhase.isExpired(endDate: context.state.endDate, now: now)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "sailboat.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(ShoppingModeLiveActivityPalette.brandAccent)

                        Text(liveActivityLocalized("Offshore"))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(ShoppingModeLiveActivityPalette.primaryText)
                    }

                    ViewThatFits(in: .horizontal) {
                        Text(liveActivityLocalized("Excursion Mode"))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(ShoppingModeLiveActivityPalette.primaryText)
                            .lineLimit(1)

                        Text(liveActivityLocalized("Excursion Mode"))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(ShoppingModeLiveActivityPalette.primaryText)
                            .lineLimit(1)

                        Text(liveActivityLocalized("Excursion Mode"))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(ShoppingModeLiveActivityPalette.primaryText)
                            .lineLimit(1)
                    }

                    ExcursionStatusTextView(
                        endDate: context.state.endDate,
                        isExpired: isExpired,
                        font: .footnote.weight(.medium),
                        foregroundStyle: ShoppingModeLiveActivityPalette.secondaryText
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Group {
                    if isExpired {
                        FinishedTimerBadge()
                    } else {
                        ZStack {
                            CountdownRing(
                                startDate: context.attributes.startDate,
                                endDate: context.state.endDate,
                                lineWidth: 4.0,
                                trackColor: ShoppingModeLiveActivityPalette.ringTrack,
                                progressColor: ShoppingModeLiveActivityPalette.ringProgress
                            )

                            LockScreenRingTimerText(endDate: context.state.endDate)
                        }
                    }
                }
                .frame(width: 66, height: 66)
            }

            if isExpired == false {
                HStack(spacing: 8) {
                    Button(intent: StopExcursionIntent()) {
                        Label(liveActivityLocalized("Stop"), systemImage: "stop.fill")
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .foregroundStyle(ShoppingModeLiveActivityPalette.primaryText)
                            .contentShape(Rectangle())
                    }

                    Button(intent: ExtendExcursionIntent()) {
                        Label(liveActivityLocalized("30 min"), systemImage: "plus")
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .foregroundStyle(ShoppingModeLiveActivityPalette.primaryText)
                            .contentShape(Rectangle())
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - ExpandedIslandMetrics

private struct ExpandedIslandMetrics {
    let topInset: CGFloat
    let timerTopOffset: CGFloat
    let topRowSpacing: CGFloat
    let brandRowSpacing: CGFloat
    let brandIconSize: CGFloat
    let brandFontSize: CGFloat
    let titleSize: CGFloat
    let subtitleSize: CGFloat
    let timerDiameter: CGFloat
    let timerLineWidth: CGFloat
    let timerFontSize: CGFloat
    let timerTextMaxWidth: CGFloat
    let actionsSpacing: CGFloat
    let actionLabelSize: CGFloat
    let actionHeight: CGFloat

    static let large = ExpandedIslandMetrics(
        topInset: 1,
        timerTopOffset: 1,
        topRowSpacing: 2,
        brandRowSpacing: 4,
        brandIconSize: 12,
        brandFontSize: 15,
        titleSize: 24,
        subtitleSize: 13,
        timerDiameter: 54,
        timerLineWidth: 3.6,
        timerFontSize: 12,
        timerTextMaxWidth: 44,
        actionsSpacing: 8,
        actionLabelSize: 15,
        actionHeight: 30
    )

    static let medium = ExpandedIslandMetrics(
        topInset: 1,
        timerTopOffset: 1,
        topRowSpacing: 2,
        brandRowSpacing: 4,
        brandIconSize: 11,
        brandFontSize: 14,
        titleSize: 22,
        subtitleSize: 12,
        timerDiameter: 50,
        timerLineWidth: 3.4,
        timerFontSize: 11,
        timerTextMaxWidth: 40,
        actionsSpacing: 7,
        actionLabelSize: 14,
        actionHeight: 29
    )

    static let small = ExpandedIslandMetrics(
        topInset: 0,
        timerTopOffset: 1,
        topRowSpacing: 1,
        brandRowSpacing: 3,
        brandIconSize: 10,
        brandFontSize: 13,
        titleSize: 20,
        subtitleSize: 11,
        timerDiameter: 46,
        timerLineWidth: 3.2,
        timerFontSize: 10,
        timerTextMaxWidth: 36,
        actionsSpacing: 6,
        actionLabelSize: 13,
        actionHeight: 28
    )
}

// MARK: - ShoppingModeExpandedIslandLeadingContentView

private struct ShoppingModeExpandedIslandLeadingContentView: View {
    let context: ActivityViewContext<ShoppingModeActivityAttributes>

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            ViewThatFits(in: .horizontal) {
                leadingContent(metrics: .large, now: timeline.date)
                leadingContent(metrics: .medium, now: timeline.date)
                leadingContent(metrics: .small, now: timeline.date)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func leadingContent(metrics: ExpandedIslandMetrics, now: Date) -> some View {
        let isExpired = ExcursionLiveActivityPhase.isExpired(endDate: context.state.endDate, now: now)

        return VStack(alignment: .leading, spacing: metrics.topRowSpacing) {
            HStack(spacing: metrics.brandRowSpacing) {
                Image(systemName: "sailboat.fill")
                    .font(.system(size: metrics.brandIconSize, weight: .semibold))
                    .foregroundStyle(ShoppingModeLiveActivityPalette.brandAccent)

                Text(liveActivityLocalized("Offshore"))
                    .font(.system(size: metrics.brandFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(ShoppingModeLiveActivityPalette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(liveActivityLocalized("Excursion Mode"))
                    .font(.system(size: metrics.titleSize, weight: .bold, design: .rounded))
                    .foregroundStyle(ShoppingModeLiveActivityPalette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)

                ExcursionStatusTextView(
                    endDate: context.state.endDate,
                    isExpired: isExpired,
                    font: .system(size: metrics.subtitleSize, weight: .medium, design: .rounded),
                    foregroundStyle: ShoppingModeLiveActivityPalette.secondaryText
                )
            }
            .dynamicIsland(verticalPlacement: .belowIfTooWide)
        }
        .padding(.top, metrics.topInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - ShoppingModeExpandedIslandTimerView

private struct ShoppingModeExpandedIslandTimerView: View {
    let context: ActivityViewContext<ShoppingModeActivityAttributes>

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            ViewThatFits {
                timer(metrics: .large, now: timeline.date)
                timer(metrics: .medium, now: timeline.date)
                timer(metrics: .small, now: timeline.date)
            }
            .frame(maxHeight: .infinity, alignment: .topTrailing)
        }
    }

    private func timer(metrics: ExpandedIslandMetrics, now: Date) -> some View {
        let isExpired = ExcursionLiveActivityPhase.isExpired(endDate: context.state.endDate, now: now)

        return ZStack {
            if isExpired {
                FinishedTimerBadge(fontSize: metrics.timerFontSize)
            } else {
                CountdownRing(
                    startDate: context.attributes.startDate,
                    endDate: context.state.endDate,
                    lineWidth: metrics.timerLineWidth,
                    trackColor: ShoppingModeLiveActivityPalette.ringTrack,
                    progressColor: ShoppingModeLiveActivityPalette.ringProgress
                )

                ExpandedRingTimerText(
                    endDate: context.state.endDate,
                    fontSize: metrics.timerFontSize,
                    maxWidth: metrics.timerTextMaxWidth
                )
            }
        }
        .frame(width: metrics.timerDiameter, height: metrics.timerDiameter)
        .padding(.top, metrics.timerTopOffset)
    }
}

// MARK: - ShoppingModeExpandedIslandActionsView

private struct ShoppingModeExpandedIslandActionsView: View {
    let endDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            if ExcursionLiveActivityPhase.isExpired(endDate: endDate, now: timeline.date) == false {
                ViewThatFits(in: .horizontal) {
                    actionRow(metrics: .large)
                    actionRow(metrics: .medium)
                    actionRow(metrics: .small)
                }
            } else {
                EmptyView()
            }
        }
    }

    private func actionRow(metrics: ExpandedIslandMetrics) -> some View {
        HStack(spacing: metrics.actionsSpacing) {
            Button(intent: StopExcursionIntent()) {
                Label(liveActivityLocalized("Stop"), systemImage: "stop.fill")
                    .font(.system(size: metrics.actionLabelSize, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .frame(maxWidth: .infinity, minHeight: metrics.actionHeight)
                    .foregroundStyle(ShoppingModeLiveActivityPalette.primaryText)
                    .contentShape(Rectangle())
            }

            Button(intent: ExtendExcursionIntent()) {
                Label(liveActivityLocalized("30 min"), systemImage: "plus")
                    .font(.system(size: metrics.actionLabelSize, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .frame(maxWidth: .infinity, minHeight: metrics.actionHeight)
                    .foregroundStyle(ShoppingModeLiveActivityPalette.primaryText)
                    .contentShape(Rectangle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - ExcursionDeepLink

private enum ExcursionDeepLink {
    static let scheme = "offshore"

    static var stopURL: URL? {
        URL(string: "\(scheme)://action/excursion/stop")
    }
}

// MARK: - ShoppingModeLiveActivityPalette

private enum ExcursionLiveActivityPhase {
    static func isExpired(endDate: Date, now: Date) -> Bool {
        now >= endDate
    }
}

private enum ShoppingModeLiveActivityPalette {
    static let surface = Color(.black)
    static let border = Color.white.opacity(0.08)
    static let controlFill = Color.white.opacity(0.18)
    static let brandAccent = Color(red: 0.27, green: 0.76, blue: 1.0)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.84)
    static let ringTrack = Color.white.opacity(0.35)
    static let ringProgress = Color.white
}

// MARK: - CountdownRing

private struct CountdownRing: View {
    let startDate: Date
    let endDate: Date
    let lineWidth: CGFloat
    let trackColor: Color
    let progressColor: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let progress = ringProgress(now: context.date)

            ZStack {
                Circle()
                    .stroke(trackColor, lineWidth: lineWidth)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        progressColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
    }

    private func ringProgress(now: Date) -> CGFloat {
        let total = max(1, endDate.timeIntervalSince(startDate))
        let remaining = max(0, endDate.timeIntervalSince(now))
        return CGFloat(min(max(remaining / total, 0), 1))
    }
}

// MARK: - FinishedTimerBadge

private struct FinishedTimerBadge: View {
    var fontSize: CGFloat = 12

    var body: some View {
        ZStack {
            Circle()
                .stroke(ShoppingModeLiveActivityPalette.ringTrack, lineWidth: 3)

            Text(liveActivityLocalized("Done"))
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ShoppingModeLiveActivityPalette.primaryText)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
    }
}

// MARK: - LockScreenRingTimerText

private struct LockScreenRingTimerText: View {
    let endDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            if ExcursionLiveActivityPhase.isExpired(endDate: endDate, now: timeline.date) {
                Text(liveActivityLocalized("Done"))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(ShoppingModeLiveActivityPalette.primaryText)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .frame(width: 52, alignment: .center)
            } else {
                Text(
                    timerInterval: timeline.date...endDate,
                    pauseTime: nil,
                    countsDown: true,
                    showsHours: true
                )
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(ShoppingModeLiveActivityPalette.primaryText)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .frame(width: 52, alignment: .center)
            }
        }
    }
}

// MARK: - ExpandedRingTimerText

private struct ExpandedRingTimerText: View {
    let endDate: Date
    let fontSize: CGFloat
    let maxWidth: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            if ExcursionLiveActivityPhase.isExpired(endDate: endDate, now: timeline.date) {
                Text(liveActivityLocalized("Done"))
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(ShoppingModeLiveActivityPalette.primaryText)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .frame(width: maxWidth, alignment: .center)
            } else {
                Text(
                    timerInterval: timeline.date...endDate,
                    pauseTime: nil,
                    countsDown: true,
                    showsHours: true
                )
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(ShoppingModeLiveActivityPalette.primaryText)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .frame(width: maxWidth, alignment: .center)
            }
        }
    }
}

// MARK: - CompactCountdownText

private struct CompactCountdownText: View {
    let startDate: Date
    let endDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            if ExcursionLiveActivityPhase.isExpired(endDate: endDate, now: timeline.date) {
                Text(liveActivityLocalized("Done"))
                    .monospacedDigit()
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.white)
                    .frame(width: 34, alignment: .trailing)
            } else {
                Text(
                    timerInterval: timeline.date...endDate,
                    pauseTime: nil,
                    countsDown: true,
                    showsHours: false
                )
                .monospacedDigit()
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.white)
                .frame(width: 34, alignment: .trailing)
            }
        }
    }
}
#endif
