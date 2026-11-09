import SwiftUI
import WidgetKit

struct CategoryLimitWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: CategoryLimitWidgetSnapshotStore.kind,
            intent: CategoryLimitWidgetConfigurationIntent.self,
            provider: CategoryLimitWidgetProvider()
        ) { entry in
            CategoryLimitWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Category Limit")
        .description("See how much of a category’s budget limit you’ve used.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

private struct CategoryLimitWidgetEntry: TimelineEntry {
    let date: Date
    let metric: CategoryLimitWidgetMetric?
    var hasSelection = true
}

private struct CategoryLimitWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CategoryLimitWidgetEntry {
        CategoryLimitWidgetEntry(date: .now, metric: nil, hasSelection: false)
    }

    func snapshot(
        for configuration: CategoryLimitWidgetConfigurationIntent,
        in context: Context
    ) async -> CategoryLimitWidgetEntry {
        let now = Date()
        if context.isPreview,
           let options = CategoryLimitWidgetSnapshotStore.loadSelectedPickerOptions(),
           let first = CategoryLimitWidgetCategoryQuery.eligibleCategories(in: options, asOf: now).first,
           let id = UUID(uuidString: first.id) {
            let current = CategoryLimitWidgetSnapshotStore.loadSelected()?.days.first {
                $0.date <= now && now < $0.validUntil
            }
            return entry(for: current, categoryID: id, date: now)
        }
        return makeTimeline(for: configuration, now: now).entries[0]
    }

    func timeline(
        for configuration: CategoryLimitWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<CategoryLimitWidgetEntry> {
        makeTimeline(for: configuration, now: .now)
    }

    private func makeTimeline(
        for configuration: CategoryLimitWidgetConfigurationIntent,
        now: Date
    ) -> Timeline<CategoryLimitWidgetEntry> {
        guard let category = configuration.category, let id = UUID(uuidString: category.id) else {
            let entry = CategoryLimitWidgetEntry(date: now, metric: nil, hasSelection: false)
            return Timeline(entries: [entry], policy: .never)
        }

        let snapshots = CategoryLimitWidgetSnapshotStore.loadSelected()?.days ?? []
        let current = snapshots.first { $0.date <= now && now < $0.validUntil }
        let future = snapshots.filter { $0.date > now }
        var entries = [entry(for: current, categoryID: id, date: now)]
        for snapshot in future {
            let upcoming = entry(for: snapshot, categoryID: id, date: snapshot.date)
            if entries.last?.metric != upcoming.metric {
                entries.append(upcoming)
            }
        }

        if let expiry = (future.last ?? current)?.validUntil {
            if entries.last?.metric != nil {
                entries.append(CategoryLimitWidgetEntry(date: expiry, metric: nil))
            }
            return Timeline(entries: entries, policy: .after(expiry))
        }

        return Timeline(entries: entries, policy: .after(WidgetTimelineSchedule.fallbackRefreshDate(afterRangeEnd: nil, now: now)))
    }

    private func entry(
        for snapshot: CategoryLimitWidgetSnapshot?,
        categoryID: UUID,
        date: Date
    ) -> CategoryLimitWidgetEntry {
        CategoryLimitWidgetEntry(date: date, metric: snapshot?.metrics.first { $0.id == categoryID })
    }
}

private struct CategoryLimitWidgetEntryView: View {
    let entry: CategoryLimitWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .accessoryRectangular {
                rectangularBody
            } else if let metric = entry.metric {
                metricView(metric)
                    .privacySensitive()
            } else {
                VStack(spacing: 2) {
                    Image(systemName: "tag")
                        .font(.caption)
                    Text("—")
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(entry.hasSelection ? "Category limit unavailable" : "Choose a category in widget settings")
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var rectangularBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let metric = entry.metric {
                Text(metric.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                if let remaining = metric.remainingAmount, let limit = metric.limitAmount {
                    Text(remaining < 0 ? "\(amountText(-remaining)) over" : "\(amountText(remaining)) left")
                        .font(.headline.weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    Text("\(amountText(limit)) limit")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Open Offshore to refresh")
                        .font(.caption)
                        .lineLimit(2)
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.25))
                        Capsule().fill(.primary)
                            .frame(width: geometry.size.width * min(max(metric.fractionUsed, 0), 1))
                            .widgetAccentable()
                    }
                }
                .frame(height: 4)
                .accessibilityLabel("Category limit used")
                .accessibilityValue(Text(metric.fractionUsed.formatted(.percent.precision(.fractionLength(0)))))
            } else {
                Label("Category Limit", systemImage: "tag")
                    .font(.caption.weight(.semibold))
                Text(entry.hasSelection ? "Category limit unavailable" : "Choose a category in widget settings")
                    .font(.caption)
                    .lineLimit(2)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .leading)
        .privacySensitive()
        .accessibilityElement(children: .combine)
    }

    private func amountText(_ amount: Double) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: amount), number: .currency)
    }

    private func metricView(_ metric: CategoryLimitWidgetMetric) -> some View {
        let progress = min(max(metric.fractionUsed, 0), 1)
        let percentage = metric.fractionUsed.formatted(.percent.precision(.fractionLength(0)))
        let arcFraction = 2.0 / 3.0
        let stroke = StrokeStyle(lineWidth: 3, lineCap: .round)

        return ZStack {
            Circle()
                .trim(from: 0, to: arcFraction)
                .stroke(Color.secondary.opacity(0.25), style: stroke)
                .rotationEffect(.degrees(150))
            Circle()
                .trim(from: 0, to: arcFraction * progress)
                .stroke(.primary, style: stroke)
                .rotationEffect(.degrees(150))
                .widgetAccentable()
            Text(percentage)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 5)
        }
        .padding(2)
        .overlay(alignment: .bottom) {
            Text(metric.name)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .allowsTightening(true)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 2)
                .padding(.bottom, 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(metric.name))
        .accessibilityValue(Text("\(percentage) of category limit used"))
    }
}

#Preview("Category remaining", as: .accessoryRectangular) {
    CategoryLimitWidget()
} timeline: {
    CategoryLimitWidgetEntry(date: .now, metric: CategoryLimitWidgetMetric(
        id: UUID(), name: "Groceries", fractionUsed: 0.68, limitAmount: 500, spentAmount: 340
    ))
    CategoryLimitWidgetEntry(date: .now, metric: CategoryLimitWidgetMetric(
        id: UUID(), name: "Dining and Entertainment", fractionUsed: 1.25, limitAmount: 100, spentAmount: 125
    ))
    CategoryLimitWidgetEntry(date: .now, metric: nil, hasSelection: false)
}
