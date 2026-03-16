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
    @AppStorage(AppShortcutNavigationStore.pendingActionKey) private var pendingShortcutActionRaw: String = ""
    @AppStorage(AppShortcutNavigationStore.pendingImportClipboardTextKey) private var pendingImportClipboardText: String = ""

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appCommandHub) private var commandHub
    @Environment(\.appTabActivationContext) private var tabActivationContext
    @Environment(DetailViewSnapshotCache.self) private var detailSnapshotCache

    @State private var displayedMonth: Date
    @State private var selectedDate: Date

    @State private var showingIncomeDeleteConfirm: Bool = false
    @State private var pendingIncomeDelete: (() -> Void)? = nil
    
    @State private var viewWidth: CGFloat = 0
    @State private var rootSnapshot: IncomeRootSnapshot = .empty
    @State private var hasLoadedRootSnapshot: Bool = false
    @State private var needsRootSnapshotRefresh: Bool = false
    @State private var rootSnapshotRefreshTask: Task<Void, Never>? = nil
    @State private var activationEnrichmentTask: Task<Void, Never>? = nil

    // MARK: - Calendar width tracking

    @State private var calendarAvailableWidth: CGFloat = 0
    
    private var calendarMonthCount: Int {
        if viewWidth < 500 {
            // All iPhones, split iPad
            return 1
        }

        if viewWidth < 980 {
            // iPad portrait or split
            return 1
        }

        if viewWidth < 1250 {
            // iPad landscape, small Mac window
            return 2
        }

        if viewWidth < 1600 {
            // Large iPad / medium Mac
            return 3
        }

        if viewWidth < 1900 {
            // Large Mac
            return 4
        }

        return 5
    }


    // MARK: - Search

    @State private var searchText: String = ""
    @FocusState private var searchFocused: Bool

    // MARK: - Sheets

    @State private var addIncomeSheet: AddIncomeSheet? = nil
    @State private var showingImportIncomeSheet: Bool = false
    @State private var shortcutImportClipboardText: String? = nil

    @State private var showingEditIncome: Bool = false
    @State private var editingIncome: Income? = nil

    @State private var showingShortcutDeletePicker: Bool = false
    @State private var shortcutDeleteCandidates: [Income] = []
    @State private var shortcutDeleteKind: IncomeDeleteKind? = nil

    private var isPhone: Bool {
        #if canImport(UIKit)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    private var shouldSyncCommandSurface: Bool {
        isPhone == false
    }

    init(workspace: Workspace) {
        self.workspace = workspace

        let workspaceID = workspace.id
        _incomes = Query(
            filter: #Predicate<Income> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Income.date, order: .reverse)]
        )

        let today = Date()
        _displayedMonth = State(initialValue: CalendarGridHelper.startOfMonth(for: today))
        _selectedDate = State(initialValue: CalendarGridHelper.displayCalendar.startOfDay(for: today))
    }

    private enum IncomeDeleteKind {
        case actual
        case planned

        var isPlanned: Bool {
            self == .planned
        }

        var title: String {
            switch self {
            case .actual:
                return "Actual Income"
            case .planned:
                return "Planned Income"
            }
        }
    }

    // MARK: - Selected Day Range

    private var selectedDayStart: Date {
        CalendarGridHelper.displayCalendar.startOfDay(for: selectedDate)
    }

    private var selectedDayEnd: Date {
        CalendarGridHelper.displayCalendar.date(byAdding: .day, value: 1, to: selectedDayStart) ?? selectedDayStart
    }

    // MARK: - Filters

    private var incomesForSelectedDay: [Income] {
        if hasLoadedRootSnapshot {
            return rootSnapshot.incomesForSelectedDay
        }

        return incomes.filter { income in
            income.date >= selectedDayStart && income.date < selectedDayEnd
        }
        .sorted { $0.date > $1.date }
    }

    private var incomesSearchedAll: [Income] {
        if hasLoadedRootSnapshot {
            return rootSnapshot.incomesSearchedAll
        }

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

    private var snapshotSearchText: String {
        hasLoadedRootSnapshot ? rootSnapshot.searchText : searchText
    }

    private var isIncomeSearchActive: Bool {
        !snapshotSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldUseSnapshotDrivenPresentation: Bool {
        hasLoadedRootSnapshot && tabActivationContext.phase != .active
    }

    private var selectedDayTitle: String {
        CalendarGridHelper.selectedDayTitleFormatter.string(from: selectedDayStart)
    }

    private var actualIncomesForSelectedDay: [Income] {
        if hasLoadedRootSnapshot {
            return rootSnapshot.actualIncomesForSelectedDay
        }
        return incomesForSelectedDay.filter { !$0.isPlanned }
    }

    private var plannedIncomesForSelectedDay: [Income] {
        if hasLoadedRootSnapshot {
            return rootSnapshot.plannedIncomesForSelectedDay
        }
        return incomesForSelectedDay.filter { $0.isPlanned }
    }

    // MARK: - Month indicators (planned vs actual per day)

    struct DayIncomePresence {
        var hasPlanned: Bool = false
        var hasActual: Bool = false
    }

    private struct IncomeRootSnapshot {
        let searchText: String
        let monthPresence: [Date: DayIncomePresence]
        let incomesForSelectedDay: [Income]
        let incomesSearchedAll: [Income]
        let actualIncomesForSelectedDay: [Income]
        let plannedIncomesForSelectedDay: [Income]
        let weekPlannedTotal: Double
        let weekActualTotal: Double

        static let empty = IncomeRootSnapshot(
            searchText: "",
            monthPresence: [:],
            incomesForSelectedDay: [],
            incomesSearchedAll: [],
            actualIncomesForSelectedDay: [],
            plannedIncomesForSelectedDay: [],
            weekPlannedTotal: 0,
            weekActualTotal: 0
        )
    }

    private struct IncomeRootSnapshotInputs: Equatable {
        let selectedDayStart: Date
        let selectedDayEnd: Date
        let selectedWeekStart: Date
        let selectedWeekEndExclusive: Date
        let displayedMonth: Date
        let monthCount: Int
        let searchText: String
        let incomesSignature: Int
    }

    private func incomePresenceByDay(for startMonth: Date, monthCount: Int) -> [Date: DayIncomePresence] {
        let cal = CalendarGridHelper.displayCalendar

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
        CalendarGridHelper.displayCalendar.date(byAdding: .day, value: 7, to: selectedWeekStart) ?? selectedWeekStart
    }

    private var selectedWeekRangeText: String {
        let startText = CalendarGridHelper.rangeDateFormatter.string(from: selectedWeekStart)
        let endInclusive = CalendarGridHelper.displayCalendar.date(byAdding: .day, value: 6, to: selectedWeekStart) ?? selectedWeekStart
        let endText = CalendarGridHelper.rangeDateFormatter.string(from: endInclusive)
        return "\(startText) – \(endText)"
    }

    private var weekPlannedTotal: Double {
        if hasLoadedRootSnapshot {
            return rootSnapshot.weekPlannedTotal
        }

        return incomes
            .filter { $0.date >= selectedWeekStart && $0.date < selectedWeekEndExclusive }
            .filter { $0.isPlanned == true }
            .reduce(0) { $0 + $1.amount }
    }

    private var weekActualTotal: Double {
        if hasLoadedRootSnapshot {
            return rootSnapshot.weekActualTotal
        }

        return incomes
            .filter { $0.date >= selectedWeekStart && $0.date < selectedWeekEndExclusive }
            .filter { $0.isPlanned == false }
            .reduce(0) { $0 + $1.amount }
    }

    private var rootSnapshotInputs: IncomeRootSnapshotInputs {
        IncomeRootSnapshotInputs(
            selectedDayStart: selectedDayStart,
            selectedDayEnd: selectedDayEnd,
            selectedWeekStart: selectedWeekStart,
            selectedWeekEndExclusive: selectedWeekEndExclusive,
            displayedMonth: displayedMonth,
            monthCount: calendarMonthCount,
            searchText: searchText,
            incomesSignature: SnapshotContentSignature.incomes(incomes)
        )
    }

    private var rootSnapshotCacheKey: String {
        [
            "income-root",
            workspace.id.uuidString,
            String(Int64(selectedDayStart.timeIntervalSinceReferenceDate)),
            String(Int64(displayedMonth.timeIntervalSinceReferenceDate)),
            String(calendarMonthCount),
            searchText,
            String(SnapshotContentSignature.incomes(incomes))
        ].joined(separator: "|")
    }

    private var monthPresence: [Date: DayIncomePresence] {
        if shouldUseSnapshotDrivenPresentation {
            return rootSnapshot.monthPresence
        }
        return incomePresenceByDay(for: displayedMonth, monthCount: calendarMonthCount)
    }

    var body: some View {
        GeometryReader { proxy in
            contentView(proxy: proxy)
        }
    }

    private var incomeTipItems: [PostBoardingTipItem] {
        [
            PostBoardingTipItem(systemImage: "calendar", title: "Income Calendar", detail: "View income in a calendar to visualize earnings, almost like a timesheet."),
            PostBoardingTipItem(systemImage: "calendar.badge.plus", title: "Planned Income", detail: "Add income you expect to earn but haven’t received yet."),
            PostBoardingTipItem(systemImage: "calendar.badge.checkmark", title: "Actual Income", detail: "Log income you’ve actually received."),
            PostBoardingTipItem(systemImage: "calendar.badge.clock", title: "Recurring Income", detail: "Planned and actual income can be setup to be a recurring series."),
            PostBoardingTipItem(systemImage: "magnifyingglass", title: "Search Income", detail: "Search by source, card, date, or amount using the search bar.")
        ]
    }

    private func contentView(proxy: GeometryProxy) -> some View {
        configuredIncomeView(proxy: proxy)
            .sheet(item: $addIncomeSheet) { sheet in
                NavigationStack {
                    AddIncomeView(
                        workspace: workspace,
                        initialDate: sheet.initialDate,
                        initialIsPlanned: sheet.initialIsPlanned
                    )
                }
            }
            .sheet(isPresented: $showingImportIncomeSheet) {
                NavigationStack {
                    ExpenseCSVImportFlowView(
                        workspace: workspace,
                        initialClipboardText: shortcutImportClipboardText
                    )
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
            .onAppear(perform: handleContentAppear)
            .onDisappear(perform: handleContentDisappear)
            .onChange(of: pendingShortcutActionRaw) { _, _ in
                consumePendingShortcutActionIfNeeded()
            }
            .onChange(of: selectedDayStart) { _, _ in
                if shouldSyncCommandSurface {
                    updateIncomeCommandAvailability()
                }
            }
            .onChange(of: actualIncomesForSelectedDay.count) { _, _ in
                if shouldSyncCommandSurface {
                    updateIncomeCommandAvailability()
                }
            }
            .onChange(of: plannedIncomesForSelectedDay.count) { _, _ in
                if shouldSyncCommandSurface {
                    updateIncomeCommandAvailability()
                }
            }
            .onChange(of: rootSnapshotInputs) { _, _ in
                if tabActivationContext.phase == .active {
                    scheduleRootSnapshotRefresh(reason: "inputsChanged")
                } else {
                    needsRootSnapshotRefresh = true
                }
            }
            .onChange(of: tabActivationContext) { _, newValue in
                guard newValue.sectionRawValue == AppSection.income.rawValue else { return }
                if newValue.phase == .active, needsRootSnapshotRefresh {
                    scheduleRootSnapshotRefresh(reason: "tabActivationSettled")
                    scheduleActivationEnrichment(reason: "tabActivationSettled")
                } else if newValue.phase != .active {
                    cancelRootSnapshotRefresh(reason: "tabPhaseChanged")
                    cancelActivationEnrichment()
                }
            }
            .onReceive(commandHub.$sequence) { _ in
                guard commandHub.surface == .income else { return }
                handleCommand(commandHub.latestCommandID)
            }
    }

    private func configuredIncomeView(proxy: GeometryProxy) -> some View {
        baseIncomeView(proxy: proxy)
            .onAppear { viewWidth = proxy.size.width }
            .onChange(of: proxy.size.width) { _, newValue in
                viewWidth = newValue
            }
            .postBoardingTip(
                key: "tip.income.v1",
                title: "Income",
                items: incomeTipItems
            )
            .navigationTitle("Income")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search"
            )
            .searchFocused($searchFocused)
            .toolbar { incomeToolbar }
            .alert("Delete?", isPresented: $showingIncomeDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    pendingIncomeDelete?()
                    pendingIncomeDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingIncomeDelete = nil
                }
            }
            .confirmationDialog(
                shortcutDeletePickerTitle,
                isPresented: $showingShortcutDeletePicker,
                titleVisibility: .visible
            ) {
                ForEach(shortcutDeleteCandidates) { income in
                    Button(shortcutDeleteCandidateLabel(for: income), role: .destructive) {
                        clearShortcutDeletePicker()
                        requestDeleteIncome(income)
                    }
                }
                Button("Cancel", role: .cancel) {
                    clearShortcutDeletePicker()
                }
            } message: {
                Text(shortcutDeletePickerMessage)
            }
    }

    private func baseIncomeView(proxy: GeometryProxy) -> some View {
        incomeListView
    }

    private var incomeListView: some View {
        List {
            calendarSection
            incomeRowsSection
            weekTotalsSection
        }
    }

    @ToolbarContentBuilder
    private var incomeToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    addIncomeSheet = AddIncomeSheet(initialDate: selectedDayStart, initialIsPlanned: false)
                } label: {
                    Label("Add Income", systemImage: "plus")
                }

                Button {
                    showingImportIncomeSheet = true
                } label: {
                    Label("Import Income", systemImage: "tray.and.arrow.down")
                }
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    private func handleContentAppear() {
        hydrateRootSnapshotIfAvailable()
        if hasLoadedRootSnapshot == false {
            rebuildRootSnapshot(reason: "onAppearInitial")
        } else if needsRootSnapshotRefresh {
            scheduleRootSnapshotRefresh(reason: "onAppearRefresh")
        }
        consumePendingShortcutActionIfNeeded()
        scheduleActivationEnrichment(reason: "onAppear")
    }

    private func handleContentDisappear() {
        cancelRootSnapshotRefresh(reason: "onDisappear")
        cancelActivationEnrichment()
        if shouldSyncCommandSurface {
            commandHub.deactivate(.income)
            commandHub.setIncomeDeletionAvailability(canDeleteActual: false, canDeletePlanned: false)
        }
    }

    private var incomeRows: [Income] {
        if shouldUseSnapshotDrivenPresentation {
            return isIncomeSearchActive ? rootSnapshot.incomesSearchedAll : rootSnapshot.incomesForSelectedDay
        }
        return isSearching ? incomesSearchedAll : incomesForSelectedDay
    }

    @ViewBuilder
    private var calendarSection: some View {
        Section {
            MultiMonthCalendarView(
                startMonth: displayedMonth,
                monthCount: calendarMonthCount,
                selectedDate: selectedDate,
                incomePresenceByDay: monthPresence,
                onStepDay: { deltaDays in
                    let cal = CalendarGridHelper.displayCalendar
                    let newDate = cal.date(byAdding: .day, value: deltaDays, to: selectedDate) ?? selectedDate
                    let normalized = cal.startOfDay(for: newDate)
                    selectedDate = normalized
                    displayedMonth = CalendarGridHelper.startOfMonth(for: normalized)
                },
                onJumpToMonthStart: { deltaMonths in
                    let cal = CalendarGridHelper.displayCalendar
                    let targetMonth = CalendarGridHelper.addingMonths(deltaMonths, to: displayedMonth)
                    let monthStart = CalendarGridHelper.startOfMonth(for: targetMonth)
                    selectedDate = cal.startOfDay(for: monthStart)
                    displayedMonth = monthStart
                },
                onJumpToToday: {
                    let cal = CalendarGridHelper.displayCalendar
                    let today = cal.startOfDay(for: Date())
                    selectedDate = today
                    displayedMonth = CalendarGridHelper.startOfMonth(for: today)
                },
                onSelectDate: { tapped in
                    let cal = CalendarGridHelper.displayCalendar
                    selectedDate = cal.startOfDay(for: tapped)
                    displayedMonth = CalendarGridHelper.startOfMonth(for: tapped)
                }
            )
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var incomeRowsSection: some View {
        Section(header: incomeSectionHeader) {
            if incomeRows.isEmpty {
                Text(isIncomeSearchActive ? "No matching income." : "No income for \(CalendarGridHelper.shortDateFormatter.string(from: selectedDayStart)).")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(incomeRows) { income in
                    incomeRowButton(for: income)
                }
            }
        }
    }

    private var incomeSectionHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isIncomeSearchActive ? "Search Results" : "Income")
                .font(.headline)

            Text(isIncomeSearchActive ? "All income entries" : selectedDayTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var weekTotalsSection: some View {
        Section(header: Text("Week Total Income")) {
            WeeklyIncomeTotalsRow(
                plannedTotal: weekPlannedTotal,
                actualTotal: weekActualTotal,
                rangeText: selectedWeekRangeText
            )
        }
    }

    private func incomeRowButton(for income: Income) -> some View {
        Button {
            editingIncome = income
            showingEditIncome = true
        } label: {
            IncomeRowView(income: income)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                requestDeleteIncome(income)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(Color("OffshoreDepth"))
        }
        .swipeActions(edge: .leading) {
            Button {
                editingIncome = income
                showingEditIncome = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(Color("AccentColor"))
        }
    }

    private func buildRootSnapshot() -> IncomeRootSnapshot {
        let incomesForSelectedDay = incomes.filter { income in
            income.date >= selectedDayStart && income.date < selectedDayEnd
        }
        .sorted { $0.date > $1.date }

        let query = SearchQueryParser.parse(searchText)
        let searchedIncomes: [Income]
        if query.isEmpty {
            searchedIncomes = incomes
        } else {
            searchedIncomes = incomes
                .filter { income in
                    if !SearchMatch.matchesDateRange(query, date: income.date) { return false }
                    if !SearchMatch.matchesTextTerms(query, in: [income.source, income.card?.name]) { return false }
                    if !SearchMatch.matchesAmountDigitTerms(query, amounts: [income.amount]) { return false }
                    return true
                }
                .sorted { $0.date > $1.date }
        }

        return IncomeRootSnapshot(
            searchText: searchText,
            monthPresence: incomePresenceByDay(for: displayedMonth, monthCount: calendarMonthCount),
            incomesForSelectedDay: incomesForSelectedDay,
            incomesSearchedAll: searchedIncomes,
            actualIncomesForSelectedDay: incomesForSelectedDay.filter { !$0.isPlanned },
            plannedIncomesForSelectedDay: incomesForSelectedDay.filter { $0.isPlanned },
            weekPlannedTotal: incomes
                .filter { $0.date >= selectedWeekStart && $0.date < selectedWeekEndExclusive && $0.isPlanned }
                .reduce(0) { $0 + $1.amount },
            weekActualTotal: incomes
                .filter { $0.date >= selectedWeekStart && $0.date < selectedWeekEndExclusive && !$0.isPlanned }
                .reduce(0) { $0 + $1.amount }
        )
    }

    private func rebuildRootSnapshot(reason: String) {
        let start = DispatchTime.now().uptimeNanoseconds
        rootSnapshot = buildRootSnapshot()
        detailSnapshotCache.store(rootSnapshot, for: rootSnapshotCacheKey)
        hasLoadedRootSnapshot = true
        needsRootSnapshotRefresh = false
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        TabFlickerDiagnostics.markEvent(
            "incomeRootSnapshotFinished",
            metadata: [
                "reason": reason,
                "elapsedMs": String(format: "%.1f", elapsedMs)
            ]
        )
    }

    private func hydrateRootSnapshotIfAvailable() {
        guard let cached: IncomeRootSnapshot = detailSnapshotCache.snapshot(for: rootSnapshotCacheKey) else {
            return
        }

        rootSnapshot = cached
        hasLoadedRootSnapshot = true
        TabFlickerDiagnostics.markEvent("incomeRootSnapshotHydrated")
    }

    private func scheduleRootSnapshotRefresh(reason: String) {
        cancelRootSnapshotRefresh(reason: "reschedule")
        let activationToken = tabActivationContext.token
        let activationPhase = tabActivationContext.phase
        TabFlickerDiagnostics.markEvent(
            "incomeRootSnapshotScheduled",
            metadata: [
                "reason": reason,
                "phase": activationPhase.rawValue,
                "token": String(activationToken)
            ]
        )

        if activationPhase == .active {
            rebuildRootSnapshot(reason: reason)
            return
        }

        needsRootSnapshotRefresh = true
        rootSnapshotRefreshTask = Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard Task.isCancelled == false else { return }

            await MainActor.run {
                guard tabActivationContext.sectionRawValue == AppSection.income.rawValue,
                      tabActivationContext.phase == .active,
                      tabActivationContext.token == activationToken else {
                    TabFlickerDiagnostics.markEvent(
                        "incomeRootSnapshotCancelled",
                        metadata: [
                            "reason": reason,
                            "cancel": "activationChanged"
                        ]
                    )
                    return
                }

                rebuildRootSnapshot(reason: reason)
            }
        }
    }

    private func cancelRootSnapshotRefresh(reason: String) {
        guard rootSnapshotRefreshTask != nil else { return }
        rootSnapshotRefreshTask?.cancel()
        rootSnapshotRefreshTask = nil
        TabFlickerDiagnostics.markEvent(
            "incomeRootSnapshotCancelled",
            metadata: ["reason": reason]
        )
    }

    private func scheduleActivationEnrichment(reason: String) {
        cancelActivationEnrichment()
        let activationToken = tabActivationContext.token

        activationEnrichmentTask = Task {
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard Task.isCancelled == false else { return }

            await MainActor.run {
                guard tabActivationContext.sectionRawValue == AppSection.income.rawValue,
                      tabActivationContext.phase == .active,
                      tabActivationContext.token == activationToken else {
                    return
                }

                if shouldSyncCommandSurface {
                    commandHub.activate(.income)
                    updateIncomeCommandAvailability()
                }

                if needsRootSnapshotRefresh {
                    scheduleRootSnapshotRefresh(reason: "postSettleEnrichment")
                }

                TabFlickerDiagnostics.markEvent(
                    "incomeActivationEnrichmentFinished",
                    metadata: ["reason": reason]
                )
            }
        }
    }

    private func cancelActivationEnrichment() {
        activationEnrichmentTask?.cancel()
        activationEnrichmentTask = nil
    }

    // MARK: - Actions

    private func openNewActualIncome() {
        addIncomeSheet = AddIncomeSheet(initialDate: selectedDayStart, initialIsPlanned: false)
    }

    private func openNewPlannedIncome() {
        addIncomeSheet = AddIncomeSheet(initialDate: selectedDayStart, initialIsPlanned: true)
    }

    private func deleteActualIncomeFromCommand() {
        handleDeleteShortcut(for: .actual)
    }

    private func deletePlannedIncomeFromCommand() {
        handleDeleteShortcut(for: .planned)
    }

    private func handleCommand(_ commandID: String) {
        switch commandID {
        case AppCommandID.Income.newActual:
            openNewActualIncome()
        case AppCommandID.Income.newPlanned:
            openNewPlannedIncome()
        case AppCommandID.Income.deleteActual:
            deleteActualIncomeFromCommand()
        case AppCommandID.Income.deletePlanned:
            deletePlannedIncomeFromCommand()
        default:
            break
        }
    }

    private func updateIncomeCommandAvailability() {
        commandHub.setIncomeDeletionAvailability(
            canDeleteActual: !actualIncomesForSelectedDay.isEmpty,
            canDeletePlanned: !plannedIncomesForSelectedDay.isEmpty
        )
    }

    private func handleDeleteShortcut(for kind: IncomeDeleteKind) {
        let candidates = deleteCandidates(for: kind)
        guard !candidates.isEmpty else { return }

        if candidates.count == 1 {
            requestDeleteIncome(candidates[0])
            return
        }

        shortcutDeleteKind = kind
        shortcutDeleteCandidates = candidates
        showingShortcutDeletePicker = true
    }

    private func deleteCandidates(for kind: IncomeDeleteKind) -> [Income] {
        incomesForSelectedDay.filter { $0.isPlanned == kind.isPlanned }
    }

    private var shortcutDeletePickerTitle: String {
        if let kind = shortcutDeleteKind {
            return "Delete \(kind.title)"
        }
        return "Delete Income"
    }

    private var shortcutDeletePickerMessage: String {
        if let kind = shortcutDeleteKind {
            return "Select which \(kind.title.lowercased()) entry to delete for \(selectedDayTitle)."
        }
        return "Select which income entry to delete."
    }

    private func shortcutDeleteCandidateLabel(for income: Income) -> String {
        let amount = income.amount.formatted(CurrencyFormatter.currencyStyle())
        return "\(income.source) • \(amount)"
    }

    private func clearShortcutDeletePicker() {
        showingShortcutDeletePicker = false
        shortcutDeleteCandidates = []
        shortcutDeleteKind = nil
    }

    private func requestDeleteIncome(_ income: Income) {
        if confirmBeforeDeleting {
            pendingIncomeDelete = {
                deleteIncome(income)
            }
            showingIncomeDeleteConfirm = true
        } else {
            deleteIncome(income)
        }
    }

    private func deleteIncome(_ income: Income) {
        modelContext.delete(income)
        if editingIncome?.id == income.id {
            showingEditIncome = false
            editingIncome = nil
        }
    }

    private func consumePendingShortcutActionIfNeeded() {
        let pending = pendingShortcutActionRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pending.isEmpty else { return }

        if pending == AppShortcutNavigationStore.PendingAction.openIncomeImportReview.rawValue {
            let clipboard = pendingImportClipboardText.trimmingCharacters(in: .whitespacesAndNewlines)
            shortcutImportClipboardText = clipboard.isEmpty ? nil : clipboard
            showingImportIncomeSheet = true
        } else if pending == AppShortcutNavigationStore.PendingAction.openQuickAddIncome.rawValue {
            addIncomeSheet = AddIncomeSheet(initialDate: selectedDayStart, initialIsPlanned: false)
        }

        pendingShortcutActionRaw = ""
        pendingImportClipboardText = ""
    }
}

// MARK: - Sheet Models

private struct AddIncomeSheet: Identifiable {
    let id = UUID()
    let initialDate: Date
    let initialIsPlanned: Bool
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
            let symbols = CalendarGridHelper.weekdaySymbolsFollowingSystem
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
                let dayKey = CalendarGridHelper.displayCalendar.startOfDay(for: cell.date)
                let presence = incomePresenceByDay[dayKey]

                DayCellView(
                    cell: cell,
                    isSelected: CalendarGridHelper.displayCalendar.isDate(cell.date, inSameDayAs: selectedDate),
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
        "\(CalendarGridHelper.displayCalendar.component(.day, from: cell.date))"
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

    static var displayCalendar: Calendar {
        Calendar.autoupdatingCurrent
    }

    static let monthTitleFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = displayCalendar
        df.locale = .autoupdatingCurrent
        df.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return df
    }()

    static let monthShortFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = displayCalendar
        df.locale = .autoupdatingCurrent
        df.setLocalizedDateFormatFromTemplate("LLL")
        return df
    }()

    static let selectedDayTitleFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = displayCalendar
        df.locale = .autoupdatingCurrent
        df.dateStyle = .full
        df.timeStyle = .none
        return df
    }()

    static let dayAccessibilityFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = displayCalendar
        df.locale = .autoupdatingCurrent
        df.dateStyle = .full
        df.timeStyle = .none
        return df
    }()

    static let shortDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = displayCalendar
        df.locale = .autoupdatingCurrent
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()

    static let rangeDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = displayCalendar
        df.locale = .autoupdatingCurrent
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()

    static var weekdaySymbolsFollowingSystem: [String] {
        displayCalendar.veryShortStandaloneWeekdaySymbols
    }

    struct DayCell: Identifiable, Hashable {
        let id: Date
        let date: Date
        let isInDisplayedMonth: Bool
    }

    static func startOfMonth(for date: Date) -> Date {
        let comps = displayCalendar.dateComponents([.year, .month], from: date)
        return displayCalendar.date(from: comps) ?? date
    }

    static func addingMonths(_ months: Int, to date: Date) -> Date {
        displayCalendar.date(byAdding: .month, value: months, to: date) ?? date
    }

    static func startOfWeek(for date: Date) -> Date {
        let weekday = displayCalendar.component(.weekday, from: date)
        let daysFromFirstWeekday = weekday - displayCalendar.firstWeekday
        return displayCalendar.date(byAdding: .day, value: -daysFromFirstWeekday, to: displayCalendar.startOfDay(for: date)) ?? date
    }

    static func makeMonthGrid(for monthDate: Date) -> [DayCell] {
        let monthStart = startOfMonth(for: monthDate)

        guard
            let firstOfMonth = displayCalendar.date(from: displayCalendar.dateComponents([.year, .month], from: monthStart))
        else {
            return []
        }

        let weekdayOfFirst = displayCalendar.component(.weekday, from: firstOfMonth)
        let leadingDays = (weekdayOfFirst - displayCalendar.firstWeekday + 7) % 7

        let totalCells = 42

        guard let gridStart = displayCalendar.date(byAdding: .day, value: -leadingDays, to: firstOfMonth) else {
            return []
        }

        let displayedMonth = displayCalendar.component(.month, from: firstOfMonth)
        let displayedYear = displayCalendar.component(.year, from: firstOfMonth)

        return (0..<totalCells).compactMap { offset in
            guard let date = displayCalendar.date(byAdding: .day, value: offset, to: gridStart) else {
                return nil
            }

            let cellMonth = displayCalendar.component(.month, from: date)
            let cellYear = displayCalendar.component(.year, from: date)

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
