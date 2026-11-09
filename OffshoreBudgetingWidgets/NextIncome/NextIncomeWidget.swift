import SwiftUI
import WidgetKit

struct NextIncomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: NextIncomeWidgetSnapshotStore.kind, provider: NextIncomeWidgetProvider()) { entry in
            Text(entry.title)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Next Income")
        .description("Count down to your next planned income.")
        .supportedFamilies([.accessoryInline])
    }
}

private struct NextIncomeWidgetEntry: TimelineEntry {
    let date: Date
    let day: NextIncomeWidgetDay?

    var title: LocalizedStringResource {
        guard let day else { return "Income unavailable" }
        guard let incomeDate = day.nextIncomeDate else { return "No planned income" }
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: incomeDate)
        ).day ?? 0
        if days == 0 { return "Next income today" }
        let countdown = Duration.seconds(days * 86_400).formatted(.units(allowed: [.days], width: .narrow))
        return "Next income in \(countdown)"
    }
}

private struct NextIncomeWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextIncomeWidgetEntry {
        let now = Date()
        return NextIncomeWidgetEntry(
            date: now,
            day: NextIncomeWidgetDay(date: now, nextIncomeDate: Calendar.current.date(byAdding: .day, value: 5, to: now))
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (NextIncomeWidgetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entries(now: .now)[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextIncomeWidgetEntry>) -> Void) {
        let timeline = entries(now: .now)
        completion(Timeline(entries: timeline, policy: .after((timeline.last?.date ?? .now).addingTimeInterval(3 * 60 * 60))))
    }

    private func entries(now: Date) -> [NextIncomeWidgetEntry] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let days = NextIncomeWidgetSnapshotStore.loadSelectedDays().filter {
            $0.date >= today && $0.date == calendar.startOfDay(for: $0.date)
        }
        let current = NextIncomeWidgetEntry(date: now, day: days.first { $0.date == today })
        let future = days.filter { $0.date > now }.map { NextIncomeWidgetEntry(date: $0.date, day: $0) }
        guard let lastDay = days.last,
              let expiry = calendar.date(byAdding: .day, value: 1, to: lastDay.date)
        else { return [current] }
        return [current] + future + [NextIncomeWidgetEntry(date: expiry, day: nil)]
    }
}
