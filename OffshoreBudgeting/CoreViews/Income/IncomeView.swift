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
    @Query private var incomes: [Income]

    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true

    @Environment(\.modelContext) private var modelContext

    @State private var displayedMonth: Date
    @State private var selectedDate: Date

    @State private var showingIncomeDeleteConfirm: Bool = false
    @State private var pendingIncomeDelete: (() -> Void)? = nil
    
    @State private var viewWidth: CGFloat = 0

    // MARK: - Calendar width tracking

    @State private var calendarAvailableWidth: CGFloat = 0
    
    private var calendarMonthCount: Int {
        #if targetEnvironment(macCatalyst)
        if viewWidth >= 1400 { return 4 }
        if viewWidth >= 980 { return 2 }
        return 1
        #else
        if viewWidth >= 980 { return 2 }
        return 1
        #endif
    }

    // MARK: - Search

    @State private var searchText: String = ""
    @FocusState private var searchFocused: Bool

    // MARK: - Sheets

    @State private var showingAddIncome: Bool = false
    @State private var addIncomeInitialDate: Date = .now

    @State private var showingEditIncome: Bool = false
    @State private var editingIncome: Income? = nil

    init(workspace: Workspace) {
        self.workspace = workspace

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

    struct DayIncomePresence {
        var hasPlanned: Bool = false
        var hasActual: Bool = false
    }

    private func incomePresenceByDay(for startMonth: Date, monthCount: Int) -> [Date: DayIncomePresence] {
        let cal = CalendarGridHelper.sundayFirstCalendar

        let start = CalendarGridHelper.startOfMonth(for: startMonth)
        let end = CalendarGridHelper.addingMonths(monthCount, to: start)

        let rangeIncomes = incomes.filter { income in
            income.date >= start && income.date < end
        }

        var presence: [Date: DayIncomePresence] = [:]

        for income in rangeIncomes {
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
        let monthPresence = incomePresenceByDay(for: displayedMonth, monthCount: calendarMonthCount)

        GeometryReader { proxy in
            List {
                // MARK: - Calendar

                Section {
                    MultiMonthCalendarView(
                        startMonth: displayedMonth,
                        monthCount: calendarMonthCount,
                        selectedDate: selectedDate,
                        incomePresenceByDay: monthPresence,
                        onStepDay: { deltaDays in
                            let cal = CalendarGridHelper.sundayFirstCalendar
                            let newDate = cal.date(byAdding: .day, value: deltaDays, to: selectedDate) ?? selectedDate
                            let normalized = cal.startOfDay(for: newDate)
                            selectedDate = normalized
                            displayedMonth = CalendarGridHelper.startOfMonth(for: normalized)
                        },
                        onJumpToMonthStart: { deltaMonths in
                            let cal = CalendarGridHelper.sundayFirstCalendar
                            let targetMonth = CalendarGridHelper.addingMonths(deltaMonths, to: displayedMonth)
                            let monthStart = CalendarGridHelper.startOfMonth(for: targetMonth)
                            selectedDate = cal.startOfDay(for: monthStart)
                            displayedMonth = monthStart
                        },
                        onJumpToToday: {
                            let cal = CalendarGridHelper.sundayFirstCalendar
                            let today = cal.startOfDay(for: Date())
                            selectedDate = today
                            displayedMonth = CalendarGridHelper.startOfMonth(for: today)
                        },
                        onSelectDate: { tapped in
                            let cal = CalendarGridHelper.sundayFirstCalendar
                            selectedDate = cal.startOfDay(for: tapped)
                            displayedMonth = CalendarGridHelper.startOfMonth(for: tapped)
                        }
                    )
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
                                editingIncome = income
                                showingEditIncome = true
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
                                    editingIncome = income
                                    showingEditIncome = true
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
            // ✅ proxy is in scope here
            .onAppear { viewWidth = proxy.size.width }
            .onChange(of: proxy.size.width) { _, newValue in
                viewWidth = newValue
            }

            // keep your existing modifiers on the List
            .postBoardingTip(
                key: "tip.income.v1",
                title: "Income",
                items: [
                    PostBoardingTipItem(systemImage: "calendar", title: "Income Calendar", detail: "View income in a calendar to visualize earnings, almost like a timesheet."),
                    PostBoardingTipItem(systemImage: "calendar.badge.plus", title: "Planned Income", detail: "Add income you expect to earn but haven’t received yet."),
                    PostBoardingTipItem(systemImage: "calendar.badge.checkmark", title: "Actual Income", detail: "Log income you’ve actually received."),
                    PostBoardingTipItem(systemImage: "calendar.badge.clock", title: "Recurring Income", detail: "Planned and actual income can be setup to be a recurring series."),
                    PostBoardingTipItem(systemImage: "magnifyingglass", title: "Search Income", detail: "Search by source, card, date, or amount using the search bar.")
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
                    addIncomeInitialDate = selectedDayStart
                    showingAddIncome = true
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
            .sheet(isPresented: $showingAddIncome) {
                NavigationStack {
                    AddIncomeView(workspace: workspace, initialDate: addIncomeInitialDate)
                }
            }
            .sheet(isPresented: $showingEditIncome, onDismiss: { editingIncome = nil }) {
                NavigationStack {
                    if let editingIncome {
                        EditIncomeView(workspace: workspace, income: editingIncome)
                    } else {
                        EmptyView()
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func deleteIncome(_ income: Income) {
        modelContext.delete(income)
        if editingIncome?.id == income.id {
            showingEditIncome = false
            editingIncome = nil
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

// MARK: - Calendar (Multi-month)

private struct MultiMonthCalendarView: View {

    let startMonth: Date
    let monthCount: Int
    let selectedDate: Date
    let incomePresenceByDay: [Date: IncomeView.DayIncomePresence]
    let onStepDay: (Int) -> Void
    let onJumpToMonthStart: (Int) -> Void
    let onJumpToToday: () -> Void
    let onSelectDate: (Date) -> Void

    var body: some View {
        VStack(spacing: 12) {
                    if #available(iOS 26.0, *) {
                        HStack {
                            Spacer()
                            Button {
                                onJumpToMonthStart(-1)
                            } label: {
                                Image(systemName: "chevron.backward.2")
                                    .frame(width: 25, height: 25)
                            }
                            .accessibilityLabel("Previous Month")
                            Spacer()
                            Button {
                                onStepDay(-1)
                            } label: {
                                Image(systemName: "chevron.backward")
                                    .frame(width: 25, height: 25)

                            }
                            .accessibilityLabel("Previous Day")
                            Spacer()
                            Button {
                                onJumpToToday()
                            } label: {
                                Text("Today")
                                    .frame(width: 55, height: 25)
                            }
                            .accessibilityLabel("Jump to Today")
                            Spacer()
                            Button {
                                onStepDay(1)
                            } label: {
                                Image(systemName: "chevron.forward")
                                    .frame(width: 25, height: 25)
                            }
                            .accessibilityLabel("Next Day")
                            Spacer()
                            Button {
                                onJumpToMonthStart(1)
                            } label: {
                                Image(systemName: "chevron.forward.2")
                                    .frame(width: 25, height: 25)
                            }
                            .accessibilityLabel("Next Month")
                            Spacer()
                        }
                        .font(.headline)
                        .buttonStyle(.glass)
                    } else {
                        HStack {
                            Spacer()
                            Button {
                                onJumpToMonthStart(-1)
                            } label: {
                                Image(systemName: "chevron.backward.2")
                                    .frame(width: 33, height: 33)
                            }
                            .accessibilityLabel("Previous Month")
                            Spacer()
                            Button {
                                onStepDay(-1)
                            } label: {
                                Image(systemName: "chevron.backward")
                                    .frame(width: 33, height: 33)
                            }
                            .accessibilityLabel("Previous Day")
                            Spacer()
                            Button {
                                onJumpToToday()
                            } label: {
                                Text("Today")
                                    .frame(width: 55, height: 33)
                            }
                            .accessibilityLabel("Jump to Today")
                            Spacer()
                            Button {
                                onStepDay(1)
                            } label: {
                                Image(systemName: "chevron.forward")
                                    .frame(width: 33, height: 33)
                            }
                            .accessibilityLabel("Next Day")
                            Spacer()
                            Button {
                                onJumpToMonthStart(1)
                            } label: {
                                Image(systemName: "chevron.forward.2")
                                    .frame(width: 33, height: 33)
                            }
                            .accessibilityLabel("Next Month")
                            Spacer()
                        }
                        .font(.headline)
                        .buttonStyle(.plain)
                    }

            HStack(alignment: .top, spacing: 24) {
                ForEach(0..<monthCount, id: \.self) { offset in
                    let month = CalendarGridHelper.addingMonths(offset, to: startMonth)

                    VStack(spacing: 8) {
                        Text(CalendarGridHelper.monthTitleFormatter.string(from: month))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        WeekdayHeaderView()

                        MonthGridView(
                            displayedMonth: month,
                            selectedDate: selectedDate,
                            incomePresenceByDay: incomePresenceByDay,
                            onSelectDate: onSelectDate
                        )
                    }
                    .frame(maxWidth: 420)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }

        }
    }
}

// MARK: - Calendar UI (shared pieces)

private struct WeekdayHeaderView: View {

    private let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(minimum: 34, maximum: 56), spacing: 0),
        count: 7
    )

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            let symbols = CalendarGridHelper.weekdaySymbolsSundayFirst
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct MonthGridView: View {

    let displayedMonth: Date
    let selectedDate: Date
    let incomePresenceByDay: [Date: IncomeView.DayIncomePresence]
    let onSelectDate: (Date) -> Void

    private let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(minimum: 34, maximum: 56), spacing: 0),
        count: 7
    )

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
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, alignment: .center)
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

// MARK: - Width measurement helpers (non-invasive)

private struct WidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct WidthReader: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: WidthPreferenceKey.self, value: proxy.size.width)
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

    static let monthShortFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = sundayFirstCalendar
        df.locale = .current
        df.setLocalizedDateFormatFromTemplate("LLL")
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
            IncomeView(workspace: ws)
        }
    }
}
