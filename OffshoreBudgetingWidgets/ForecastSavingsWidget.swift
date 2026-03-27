import SwiftUI
import WidgetKit

struct ForecastSavingsWidgetSnapshot: Codable, Hashable {
    let title: String
    let rangeStart: Date
    let rangeEnd: Date
    let projectedSavings: Double?
    let actualSavings: Double?
    let gapToProjected: Double?
    let statusLine: String
    let message: String?
}

struct ForecastSavingsWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: ForecastSavingsWidgetSnapshot?
}

extension ForecastSavingsWidgetSnapshot {
    static var placeholder: ForecastSavingsWidgetSnapshot {
        let start = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now)) ?? .now
        let end = Calendar.current.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? .now

        return ForecastSavingsWidgetSnapshot(
            title: widgetLocalized("Forecast Savings"),
            rangeStart: start,
            rangeEnd: end,
            projectedSavings: 640,
            actualSavings: 522,
            gapToProjected: -118,
            statusLine: "Forecast is currently on track.",
            message: nil
        )
    }
}

struct ForecastSavingsWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ForecastSavingsWidgetEntry {
        ForecastSavingsWidgetEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (ForecastSavingsWidgetEntry) -> Void) {
        completion(
            ForecastSavingsWidgetEntry(
                date: .now,
                snapshot: loadSnapshot() ?? .placeholder
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ForecastSavingsWidgetEntry>) -> Void) {
        let entry = ForecastSavingsWidgetEntry(date: .now, snapshot: loadSnapshot())
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 3, to: .now) ?? .now.addingTimeInterval(10_800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadSnapshot() -> ForecastSavingsWidgetSnapshot? {
        guard let workspaceID = ForecastSavingsWidgetSnapshotStore.selectedWorkspaceID(), !workspaceID.isEmpty else {
            return nil
        }
        return ForecastSavingsWidgetSnapshotStore.load(workspaceID: workspaceID)
    }
}

struct ForecastSavingsWidget: Widget {
    static let kind = "ForecastSavingsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ForecastSavingsWidgetProvider()) { entry in
            ForecastSavingsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Forecast Savings")
        .description("See projected end-of-month savings at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

private struct ForecastSavingsWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ForecastSavingsWidgetEntry

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
        .widgetURL(OffshoreWidgetDeepLink.openForecastSavingsURL)
        .containerBackground(.background, for: .widget)
    }

    private var snapshot: ForecastSavingsWidgetSnapshot {
        entry.snapshot ?? .placeholder
    }

    private var rangeText: String {
        widgetCompactDateRangeText(start: snapshot.rangeStart, end: snapshot.rangeEnd)
    }

    private var projectedText: String {
        amountText(snapshot.projectedSavings)
    }

    private var actualText: String {
        amountText(snapshot.actualSavings)
    }

    private var gapText: String {
        amountText(snapshot.gapToProjected)
    }

    private var compactStatusText: String {
        if (snapshot.projectedSavings ?? 0) < 0 {
            return "Overspending"
        }
        if (snapshot.actualSavings ?? 0) < 0 {
            return "Actuals Negative"
        }
        return "On Track"
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
                Text(projectedText)
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("Projected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text(snapshot.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
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
                    Text(projectedText)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Text("projected")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    summaryPill(title: "Actual", value: actualText)
                    summaryPill(title: "Gap", value: gapText)
                }

                Text(snapshot.statusLine)
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
                Text(projectedText)
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(compactStatusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
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
