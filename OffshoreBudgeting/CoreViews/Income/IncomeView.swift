//
//  IncomeView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/20/26.
//

import SwiftUI
import SwiftData

struct IncomeView: View {

    let workspace: Workspace
    @Binding var sheetRoute: IncomeSheetRoute?
    @Query private var incomes: [Income]

    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true

    @Environment(\.modelContext) private var modelContext

    @State private var displayedMonth: Date
    @State private var selectedDate: Date

    @State private var showingIncomeDeleteConfirm: Bool = false
    @State private var pendingIncomeDelete: (() -> Void)? = nil

    // MARK: - Search

    @State private var searchText: String = ""
    @FocusState private var searchFocused: Bool

    init(workspace: Workspace, sheetRoute: Binding<IncomeSheetRoute?>) {
        self.workspace = workspace
        self._sheetRoute = sheetRoute

        let workspaceID = workspace.id
        _incomes = Query(
            filter: #Predicate<Income> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Income.date, order: .reverse)]
        )

        let today = Date()
        _displayedMonth = State(initialValue: CalendarGridHelper.startOfMonth(for: today))
        _selectedDate = State(initialValue: CalendarGridHelper.sundayFirstCalendar.startOfDay(for: today))
    }

    // MARK: - Selected Day Range

    private var selectedDayStart: Date {
        CalendarGridHelper.sundayFirstCalendar.startOfDay(for: selectedDate)
    }

    private var selectedDayEnd: Date {
        CalendarGridHelper.sundayFirstCalendar.date(byAdding: .day, value: 1, to: selectedDayStart) ?? selectedDayStart
    }

    // MARK: - Filters

    private var incomesForSelectedDay: [Income] {
        incomes.filter { income in
            income.date >= selectedDayStart && income.date < selectedDayEnd
        }
        .sorted { $0.date > $1.date }
    }

