import SwiftUI
import WidgetKit

struct SafeSpendTodayWidgetSnapshot: Codable, Hashable {
    let title: String
    let periodTitle: String
    let rangeStart: Date
    let rangeEnd: Date
    let safeToSpendToday: Double?
    let periodRemainingRoom: Double?
    let daysLeftInPeriod: Int?
    let isDailyPeriod: Bool
    let message: String?
}

struct SafeSpendTodayWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: SafeSpendTodayWidgetSnapshot?
}

extension SafeSpendTodayWidgetSnapshot {
    static var placeholder: SafeSpendTodayWidgetSnapshot {
        let start = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now)) ?? .now
        let end = Calendar.current.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? .now

        return SafeSpendTodayWidgetSnapshot(
            title: widgetLocalized("Safe Spend Today"),
            periodTitle: widgetLocalized("Monthly"),
            rangeStart: start,
            rangeEnd: end,
            safeToSpendToday: 42.15,
            periodRemainingRoom: 379.35,
            daysLeftInPeriod: 9,
            isDailyPeriod: false,
            message: nil
        )
    }
}

struct SafeSpendTodayWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SafeSpendTodayWidgetEntry {
        SafeSpendTodayWidgetEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SafeSpendTodayWidgetEntry) -> Void) {
        completion(
            SafeSpendTodayWidgetEntry(
                date: .now,
                snapshot: loadSnapshot() ?? .placeholder
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SafeSpendTodayWidgetEntry>) -> Void) {
        let entry = SafeSpendTodayWidgetEntry(date: .now, snapshot: loadSnapshot())
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 3, to: .now) ?? .now.addingTimeInterval(10_800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadSnapshot() -> SafeSpendTodayWidgetSnapshot? {
        guard let workspaceID = SafeSpendTodayWidgetSnapshotStore.selectedWorkspaceID(), !workspaceID.isEmpty else {
            return nil
        }
        return SafeSpendTodayWidgetSnapshotStore.load(workspaceID: workspaceID)
    }
}

struct SafeSpendTodayWidget: Widget {
    static let kind = "SafeSpendTodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SafeSpendTodayWidgetProvider()) { entry in
            SafeSpendTodayWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Safe Spend Today")
        .description("See a glanceable safe-to-spend amount for today.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

private struct SafeSpendTodayWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SafeSpendTodayWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                rectangularBody
            case .systemMedium:
                mediumBody
            default:
                smallBody
            }
        }
        .widgetURL(OffshoreWidgetDeepLink.openSafeSpendTodayURL)
        .containerBackground(.background, for: .widget)
    }

    private var snapshot: SafeSpendTodayWidgetSnapshot {
        entry.snapshot ?? .placeholder
    }

    private var rangeText: String {
        widgetCompactDateRangeText(start: snapshot.rangeStart, end: snapshot.rangeEnd)
    }

    private var safeAmountText: String {
        amountText(snapshot.safeToSpendToday)
    }

    private var periodRemainingText: String {
        amountText(snapshot.periodRemainingRoom)
    }

    private var secondarySummaryText: String {
        if snapshot.isDailyPeriod {
            return "Budget period: \(snapshot.periodTitle)"
        }

        let daysLeft = snapshot.daysLeftInPeriod ?? 0
        return "\(daysLeft) day(s) left in \(snapshot.periodTitle.lowercased())"
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeaderView(
                title: snapshot.title,
                periodToken: "",
                rangeText: rangeText,
                style: .stacked
            )

            if let message = snapshot.message {
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            } else {
                Text(safeAmountText)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("Today")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text(secondarySummaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
    }

    private var mediumBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeaderView(
                title: snapshot.title,
                periodToken: "",
                rangeText: rangeText,
                style: .singleLine
            )

            if let message = snapshot.message {
                Text(message)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(safeAmountText)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Text("today")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    summaryPill(title: snapshot.isDailyPeriod ? "Today" : "Period Room", value: periodRemainingText)
                    if !snapshot.isDailyPeriod {
                        summaryPill(title: "Days Left", value: "\(snapshot.daysLeftInPeriod ?? 0)")
                    }
                }

                Text(secondarySummaryText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
    }

    private var rectangularBody: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(snapshot.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let message = snapshot.message {
                Text(message)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
            } else {
                Text("\(safeAmountText) today")
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(rectangularSupportingText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var rectangularSupportingText: String {
        if snapshot.isDailyPeriod {
            return snapshot.periodTitle
        }

        return "\(snapshot.daysLeftInPeriod ?? 0)d left"
    }

    private func summaryPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private func amountText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return NumberFormatter.localizedString(from: NSNumber(value: value), number: .currency)
    }
}
