import SwiftUI
import SwiftData

struct PresetDetailView: View, Equatable {
    let workspace: Workspace
    let preset: Preset
    private let workspaceID: UUID
    private let presetID: UUID

    // Parent refreshes must not replace this destination's query configuration.
    // Its own state, model observations, and queries still update normally.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.workspaceID == rhs.workspaceID && lhs.presetID == rhs.presetID
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var referenceDate = Date.now

    @Query private var expenses: [PlannedExpense]
    @Query private var budgets: [Budget]
    @AppStorage("general_hideFuturePlannedExpenses") private var hideFuture = false
    @AppStorage("general_excludeFuturePlannedExpensesFromCalculations") private var excludeFuture = false
    @State private var grouping: BudgetingPeriod
    @State private var hasInitializedRange = false
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var showingLinkedBudgets = false
    @State private var modal: Modal?

    private enum Modal: Identifiable {
        case preset, expense(PlannedExpense), help
        var id: String {
            switch self {
            case .preset: "preset"
            case .expense(let expense): "expense-\(expense.id)"
            case .help: "help"
            }
        }
    }

    init(workspace: Workspace, preset: Preset) {
        self.workspace = workspace
        self.preset = preset
        self.workspaceID = workspace.id
        self.presetID = preset.id
        let period = BudgetingPeriod(rawValue: UserDefaults.standard.string(forKey: "general_defaultBudgetingPeriod") ?? "") ?? .monthly
        _grouping = State(initialValue: period)
        let dates = PresetDetailCalculator.initialRange(
            workspaceID: workspace.id, presetID: preset.id, occurrences: [], grouping: period
        )
        _startDate = State(initialValue: Calendar.current.startOfDay(for: min(dates.start, dates.end)))
        _endDate = State(initialValue: Calendar.current.startOfDay(for: max(dates.start, dates.end)))
        let workspaceID = workspace.id
        let presetID = preset.id
        _expenses = Query(filter: #Predicate<PlannedExpense> {
            $0.workspace?.id == workspaceID && $0.sourcePresetID == presetID
        }, sort: [SortDescriptor(\PlannedExpense.expenseDate, order: .reverse)])
        _budgets = Query(filter: #Predicate<Budget> { $0.workspace?.id == workspaceID },
                         sort: [SortDescriptor(\Budget.startDate, order: .reverse)])
    }

    private var linkedBudgets: [Budget] {
        budgets.filter { budget in
            (budget.presetLinks ?? []).contains { $0.preset?.id == preset.id }
        }
    }

    private var occurrenceSnapshots: [PresetDetailCalculator.Occurrence] {
        expenses.map {
            .init(id: $0.id, workspaceID: $0.workspace?.id, sourcePresetID: $0.sourcePresetID,
                  sourceBudgetID: $0.sourceBudgetID, date: $0.expenseDate,
                  plannedAmount: $0.plannedAmount, actualAmount: $0.actualAmount)
        }
    }

    private func initializeHistoryRangeIfNeeded() {
        guard !hasInitializedRange else { return }
        let dates = PresetDetailCalculator.initialRange(
            workspaceID: workspaceID, presetID: presetID,
            occurrences: occurrenceSnapshots, grouping: grouping, now: referenceDate
        )
        startDate = dates.start
        endDate = dates.end
        hasInitializedRange = true
    }

    private func result(now: Date) -> PresetDetailCalculator.Result {
        PresetDetailCalculator.calculate(
            workspaceID: workspaceID, presetID: presetID, occurrences: occurrenceSnapshots,
            startDate: startDate, endDate: endDate, grouping: grouping,
            hideFuturePlanned: hideFuture, excludeFuturePlanned: excludeFuture,
            currencyCode: CurrencyFormatter.currencyCode, now: now
        )
    }

    var body: some View {
        content(now: referenceDate)
            .modifier(DateRangeNavigationHeader(
                title: preset.title,
                startDate: startDate,
                endDate: endDate
            ))
            .onAppear { initializeHistoryRangeIfNeeded() }
            .task { await refreshAtDayBoundary() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { referenceDate = .now }
            }
    }

    // Keep the List at the navigation root for native large-title scrolling.
    // Assumptions change only at a calendar-day boundary, not every minute.
    private func refreshAtDayBoundary() async {
        referenceDate = .now
        while !Task.isCancelled {
            let calendar = Calendar.current
            let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))
                ?? Date.now.addingTimeInterval(86_400)
            do {
                try await Task.sleep(for: .seconds(max(1, nextDay.timeIntervalSinceNow)))
            } catch {
                return
            }
            referenceDate = .now
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let derived = result(now: now)
        let expensesByID = Dictionary(expenses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let budgetsByID = Dictionary(budgets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        List {
            summarySection
            Section {
                PresetDetailTrendChart(periods: derived.periods, grouping: grouping)
            } header: {
                Text("Planned vs. Effective")
            } footer: {
                Text("Once an expense date passes, a blank actual counts as planned. Today’s and future blanks stay pending.")
            }
            metricsSection(derived)
            Section {
                if derived.history.isEmpty {
                    ContentUnavailableView("No Occurrences", systemImage: "calendar",
                        description: Text("No planned expenses match these dates and visibility settings."))
                }
                ForEach(derived.history) { occurrence in
                    if let expense = expensesByID[occurrence.id] {
                        Button { modal = .expense(expense) } label: {
                            PresetOccurrenceRow(
                                occurrence: occurrence,
                                budgetName: occurrence.sourceBudgetID.flatMap { budgetsByID[$0]?.name },
                                now: now
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Edit planned expense")
                        .accessibilityIdentifier("presetDetail.history.\(occurrence.id)")
                    }
                }
            } header: {
                Text("Occurrence History")
            } footer: {
                Text("History reflects surviving expense records, not a log of changes to this preset. Future visibility follows your planned expense settings.")
            }
            Section {
                DisclosureGroup("Linked Budgets (\(linkedBudgets.count))", isExpanded: $showingLinkedBudgets) {
                    if linkedBudgets.isEmpty {
                        Text("No linked budgets").foregroundStyle(.secondary)
                    }
                    ForEach(linkedBudgets) { budget in
                        NavigationLink {
                            BudgetDetailView(workspace: workspace, budget: budget)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(budget.name)
                                Text("\(AppDateFormat.abbreviatedDate(budget.startDate)) – \(AppDateFormat.abbreviatedDate(budget.endDate))")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .accessibilityIdentifier("presetDetail.linkedBudgets")
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                DateRangeToolbarControls(startDate: startDate, endDate: endDate, onApply: applyDates) {
                    let dates = $0.makeRange()
                    applyDates(dates.start, dates.end)
                }
            }
            if #available(iOS 26.0, macCatalyst 26.0, *) {
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Edit", systemImage: "pencil") { modal = .preset }
                    .accessibilityIdentifier("presetDetail.edit")
            }
        }
        .appSheet(item: $modal) { route in
            switch route {
            case .preset:
                NavigationStack { EditPresetView(workspace: workspace, preset: preset) }
            case .expense(let expense):
                NavigationStack { EditPlannedExpenseView(workspace: workspace, plannedExpense: expense) }
            case .help:
                FinancialCalculationHelpView(sections: calculationSections(derived), dateRange: dateRangeText)
            }
        }
    }

    private var summarySection: some View {
        Section("Preset") {
            PresetRowView(preset: preset, assignedBudgetsCount: linkedBudgets.count)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(summaryAccent)
                        .frame(width: 3)
                        .padding(.vertical, 8)
                        .offset(x: -10)
                        .accessibilityHidden(true)
                }
            LabeledContent("Card", value: preset.defaultCard.flatMap {
                $0.workspace?.id == workspace.id ? $0.name : nil
            } ?? String(localized: "Card Unassigned"))
            LabeledContent("Category", value: preset.defaultCategory.flatMap {
                $0.workspace?.id == workspace.id ? $0.name : nil
            } ?? String(localized: "Uncategorized"))
            LabeledContent("Status", value: preset.isArchived ? String(localized: "Archived") : String(localized: "Active"))
        }
    }

    private var summaryAccent: LinearGradient {
        let card = preset.defaultCard.flatMap { $0.workspace?.id == workspace.id ? $0 : nil }
        let theme = CardThemeOption(rawValue: card?.theme ?? "") ?? .charcoal
        let cardColor = CardThemePalette.colors(for: theme).first ?? .secondary
        let categoryColor = preset.defaultCategory.flatMap {
            $0.workspace?.id == workspace.id ? Color(hex: $0.hexColor) : nil
        } ?? cardColor
        return LinearGradient(colors: [cardColor, categoryColor], startPoint: .top, endPoint: .bottom)
    }

    private func metricsSection(_ result: PresetDetailCalculator.Result) -> some View {
        Section {
            amountRow("Average Effective", amount: result.averageEffectiveAmount)
                .accessibilityIdentifier("presetDetail.averageEffective")
            amountRow("Total Variance", amount: result.includedCount > 0 ? result.totalVariance : nil)
                .accessibilityIdentifier("presetDetail.totalVariance")
            let countsLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            countsLayout {
                planCounts(result)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Higher: \(result.abovePlanCount). As Expected: \(result.onPlanCount). Lower: \(result.belowPlanCount)."))
            .accessibilityIdentifier("presetDetail.planCounts")
        } header: {
            Text("Results")
        } footer: {
            Button("How is this calculated?", systemImage: "info.circle") { modal = .help }
                .font(.subheadline)
        }
    }

    @ViewBuilder
    private func planCounts(_ result: PresetDetailCalculator.Result) -> some View {
        planCount(Text("Higher \(countValue(result.abovePlanCount))"))
        planCount(Text("As Expected \(countValue(result.onPlanCount))"))
        planCount(Text("Lower \(countValue(result.belowPlanCount))"))
    }

    private func countValue(_ count: Int) -> Text {
        Text(AppNumberFormat.integer(count))
            .foregroundStyle(.secondary)
    }

    private func planCount(_ text: Text) -> some View {
        text
            .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .center)
    }

    private func amountRow(_ title: LocalizedStringKey, amount: Double?) -> some View {
        LabeledContent(title) {
            if let amount {
                Text(amount, format: CurrencyFormatter.currencyStyle())
            } else {
                Text("Not available").foregroundStyle(.secondary)
            }
        }
    }

    private var dateRangeText: String {
        "\(AppDateFormat.abbreviatedDate(startDate)) – \(AppDateFormat.abbreviatedDate(endDate))"
    }

    private func applyDates(_ start: Date, _ end: Date) {
        hasInitializedRange = true
        startDate = Calendar.current.startOfDay(for: min(start, end))
        endDate = Calendar.current.startOfDay(for: max(start, end))
    }

    private func calculationSections(_ result: PresetDetailCalculator.Result) -> [FinancialCalculationSection] {
        [.init(id: "preset-variance", title: "Effective Variance",
               explanation: "An actual amount greater than zero takes priority. Once the planned expense date has passed, a blank actual is assumed to match its planned amount. Today’s and future blanks remain pending. No actual amounts are written to your records.",
               rows: [
                .init(id: "effective", title: "Effective", amount: result.effectiveTotal),
                .init(id: "planned", title: "Planned", amount: -result.plannedTotal),
                .init(id: "variance", title: "Total Variance", amount: result.totalVariance, isTotal: true)
               ], notes: [
                "Amounts are gross costs before allocation splits or savings offsets. Separate occurrences from overlapping budgets are counted separately.",
                "Variance is effective amount minus the occurrence’s stored planned amount, not the preset’s current amount. Averages and period comparisons include recorded and assumed occurrences. Averages are per occurrence, not per chart period. Future visibility and calculation settings apply independently.",
                "Above, below, and on-plan counts compare amounts at the selected currency’s precision."
               ])]
    }
}