    private var incomesSearchedAll: [Income] {
        let query = SearchQueryParser.parse(searchText)
        guard !query.isEmpty else { return incomes }

        return incomes
            .filter { income in
                if !SearchMatch.matchesDateRange(query, date: income.date) { return false }
                if !SearchMatch.matchesTextTerms(query, in: [income.source, income.card?.name]) { return false }
                if !SearchMatch.matchesAmountDigitTerms(query, amounts: [income.amount]) { return false }
                return true
            }
            .sorted { $0.date > $1.date }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedDayTitle: String {
        CalendarGridHelper.selectedDayTitleFormatter.string(from: selectedDayStart)
    }

    // MARK: - Month indicators (planned vs actual per day)

    private var displayedMonthStart: Date {
        CalendarGridHelper.startOfMonth(for: displayedMonth)
    }

    private var displayedMonthEnd: Date {
        CalendarGridHelper.addingMonths(1, to: displayedMonthStart)
    }

    struct DayIncomePresence {
        var hasPlanned: Bool = false
        var hasActual: Bool = false
    }

    /// Keyed by start-of-day Date for the displayed month.
    private var displayedMonthIncomePresenceByDay: [Date: DayIncomePresence] {
        let cal = CalendarGridHelper.sundayFirstCalendar

        let monthIncomes = incomes.filter { income in
            income.date >= displayedMonthStart && income.date < displayedMonthEnd
        }

        var presence: [Date: DayIncomePresence] = [:]

        for income in monthIncomes {
            let dayKey = cal.startOfDay(for: income.date)
            var current = presence[dayKey, default: DayIncomePresence()]

            if income.isPlanned {
                current.hasPlanned = true
            } else {
                current.hasActual = true
            }

            presence[dayKey] = current
        }

        return presence
    }

    // MARK: - Week Totals (planned vs actual)

    private var selectedWeekStart: Date {
        CalendarGridHelper.startOfWeek(for: selectedDayStart)
    }

    private var selectedWeekEndExclusive: Date {
        CalendarGridHelper.sundayFirstCalendar.date(byAdding: .day, value: 7, to: selectedWeekStart) ?? selectedWeekStart
    }

    private var selectedWeekRangeText: String {
        let startText = CalendarGridHelper.rangeDateFormatter.string(from: selectedWeekStart)
        let endInclusive = CalendarGridHelper.sundayFirstCalendar.date(byAdding: .day, value: 6, to: selectedWeekStart) ?? selectedWeekStart
        let endText = CalendarGridHelper.rangeDateFormatter.string(from: endInclusive)
        return "\(startText) – \(endText)"
    }

    private var weekPlannedTotal: Double {
        incomes
            .filter { $0.date >= selectedWeekStart && $0.date < selectedWeekEndExclusive }
            .filter { $0.isPlanned == true }
            .reduce(0) { $0 + $1.amount }
    }

    private var weekActualTotal: Double {
        incomes
            .filter { $0.date >= selectedWeekStart && $0.date < selectedWeekEndExclusive }
            .filter { $0.isPlanned == false }
            .reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        List {
            // MARK: - Calendar

            Section {
                VStack(spacing: 12) {
                    MonthHeaderView(
                        displayedMonth: displayedMonth,
                        onPreviousMonth: {
                            displayedMonth = CalendarGridHelper.addingMonths(-1, to: displayedMonth)
                        },
                        onNextMonth: {
                            displayedMonth = CalendarGridHelper.addingMonths(1, to: displayedMonth)
                        }
                    )

                    WeekdayHeaderView()

                    MonthGridView(
                        displayedMonth: displayedMonth,
                        selectedDate: selectedDate,
                        incomePresenceByDay: displayedMonthIncomePresenceByDay,
                        onSelectDate: { tapped in
                            let cal = CalendarGridHelper.sundayFirstCalendar
                            selectedDate = cal.startOfDay(for: tapped)
                            displayedMonth = CalendarGridHelper.startOfMonth(for: tapped)
                        }
                    )
                }
                .padding(.vertical, 8)
            }

            // MARK: - Row 1: Selected day list (swipe edit/delete)

            Section(
                header: VStack(alignment: .leading, spacing: 4) {
                    Text(isSearching ? "Search Results" : "Income")
                        .font(.headline)

                    Text(isSearching ? "All income entries" : selectedDayTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            ) {
                let rows = isSearching ? incomesSearchedAll : incomesForSelectedDay

                if rows.isEmpty {
                    Text(isSearching ? "No matching income." : "No income for \(CalendarGridHelper.shortDateFormatter.string(from: selectedDayStart)).")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rows) { income in
                        Button {
                            sheetRoute = .edit(income)
                        } label: {
                            IncomeRowView(income: income)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                if confirmBeforeDeleting {
                                    pendingIncomeDelete = {
                                        deleteIncome(income)
                                    }
                                    showingIncomeDeleteConfirm = true
                                } else {
                                    deleteIncome(income)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                sheetRoute = .edit(income)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }


            // MARK: - Row 2: Week totals

            Section(header: Text("Week Total Income")) {
                WeeklyIncomeTotalsRow(
                    plannedTotal: weekPlannedTotal,
                    actualTotal: weekActualTotal,
                    rangeText: selectedWeekRangeText
                )
            }
        }
        .postBoardingTip(
            key: "tip.income.v1",
            title: "Income",
            items: [
                PostBoardingTipItem(
                    systemImage: "calendar",
                    title: "Income Calendar",
                    detail: "View income in a calendar to visualize earnings, almost like a timesheet."
                ),
                PostBoardingTipItem(
                    systemImage: "calendar.badge.plus",
                    title: "Planned Income",
                    detail: "Add income you expect to earn but haven’t received yet."
                ),
                PostBoardingTipItem(
                    systemImage: "calendar.badge.checkmark",
                    title: "Actual Income",
                    detail: "Log income you’ve actually received."
                ),
                PostBoardingTipItem(
                    systemImage: "calendar.badge.clock",
                    title: "Recurring Income",
                    detail: "Planned and actual income can be setup to be a recurring series."
                ),
                PostBoardingTipItem(
                    systemImage: "magnifyingglass",
                    title: "Search Income",
                    detail: "Search by source, card, date, or amount using the search bar."
                )
            ]
        )
        .navigationTitle("Income")
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search"
        )
        .searchFocused($searchFocused)
        .toolbar {
            Button {
                sheetRoute = .add(initialDate: selectedDayStart)
            } label: {
                Image(systemName: "plus")
            }
        }
        .alert("Delete?", isPresented: $showingIncomeDeleteConfirm) {
            Button("Delete", role: .destructive) {
                pendingIncomeDelete?()
                pendingIncomeDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingIncomeDelete = nil
            }
        }
    }

    // MARK: - Actions

    private func deleteIncome(_ income: Income) {
        modelContext.delete(income)
        if case .edit(let editing)? = sheetRoute, editing.id == income.id {
            sheetRoute = nil
        }
    }
}

// MARK: - Row Views

private struct IncomeRowView: View {

    let income: Income

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(income.source)
                    .font(.headline)

                Text(income.isPlanned ? "Planned" : "Actual")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(income.amount, format: CurrencyFormatter.currencyStyle())
                .foregroundStyle(income.isPlanned ? .orange : .blue)
                .font(.headline)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WeeklyIncomeTotalsRow: View {

    let plannedTotal: Double
    let actualTotal: Double
    let rangeText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Planned")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(plannedTotal, format: CurrencyFormatter.currencyStyle())
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Actual")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(actualTotal, format: CurrencyFormatter.currencyStyle())
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }

            Text(rangeText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Calendar UI

private struct MonthHeaderView: View {

    let displayedMonth: Date
    let onPreviousMonth: () -> Void
    let onNextMonth: () -> Void

    private var monthTitle: String {
        CalendarGridHelper.monthTitleFormatter.string(from: displayedMonth)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPreviousMonth) {
                Image(systemName: "chevron.left")
                    .font(.headline)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(monthTitle)
                .font(.headline)

            Spacer()

            Button(action: onNextMonth) {
                Image(systemName: "chevron.right")
                    .font(.headline)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct WeekdayHeaderView: View {

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            let symbols = CalendarGridHelper.weekdaySymbolsSundayFirst
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct MonthGridView: View {

    let displayedMonth: Date
    let selectedDate: Date
    let incomePresenceByDay: [Date: IncomeView.DayIncomePresence]
    let onSelectDate: (Date) -> Void

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private var days: [CalendarGridHelper.DayCell] {
        CalendarGridHelper.makeMonthGrid(for: displayedMonth)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(days) { cell in
                let dayKey = CalendarGridHelper.sundayFirstCalendar.startOfDay(for: cell.date)
                let presence = incomePresenceByDay[dayKey]

                DayCellView(
                    cell: cell,
                    isSelected: CalendarGridHelper.sundayFirstCalendar.isDate(cell.date, inSameDayAs: selectedDate),
                    presence: presence
                ) {
                    onSelectDate(cell.date)
                }
            }
        }
    }
}

private struct DayCellView: View {

    let cell: CalendarGridHelper.DayCell
    let isSelected: Bool
    let presence: IncomeView.DayIncomePresence?
    let onTap: () -> Void

    private var dayNumber: String {
        "\(CalendarGridHelper.sundayFirstCalendar.component(.day, from: cell.date))"
    }

    private var hasPlanned: Bool { presence?.hasPlanned == true }
    private var hasActual: Bool { presence?.hasActual == true }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text(dayNumber)
                    .font(.callout)
                    .frame(width: 34, height: 34)
                    .foregroundStyle(dayForegroundStyle)
                    .background {
                        Circle()
                            .fill(dayBackgroundStyle)
                    }
                    .opacity(cell.isInDisplayedMonth ? 1.0 : 0.45)

                DotIndicatorView(hasPlanned: hasPlanned, hasActual: hasActual)
                    .frame(height: 8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(cell.isInDisplayedMonth ? "Select day" : "Select day outside current month")
    }

    private var dayForegroundStyle: Color {
        if isSelected { return .primary }
        return cell.isInDisplayedMonth ? .primary : .secondary
    }

    private var dayBackgroundStyle: Color {
        if isSelected { return .secondary.opacity(0.25) }
        return .clear
    }

    private var accessibilityLabel: String {
        let dateString = CalendarGridHelper.dayAccessibilityFormatter.string(from: cell.date)

        if hasPlanned && hasActual {
            return "\(dateString), planned and actual income"
        } else if hasPlanned {
            return "\(dateString), planned income"
        } else if hasActual {
            return "\(dateString), actual income"
        } else {
            return dateString
        }
    }
}

private struct DotIndicatorView: View {

    let hasPlanned: Bool
    let hasActual: Bool

    var body: some View {
        if hasPlanned && hasActual {
            HStack(spacing: 3) {
                Circle()
                    .frame(width: 6, height: 6)
                    .foregroundStyle(.orange)

                Circle()
                    .frame(width: 6, height: 6)
                    .foregroundStyle(.blue)
            }
            .accessibilityHidden(true)
        } else if hasPlanned {
            Circle()
                .frame(width: 6, height: 6)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
        } else if hasActual {
            Circle()
                .frame(width: 6, height: 6)
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
        } else {
            Color.clear
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Calendar Helpers

private enum CalendarGridHelper {

    static let sundayFirstCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 1 // Sunday
        return cal
    }()

    static let monthTitleFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = sundayFirstCalendar
        df.locale = .current
        df.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return df
    }()

    static let selectedDayTitleFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = sundayFirstCalendar
        df.locale = .current
        df.dateStyle = .full
        df.timeStyle = .none
        return df
    }()

    static let dayAccessibilityFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = sundayFirstCalendar
        df.locale = .current
        df.dateStyle = .full
        df.timeStyle = .none
        return df
    }()

    static let shortDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = sundayFirstCalendar
        df.locale = .current
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()

    static let rangeDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = sundayFirstCalendar
        df.locale = .current
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()

    static var weekdaySymbolsSundayFirst: [String] {
        sundayFirstCalendar.veryShortStandaloneWeekdaySymbols
    }

    struct DayCell: Identifiable, Hashable {
        let id: Date
        let date: Date
        let isInDisplayedMonth: Bool
    }

    static func startOfMonth(for date: Date) -> Date {
        let comps = sundayFirstCalendar.dateComponents([.year, .month], from: date)
        return sundayFirstCalendar.date(from: comps) ?? date
    }

    static func addingMonths(_ months: Int, to date: Date) -> Date {
        sundayFirstCalendar.date(byAdding: .month, value: months, to: date) ?? date
    }

    static func startOfWeek(for date: Date) -> Date {
        let weekday = sundayFirstCalendar.component(.weekday, from: date) // Sunday = 1
        let daysFromSunday = weekday - sundayFirstCalendar.firstWeekday
        return sundayFirstCalendar.date(byAdding: .day, value: -daysFromSunday, to: sundayFirstCalendar.startOfDay(for: date)) ?? date
    }

    static func makeMonthGrid(for monthDate: Date) -> [DayCell] {
        let monthStart = startOfMonth(for: monthDate)

        guard
            let firstOfMonth = sundayFirstCalendar.date(from: sundayFirstCalendar.dateComponents([.year, .month], from: monthStart))
        else {
            return []
        }

        let weekdayOfFirst = sundayFirstCalendar.component(.weekday, from: firstOfMonth) // Sunday = 1
        let leadingDays = (weekdayOfFirst - sundayFirstCalendar.firstWeekday + 7) % 7

        let totalCells = 42

        guard let gridStart = sundayFirstCalendar.date(byAdding: .day, value: -leadingDays, to: firstOfMonth) else {
            return []
        }

        let displayedMonth = sundayFirstCalendar.component(.month, from: firstOfMonth)
        let displayedYear = sundayFirstCalendar.component(.year, from: firstOfMonth)

        return (0..<totalCells).compactMap { offset in
            guard let date = sundayFirstCalendar.date(byAdding: .day, value: offset, to: gridStart) else {
                return nil
            }

            let cellMonth = sundayFirstCalendar.component(.month, from: date)
            let cellYear = sundayFirstCalendar.component(.year, from: date)

            let isInDisplayedMonth = (cellMonth == displayedMonth && cellYear == displayedYear)
            return DayCell(id: date, date: date, isInDisplayedMonth: isInDisplayedMonth)
        }
    }
}

// MARK: - Preview

#Preview("Income") {
    let container = PreviewSeed.makeContainer()
    PreviewHost(container: container) { ws in
        NavigationStack {
            IncomeView(workspace: ws, sheetRoute: .constant(nil))
        }
    }
}
