//
//  WhatIfScenarioPlannerView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/25/26.
//

import SwiftUI
import CoreText

#if canImport(UIKit)
import UIKit
#endif

struct WhatIfScenarioPlannerView: View {
    
    // MARK: - Export sheet routing

    private enum ExportSheetRoute: Identifiable {
        case options
        case share

        var id: String {
            switch self {
            case .options: return "options"
            case .share: return "share"
            }
        }
    }

    @State private var exportSheetRoute: ExportSheetRoute? = nil


    let workspace: Workspace
    let budgets: [Budget]
    let categories: [Category]
    let incomes: [Income]
    let plannedExpenses: [PlannedExpense]
    let variableExpenses: [VariableExpense]
    let savingsEntries: [SavingsLedgerEntry]
    let startDate: Date
    let endDate: Date

    /// If provided, the planner will open with this scenario selected.
    /// Used by Home inline previews to jump straight into a pinned scenario.
    let initialScenarioID: UUID?
    
    @State private var pinnedRefreshTick: Int = 0

    // Baseline = seeded min/max values per category for this range
    @State private var baselineBoundsByCategoryID: [UUID: WhatIfScenarioStore.WhatIfCategoryBounds] = [:]

    // Overrides = scenario min/max adjustments (global per workspace)
    @State private var overridesByCategoryID: [UUID: WhatIfScenarioStore.WhatIfCategoryBounds] = [:]

    // Scenario values rendered in UI (override ?? baseline)
    @State private var scenarioBoundsByCategoryID: [UUID: WhatIfScenarioStore.WhatIfCategoryBounds] = [:]
    @State private var scenarioPlannedIncomeTotal: Double = 0
    @State private var scenarioActualIncomeTotal: Double = 0

    // Global scenario list + selection
    @State private var scenarios: [WhatIfScenarioStore.GlobalScenarioInfo] = []
    @State private var selectedScenarioID: UUID? = nil

    @State private var didLoad: Bool = false

    // Rename / New / Duplicate prompts
    @State private var showNewScenarioPrompt: Bool = false
    @State private var newScenarioName: String = "Scenario"

    @State private var showRenamePrompt: Bool = false
    @State private var renameScenarioName: String = ""

    @State private var showDuplicatePrompt: Bool = false
    @State private var duplicateScenarioName: String = "Copy"

    @State private var showDeleteConfirm: Bool = false

    private var store: WhatIfScenarioStore {
        WhatIfScenarioStore(workspaceID: workspace.id)
    }

    private var isPinnedSelection: Bool {
        _ = pinnedRefreshTick
        guard let selectedScenarioID else { return false }
        return store.isGlobalScenarioPinned(selectedScenarioID)
    }

    // MARK: - Derived (baseline totals)

    private var actualIncomeTotal: Double {
        incomes
            .filter { !$0.isPlanned }
            .filter { isInRange($0.date) }
            .reduce(0) { $0 + describedAsCurrencySafe($1.amount) }
    }

    private var plannedIncomeTotal: Double {
        incomes
            .filter(\.isPlanned)
            .filter { isInRange($0.date) }
            .reduce(0) { $0 + describedAsCurrencySafe($1.amount) }
    }

    private var plannedExpensesEffectiveTotal: Double {
        plannedExpenses
            .filter { isInRange($0.expenseDate) }
            .reduce(0) { $0 + SavingsMathService.plannedBudgetImpactAmount(for: $1) }
    }

    private var variableExpensesTotal: Double {
        variableExpenses
            .filter { isInRange($0.transactionDate) }
            .reduce(0) { $0 + describedAsCurrencySafe(SavingsMathService.variableBudgetImpactAmount(for: $1)) }
    }

    private var actualSavings: Double {
        actualIncomeTotal
            - (plannedExpensesEffectiveTotal + variableExpensesTotal)
            + SavingsMathService.actualSavingsAdjustmentTotal(
                from: savingsEntries,
                startDate: startDate,
                endDate: endDate
            )
    }

    // MARK: - Scenario totals

    private var scenarioMinSpendTotal: Double {
        categories.reduce(0) { partial, category in
            partial + describedAsCurrencySafe(scenarioBoundsByCategoryID[category.id, default: .init(min: 0, max: 0)].min)
        }
    }

    private var scenarioMaxSpendTotal: Double {
        categories.reduce(0) { partial, category in
            partial + describedAsCurrencySafe(scenarioBoundsByCategoryID[category.id, default: .init(min: 0, max: 0)].max)
        }
    }

    private var scenarioSpendTotal: Double {
        categories.reduce(0) { partial, category in
            let bounds = scenarioBoundsByCategoryID[category.id, default: .init(min: 0, max: 0)]
            return partial + describedAsCurrencySafe(bounds.resolvedScenarioSpend(fallback: bounds.midpoint))
        }
    }

    private var actualIncomeOutcomeRange: ClosedRange<Double> {
        (scenarioActualIncomeTotal - scenarioMaxSpendTotal)...(scenarioActualIncomeTotal - scenarioMinSpendTotal)
    }

    private var plannedIncomeOutcomeRange: ClosedRange<Double> {
        (scenarioPlannedIncomeTotal - scenarioMaxSpendTotal)...(scenarioPlannedIncomeTotal - scenarioMinSpendTotal)
    }

    private var scenarioOutcomeForDonut: Double {
        describedAsCurrencySafe(scenarioActualIncomeTotal - scenarioSpendTotal)
    }

    private var subtitleText: String {
        "\(formattedDate(startDate)) - \(formattedDate(endDate))"
    }

    private var savingsLabel: String {
        scenarioOutcomeForDonut >= 0 ? "Savings" : "Over"
    }

    private var savingsColor: Color {
        scenarioOutcomeForDonut >= 0 ? .green : .red
    }

    private var savingsValueMagnitude: Double {
        let magnitude = scenarioOutcomeForDonut >= 0 ? scenarioOutcomeForDonut : abs(scenarioOutcomeForDonut)
        return describedAsCurrencySafe(magnitude)
    }

    private var selectedScenarioName: String {
        guard let id = selectedScenarioID else { return "Scenario" }
        return scenarios.first(where: { $0.id == id })?.name ?? "Scenario"
    }

    // MARK: - Export

    private var exportText: String {
        let header = "What If? • \(workspace.name)\n\(subtitleText)\nScenario: \(selectedScenarioName)\n"
        let totals =
        """
        Outcome (Actual Income): \(formatRange(actualIncomeOutcomeRange))
        Outcome (Planned Income): \(formatRange(plannedIncomeOutcomeRange))
        Actual Savings: \(CurrencyFormatter.string(from: actualSavings))
        Entered Actual Income: \(CurrencyFormatter.string(from: actualIncomeTotal))
        Entered Planned Income: \(CurrencyFormatter.string(from: plannedIncomeTotal))
        Scenario Actual Income: \(CurrencyFormatter.string(from: scenarioActualIncomeTotal))
        Scenario Planned Income: \(CurrencyFormatter.string(from: scenarioPlannedIncomeTotal))

        """

        let lines: [String] = categories.map { c in
            let baseline = baselineBoundsByCategoryID[c.id, default: .init(min: 0, max: 0)]
            let planned = scenarioBoundsByCategoryID[c.id, default: .init(min: 0, max: 0)]
            let plannedScenario = planned.resolvedScenarioSpend(fallback: planned.midpoint)
            let baselineScenario = baseline.resolvedScenarioSpend(fallback: baseline.midpoint)
            return "\(c.name): Min \(CurrencyFormatter.string(from: planned.min)), Max \(CurrencyFormatter.string(from: planned.max)), Scenario \(CurrencyFormatter.string(from: plannedScenario)) (Actual Min \(CurrencyFormatter.string(from: baseline.min)), Actual Max \(CurrencyFormatter.string(from: baseline.max)), Actual Scenario \(CurrencyFormatter.string(from: baselineScenario)))"
        }

        return header + "\n" + totals + lines.joined(separator: "\n")
    }

    private var exportCSV: String {
        var rows: [String] = ["Category Name,Min Amount,Max Amount,Scenario Spend"]

        for c in categories {
            let bounds = scenarioBoundsByCategoryID[c.id, default: .init(min: 0, max: 0)]
            let scenarioSpend = bounds.resolvedScenarioSpend(fallback: bounds.midpoint)
            rows.append("\"\(c.name)\",\(CurrencyFormatter.csvNumberString(from: bounds.min)),\(CurrencyFormatter.csvNumberString(from: bounds.max)),\(CurrencyFormatter.csvNumberString(from: scenarioSpend))")
        }

        rows.append("\"Outcome Actual Income Min\",\(CurrencyFormatter.csvNumberString(from: actualIncomeOutcomeRange.lowerBound))")
        rows.append("\"Outcome Actual Income Max\",\(CurrencyFormatter.csvNumberString(from: actualIncomeOutcomeRange.upperBound))")
        rows.append("\"Outcome Planned Income Min\",\(CurrencyFormatter.csvNumberString(from: plannedIncomeOutcomeRange.lowerBound))")
        rows.append("\"Outcome Planned Income Max\",\(CurrencyFormatter.csvNumberString(from: plannedIncomeOutcomeRange.upperBound))")
        rows.append("\"Entered Actual Income\",\(CurrencyFormatter.csvNumberString(from: actualIncomeTotal))")
        rows.append("\"Entered Planned Income\",\(CurrencyFormatter.csvNumberString(from: plannedIncomeTotal))")
        rows.append("\"Scenario Actual Income\",\(CurrencyFormatter.csvNumberString(from: scenarioActualIncomeTotal))")
        rows.append("\"Scenario Planned Income\",\(CurrencyFormatter.csvNumberString(from: scenarioPlannedIncomeTotal))")
        return rows.joined(separator: "\n")
    }

    // MARK: - Export UI state

    @State private var showExportSheet: Bool = false
    @State private var shareItems: [Any] = []
    @State private var showExportOptions: Bool = false

    // MARK: - Donut slices

    private var donutSlices: [DonutSlice] {
        var slices: [DonutSlice] = categories.compactMap { category in
            let bounds = scenarioBoundsByCategoryID[category.id, default: .init(min: 0, max: 0)]
            let value = describedAsCurrencySafe(bounds.resolvedScenarioSpend(fallback: bounds.midpoint))
            guard value > 0 else { return nil }
            let color = Color(hex: category.hexColor) ?? .secondary
            return DonutSlice(id: category.id, title: category.name, value: value, color: color)
        }

        if savingsValueMagnitude > 0 {
            let role: DonutSliceRole = (scenarioOutcomeForDonut >= 0) ? .savings : .over
            slices.append(
                DonutSlice(
                    title: savingsLabel,
                    value: savingsValueMagnitude,
                    color: savingsColor.opacity(0.85),
                    role: role
                )
            )
        }

        return slices
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    headerBlock
                        .listRowSeparator(.hidden)

                    DonutChartView(
                        slices: donutSlices,
                        innerRadiusRatio: 0.70,
                        centerTitle: savingsLabel,
                        centerValueText: CurrencyFormatter.string(from: savingsValueMagnitude),
                        showsLegend: false
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
                    .listRowSeparator(.hidden)
                    .animation(.snappy(duration: 0.25), value: donutSlices)
                    .animation(.snappy(duration: 0.25), value: scenarioOutcomeForDonut)

                    scenarioMetaRow
                        .listRowSeparator(.hidden)
                }

                Section(String(localized: "homeWidget.income", defaultValue: "Income", comment: "Pinned home widget title for income metrics.")) {
                    VStack(alignment: .leading, spacing: 8) {
                        WhatIfIncomeRowView(
                            baselinePlannedAmount: plannedIncomeTotal,
                            baselineActualAmount: actualIncomeTotal,
                            plannedAmount: scenarioPlannedIncomeBinding,
                            actualAmount: scenarioActualIncomeBinding,
                            currencyCode: CurrencyFormatter.currencyCode
                        )
                    }
                    .padding(.vertical, 4)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            resetIncomeToBaseline()
                        } label: {
                            Label(String(localized: "common.reset", defaultValue: "Reset", comment: "Common action label to reset values."), systemImage: "arrow.counterclockwise")
                        }
                        .tint(.secondary)
                    }
                }

                Section(String(localized: "common.categories", defaultValue: "Categories", comment: "Common section title for categories.")) {
                    if categories.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized: "whatIf.noCategoriesYet", defaultValue: "No categories yet", comment: "Empty-state title when no categories exist for What If planner."))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text(String(localized: "whatIf.createCategoriesFirst", defaultValue: "Create categories first, then come back to plan scenarios.", comment: "Empty-state helper text for What If planner when no categories exist."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 6)
                    } else {
                        ForEach(categories) { category in
                            WhatIfCategoryRowView(
                                categoryName: category.name,
                                categoryHex: category.hexColor,
                                baselineMinAmount: baselineBoundsByCategoryID[category.id, default: .init(min: 0, max: 0)].min,
                                baselineMaxAmount: baselineBoundsByCategoryID[category.id, default: .init(min: 0, max: 0)].max,
                                baselineScenarioSpendAmount: baselineBoundsByCategoryID[category.id, default: .init(min: 0, max: 0)].resolvedScenarioSpend(
                                    fallback: baselineBoundsByCategoryID[category.id, default: .init(min: 0, max: 0)].midpoint
                                ),
                                minAmount: minBindingForCategory(category.id),
                                maxAmount: maxBindingForCategory(category.id),
                                scenarioSpendAmount: scenarioBindingForCategory(category.id),
                                currencyCode: CurrencyFormatter.currencyCode,
                                onEditingBegan: { scrollCategoryIntoView(category.id, with: proxy) }
                            )
                            .id(category.id)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    resetCategoryToBaseline(category.id)
                                } label: {
                                    Label(String(localized: "common.reset", defaultValue: "Reset", comment: "Common action label to reset values."), systemImage: "arrow.counterclockwise")
                                }
                                .tint(.secondary)
                            }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onReceive(pinnedChangePublisher) { _ in
                pinnedRefreshTick += 1
            }
            .listStyle(.insetGrouped)
            .navigationTitle(String(localized: "homeWidget.whatIf", defaultValue: "What If?", comment: "Pinned home widget title for what-if planner."))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(String(localized: "homeWidget.whatIf", defaultValue: "What If?", comment: "Pinned home widget title for what-if planner."))
                            .font(.headline)
                        Text(subtitleText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    scenarioMenu
                }

            }
            #if canImport(UIKit)
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { _ in hideKeyboard() }
            )
            #endif
            .onAppear {
                loadEverythingIfNeeded()
            }
            .onChange(of: selectedScenarioID) { _, newValue in
                guard didLoad, let id = newValue else { return }
                loadScenarioIntoUI(id: id)
            }
            .alert(String(localized: "whatIf.alert.newScenarioTitle", defaultValue: "New Scenario", comment: "Alert title for creating a new What If scenario."), isPresented: $showNewScenarioPrompt) {
                TextField(String(localized: "common.name", defaultValue: "Name", comment: "Common label for a name field."), text: $newScenarioName)
                Button(String(localized: "common.create", defaultValue: "Create", comment: "Common action to create an item.")) { createScenario() }
                Button(String(localized: "common.cancel", defaultValue: "Cancel", comment: "Common cancel action label."), role: .cancel) {}
            } message: {
                Text(String(localized: "whatIf.alert.newScenarioMessage", defaultValue: "Create a named scenario for this workspace.", comment: "Alert message for creating a new What If scenario."))
            }
            .alert(String(localized: "whatIf.alert.renameScenarioTitle", defaultValue: "Rename Scenario", comment: "Alert title for renaming a What If scenario."), isPresented: $showRenamePrompt) {
                TextField(String(localized: "common.name", defaultValue: "Name", comment: "Common label for a name field."), text: $renameScenarioName)
                Button(String(localized: "common.save", defaultValue: "Save", comment: "Common action to save changes.")) { renameScenario() }
                Button(String(localized: "common.cancel", defaultValue: "Cancel", comment: "Common cancel action label."), role: .cancel) {}
            } message: {
                Text(String(localized: "whatIf.alert.renameScenarioMessage", defaultValue: "Rename the current scenario.", comment: "Alert message for renaming a What If scenario."))
            }
            .alert(String(localized: "whatIf.alert.duplicateScenarioTitle", defaultValue: "Duplicate Scenario", comment: "Alert title for duplicating a What If scenario."), isPresented: $showDuplicatePrompt) {
                TextField(String(localized: "common.name", defaultValue: "Name", comment: "Common label for a name field."), text: $duplicateScenarioName)
                Button(String(localized: "common.duplicate", defaultValue: "Duplicate", comment: "Common action label for duplicating.")) { duplicateScenario() }
                Button(String(localized: "common.cancel", defaultValue: "Cancel", comment: "Common cancel action label."), role: .cancel) {}
            } message: {
                Text(String(localized: "whatIf.alert.duplicateScenarioMessage", defaultValue: "Make a copy of the current scenario.", comment: "Alert message for duplicating a What If scenario."))
            }
            .alert(String(localized: "whatIf.alert.deleteScenarioTitle", defaultValue: "Delete this scenario?", comment: "Alert title for deleting a What If scenario."), isPresented: $showDeleteConfirm) {
                Button(String(localized: "whatIf.deleteScenario", defaultValue: "Delete Scenario", comment: "Destructive action label to delete selected scenario."), role: .destructive) { deleteScenario() }
                Button(String(localized: "common.cancel", defaultValue: "Cancel", comment: "Common cancel action label."), role: .cancel) {}
            } message: {
                Text(String(localized: "common.cannotBeUndone", defaultValue: "This cannot be undone.", comment: "Common destructive action warning."))
            }
        }
    }

    // MARK: - Header / Meta

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent(String(localized: "whatIf.scenario", defaultValue: "Scenario", comment: "Label for current scenario in What If header.")) {
                Text(selectedScenarioName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                LabeledContent(String(localized: "homeWidget.income.actualIncome", defaultValue: "Actual Income", comment: "Metric label for actual income.")) {
                    Text(actualIncomeTotal, format: CurrencyFormatter.currencyStyle())
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                LabeledContent(String(localized: "homeWidget.income.plannedIncome", defaultValue: "Planned Income", comment: "Metric label for planned income.")) {
                    Text(plannedIncomeTotal, format: CurrencyFormatter.currencyStyle())
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                LabeledContent(String(localized: "homeWidget.whatIf.actualSavings", defaultValue: "Actual Savings", comment: "Headline label for actual savings in What If tile.")) {
                    Text(actualSavings, format: CurrencyFormatter.currencyStyle())
                        .font(.body.weight(.semibold))
                        .foregroundStyle(actualSavings >= 0 ? .green : .red)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .contain)
        }
        .padding(.vertical, 6)
    }

    private var scenarioMetaRow: some View {
        HStack(spacing: 10) {
            Image(systemName: isPinnedSelection ? "pin.fill" : "doc.text")
                .foregroundStyle(isPinnedSelection ? .primary : .secondary)
                .accessibilityHidden(true)

            Text(selectedScenarioName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            Button {
                exportSheetRoute = .options
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
            }
            .accessibilityLabel(String(localized: "common.export", defaultValue: "Export", comment: "Common action label for export."))
        }
        .padding(.vertical, 4)
        .sheet(item: $exportSheetRoute) { route in
            switch route {
            case .options:
                ExportOptionsSheet(
                    onSelect: { format in
                        // Close options first, then open share.
                        exportSheetRoute = nil
                        exportAndShare(format)
                        exportSheetRoute = .share
                    }
                )

            case .share:
                ShareSheet(items: shareItems)
            }
        }
    }

    private struct ExportOptionsSheet: View {
        let onSelect: (ExportFormat) -> Void
        @Environment(\.dismiss) private var dismiss
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        @Environment(\.verticalSizeClass) private var verticalSizeClass

        private var isPhone: Bool {
            #if os(iOS)
            UIDevice.current.userInterfaceIdiom == .phone
            #else
            false
            #endif
        }

        private var useMediumDetent: Bool {
            isPhone
        }

        var body: some View {
            NavigationStack {
                List {
                    Section {
                        Button(String(localized: "export.csv", defaultValue: "Export as CSV", comment: "Export action label for CSV format.")) {
                            dismiss()
                            onSelect(.csv)
                        }

                        Button(String(localized: "export.pdf", defaultValue: "Export as PDF", comment: "Export action label for PDF format.")) {
                            dismiss()
                            onSelect(.pdf)
                        }

                        Button(String(localized: "export.text", defaultValue: "Export as Text", comment: "Export action label for plain text format.")) {
                            dismiss()
                            onSelect(.txt)
                        }
                    } header: {
                        Text(String(localized: "export.chooseFileFormat", defaultValue: "Choose a file format.", comment: "Section header prompting user to choose export format."))
                    }
                }
                .navigationTitle(String(localized: "common.export", defaultValue: "Export", comment: "Common action label for export."))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "common.close", defaultValue: "Close", comment: "Common action label to close a sheet.")) { dismiss() }
                    }
                }
            }
            .presentationDetents(
                useMediumDetent ? [.medium] : [.large]
            )
        }
    }


    private var scenarioMenu: some View {
        Menu {
            Section(String(localized: "whatIf.scenarios", defaultValue: "Scenarios", comment: "Section title listing available What If scenarios.")) {
                ForEach(scenarios) { s in
                    Button {
                        selectScenario(s.id)
                    } label: {
                        if s.id == selectedScenarioID {
                            Label(s.name, systemImage: "checkmark")
                        } else {
                            Text(s.name)
                        }
                    }
                }
            }

            Divider()

            if let selectedScenarioID {
                if isPinnedSelection {
                    Button {
                        store.setGlobalScenarioPinned(selectedScenarioID, isPinned: false)
                    } label: {
                        Label(String(localized: "whatIf.unpinFromHome", defaultValue: "Unpin from Home", comment: "Menu action to unpin selected scenario from Home."), systemImage: "pin.slash")
                    }
                } else {
                    Button {
                        store.setGlobalScenarioPinned(selectedScenarioID, isPinned: true)
                    } label: {
                        Label(String(localized: "whatIf.pinToHome", defaultValue: "Pin to Home", comment: "Menu action to pin selected scenario to Home."), systemImage: "pin")
                    }
                }

                Divider()
            }

            Button {
                newScenarioName = String(localized: "whatIf.scenario", defaultValue: "Scenario", comment: "Default name prefix for What If scenarios.")
                showNewScenarioPrompt = true
            } label: {
                Label(String(localized: "whatIf.newScenario", defaultValue: "New Scenario", comment: "Menu action to create a new What If scenario."), systemImage: "plus")
            }

            Button {
                duplicateScenarioName = "\(selectedScenarioName) Copy"
                showDuplicatePrompt = true
            } label: {
                Label(String(localized: "common.duplicate", defaultValue: "Duplicate", comment: "Common action label for duplicating."), systemImage: "doc.on.doc")
            }
            .disabled(selectedScenarioID == nil)

            Button {
                renameScenarioName = selectedScenarioName
                showRenamePrompt = true
            } label: {
                Label(String(localized: "common.rename", defaultValue: "Rename", comment: "Common action label for renaming."), systemImage: "pencil")
            }
            .tint(Color("AccentColor"))
            .disabled(selectedScenarioID == nil)

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label(String(localized: "common.delete", defaultValue: "Delete", comment: "Common action label for deleting."), systemImage: "trash")
            }
            .tint(Color("OffshoreDepth"))
            .disabled(scenarios.count <= 1 || selectedScenarioID == nil)

        } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityLabel(String(localized: "whatIf.scenarioOptions", defaultValue: "Scenario options", comment: "Accessibility label for scenario options menu."))
        }
    }

    // MARK: - Scenario Lifecycle (GLOBAL)

    private func loadEverythingIfNeeded() {
        guard didLoad == false else { return }

        baselineBoundsByCategoryID = buildBaselineBoundsByCategoryID()

        let defaultScenario = store.ensureDefaultGlobalScenario()
        scenarios = store.listGlobalScenarios()

        let chosen = initialScenarioID ?? defaultScenario.id

        selectedScenarioID = chosen

        if scenarios.contains(where: { $0.id == chosen }) {
            loadScenarioIntoUI(id: chosen)
        } else {
            overridesByCategoryID = [:]
            resetScenarioIncomeToBaseline()
            rebuildScenarioFromOverrides(animated: false)
        }

        didLoad = true
    }

    // MARK: - Export helpers

    private enum ExportFormat {
        case csv
        case pdf
        case txt

        var fileExtension: String {
            switch self {
            case .csv: return "csv"
            case .pdf: return "pdf"
            case .txt: return "txt"
            }
        }
    }

    private func exportAndShare(_ format: ExportFormat) {
        let fileName = sanitizedFileName("WhatIf_\(workspace.name)_\(selectedScenarioName)")

        switch format {
        case .csv:
            guard let url = writeTempFile(data: Data(exportCSV.utf8), fileName: fileName, ext: format.fileExtension) else { return }
            presentShareSheet([url])

        case .txt:
            guard let url = writeTempFile(data: Data(exportText.utf8), fileName: fileName, ext: format.fileExtension) else { return }
            presentShareSheet([url])

        case .pdf:
            guard let data = buildTextOnlyPDFData() else { return }
            guard let url = writeTempFile(data: data, fileName: fileName, ext: format.fileExtension) else { return }
            presentShareSheet([url])
        }
    }

    private func presentShareSheet(_ items: [Any]) {
        shareItems = items
        showExportSheet = true
    }

    private func sanitizedFileName(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let cleaned = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func writeTempFile(data: Data, fileName: String, ext: String) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
            .appendingPathExtension(ext)

        do {
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }

    private func buildTextOnlyPDFData() -> Data? {
        #if canImport(UIKit)
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter @ 72 dpi
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let bodyText = buildPDFText()
        let data = renderer.pdfData { ctx in
            ctx.beginPage()

            let margin: CGFloat = 36
            let rect = CGRect(x: margin, y: margin, width: pageRect.width - (margin * 2), height: pageRect.height - (margin * 2))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.label
            ]

            let attributed = NSAttributedString(string: bodyText, attributes: attrs)
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            let path = CGPath(rect: rect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, attributed.length), path, nil)
            let context = ctx.cgContext
            context.saveGState()
            context.translateBy(x: 0, y: pageRect.height)
            context.scaleBy(x: 1, y: -1)
            CTFrameDraw(frame, context)
            context.restoreGState()
        }

        return data
        #else
        return nil
        #endif
    }

    private func buildPDFText() -> String {
        var lines: [String] = []
        lines.append("What If? • \(workspace.name)")
        lines.append(subtitleText)
        lines.append("Scenario: \(selectedScenarioName)")
        lines.append("Generated: \(AppDateFormat.abbreviatedDateTime(.now))")
        lines.append("")
        lines.append("Outcome (Actual Income): \(formatRange(actualIncomeOutcomeRange))")
        lines.append("Outcome (Planned Income): \(formatRange(plannedIncomeOutcomeRange))")
        lines.append("Entered Actual Income: \(CurrencyFormatter.string(from: actualIncomeTotal))")
        lines.append("Entered Planned Income: \(CurrencyFormatter.string(from: plannedIncomeTotal))")
        lines.append("Scenario Actual Income: \(CurrencyFormatter.string(from: scenarioActualIncomeTotal))")
        lines.append("Scenario Planned Income: \(CurrencyFormatter.string(from: scenarioPlannedIncomeTotal))")
        lines.append("Actual Savings: \(CurrencyFormatter.string(from: actualSavings))")
        lines.append("")
        lines.append("Categories")

        for c in categories {
            let bounds = scenarioBoundsByCategoryID[c.id, default: .init(min: 0, max: 0)]
            let scenarioSpend = bounds.resolvedScenarioSpend(fallback: bounds.midpoint)
            lines.append("• \(c.name): Min \(CurrencyFormatter.string(from: bounds.min)), Max \(CurrencyFormatter.string(from: bounds.max)), Scenario \(CurrencyFormatter.string(from: scenarioSpend))")
        }

        lines.append("")
        lines.append("Scenario Outcome: \(CurrencyFormatter.string(from: scenarioOutcomeForDonut))")
        return lines.joined(separator: "\n")
    }

    private func loadScenarioIntoUI(id: UUID) {
        let loadedOverrides = store.loadGlobalScenario(scenarioID: id) ?? .empty
        overridesByCategoryID = sanitizeOverrides(loadedOverrides.overridesByCategoryID)
        scenarioPlannedIncomeTotal = loadedOverrides.plannedIncomeOverride ?? plannedIncomeTotal
        scenarioActualIncomeTotal = loadedOverrides.actualIncomeOverride ?? actualIncomeTotal

        store.setSelectedGlobalScenarioID(id)
        scenarios = store.listGlobalScenarios()

        rebuildScenarioFromOverrides(animated: true)
    }

    private func selectScenario(_ id: UUID) {
        selectedScenarioID = id
    }

    private func createScenario() {
        let created = store.createGlobalScenario(name: newScenarioName, overrides: .empty)
        scenarios = store.listGlobalScenarios()
        selectedScenarioID = created.id
        overridesByCategoryID = [:]
        resetScenarioIncomeToBaseline()
        rebuildScenarioFromOverrides(animated: true)
        didLoad = true
    }

    private func renameScenario() {
        guard let id = selectedScenarioID else { return }
        store.renameGlobalScenario(scenarioID: id, newName: renameScenarioName)
        scenarios = store.listGlobalScenarios()
    }

    private func duplicateScenario() {
        guard let id = selectedScenarioID else { return }
        guard let created = store.duplicateGlobalScenario(
            scenarioID: id,
            newName: duplicateScenarioName
        ) else { return }

        scenarios = store.listGlobalScenarios()
        selectedScenarioID = created.id
        loadScenarioIntoUI(id: created.id)
    }

    private func deleteScenario() {
        guard let id = selectedScenarioID else { return }
        store.deleteGlobalScenario(scenarioID: id)

        _ = store.ensureDefaultGlobalScenario()
        scenarios = store.listGlobalScenarios()

        let next = store.loadSelectedGlobalScenarioID() ?? store.globalDefaultScenarioID()

        selectedScenarioID = next

        if let next {
            loadScenarioIntoUI(id: next)
        } else {
            overridesByCategoryID = [:]
            resetScenarioIncomeToBaseline()
            rebuildScenarioFromOverrides(animated: true)
        }
    }

    // MARK: - Editing / Overrides

    private func resetCategoryToBaseline(_ categoryID: UUID) {
        overridesByCategoryID.removeValue(forKey: categoryID)
        rebuildScenarioFromOverrides(animated: true)
        persistIfReady()
    }

    private func resetIncomeToBaseline() {
        resetScenarioIncomeToBaseline()
        persistIfReady()
    }

    private func setScenarioValues(min newMin: Double, max newMax: Double, scenarioSpend newScenarioSpend: Double, for categoryID: UUID) {
        let baseline = baselineBoundsByCategoryID[categoryID, default: .init(min: 0, max: 0)]
        var candidate = WhatIfScenarioStore.WhatIfCategoryBounds(
            min: newMin,
            max: newMax,
            scenarioSpend: newScenarioSpend
        )
        candidate.normalize()

        // If it matches baseline, remove override (keeps payload clean)
        if candidate == baseline {
            overridesByCategoryID.removeValue(forKey: categoryID)
        } else {
            overridesByCategoryID[categoryID] = candidate
        }

        rebuildScenarioFromOverrides(animated: false)
        persistIfReady()
    }

    private func setScenarioIncome(planned newPlanned: Double, actual newActual: Double) {
        scenarioPlannedIncomeTotal = max(0, CurrencyFormatter.roundedToCurrency(newPlanned))
        scenarioActualIncomeTotal = max(0, CurrencyFormatter.roundedToCurrency(newActual))
        persistIfReady()
    }

    private func rebuildScenarioFromOverrides(animated: Bool) {
        let ids = categories.map { $0.id }
        let rebuilt = store.applyGlobalScenario(
            overrides: overridesByCategoryID,
            baselineByCategoryID: baselineBoundsByCategoryID,
            categories: ids
        )

        if animated {
            withAnimation(.snappy(duration: 0.20)) {
                scenarioBoundsByCategoryID = rebuilt
            }
        } else {
            scenarioBoundsByCategoryID = rebuilt
        }
    }

    private func sanitizeOverrides(_ overrides: [UUID: WhatIfScenarioStore.WhatIfCategoryBounds]) -> [UUID: WhatIfScenarioStore.WhatIfCategoryBounds] {
        // Keep only keys that still exist, and clamp values
        let validIDs = Set(categories.map { $0.id })
        var cleaned: [UUID: WhatIfScenarioStore.WhatIfCategoryBounds] = [:]
        cleaned.reserveCapacity(overrides.count)

        for (id, value) in overrides where validIDs.contains(id) {
            var normalized = value
            normalized.normalize()
            cleaned[id] = normalized
        }

        return cleaned
    }

    private func persistIfReady() {
        guard didLoad, let id = selectedScenarioID else { return }
        store.saveGlobalScenario(currentScenarioOverrides(), scenarioID: id)
        scenarios = store.listGlobalScenarios()
    }

    // MARK: - Scenario binding

    private func minBindingForCategory(_ id: UUID) -> Binding<Double> {
        Binding(
            get: { scenarioBoundsByCategoryID[id, default: .init(min: 0, max: 0)].min },
            set: { newValue in
                withAnimation(.snappy(duration: 0.20)) {
                    let bounds = scenarioBoundsByCategoryID[id, default: .init(min: 0, max: 0)]
                    let currentMax = scenarioBoundsByCategoryID[id, default: .init(min: 0, max: 0)].max
                    let currentScenario = bounds.resolvedScenarioSpend(fallback: bounds.midpoint)
                    setScenarioValues(min: newValue, max: currentMax, scenarioSpend: currentScenario, for: id)
                }
            }
        )
    }

    private func maxBindingForCategory(_ id: UUID) -> Binding<Double> {
        Binding(
            get: { scenarioBoundsByCategoryID[id, default: .init(min: 0, max: 0)].max },
            set: { newValue in
                withAnimation(.snappy(duration: 0.20)) {
                    let bounds = scenarioBoundsByCategoryID[id, default: .init(min: 0, max: 0)]
                    let currentMin = bounds.min
                    let currentScenario = bounds.resolvedScenarioSpend(fallback: bounds.midpoint)
                    setScenarioValues(min: currentMin, max: newValue, scenarioSpend: currentScenario, for: id)
                }
            }
        )
    }

    private func scenarioBindingForCategory(_ id: UUID) -> Binding<Double> {
        Binding(
            get: {
                let bounds = scenarioBoundsByCategoryID[id, default: .init(min: 0, max: 0)]
                return bounds.resolvedScenarioSpend(fallback: bounds.midpoint)
            },
            set: { newValue in
                withAnimation(.snappy(duration: 0.20)) {
                    let bounds = scenarioBoundsByCategoryID[id, default: .init(min: 0, max: 0)]
                    setScenarioValues(min: bounds.min, max: bounds.max, scenarioSpend: newValue, for: id)
                }
            }
        )
    }

    private var scenarioPlannedIncomeBinding: Binding<Double> {
        Binding(
            get: { scenarioPlannedIncomeTotal },
            set: { newValue in
                setScenarioIncome(planned: newValue, actual: scenarioActualIncomeTotal)
            }
        )
    }

    private var scenarioActualIncomeBinding: Binding<Double> {
        Binding(
            get: { scenarioActualIncomeTotal },
            set: { newValue in
                setScenarioIncome(planned: scenarioPlannedIncomeTotal, actual: newValue)
            }
        )
    }

    // MARK: - Baseline builder

    private func buildBaselineBoundsByCategoryID() -> [UUID: WhatIfScenarioStore.WhatIfCategoryBounds] {
        let spentByCategoryID = buildBaselineSpendByCategoryID()
        let limitByCategoryID = buildLimitByCategoryID()

        var result: [UUID: WhatIfScenarioStore.WhatIfCategoryBounds] = [:]
        result.reserveCapacity(categories.count)

        for category in categories {
            let spent = spentByCategoryID[category.id, default: 0]
            let limit = limitByCategoryID[category.id]
            let minValue = limit?.minAmount ?? spent
            let maxValue = limit?.maxAmount ?? spent
            result[category.id] = .init(min: minValue, max: maxValue, scenarioSpend: spent)
        }

        return result
    }

    private func buildBaselineSpendByCategoryID() -> [UUID: Double] {
        var plannedByCategoryID: [UUID: Double] = [:]
        var variableByCategoryID: [UUID: Double] = [:]

        for expense in plannedExpenses {
            guard
                isInRange(expense.expenseDate),
                let category = expense.category
            else { continue }

            let effective = effectivePlannedExpenseAmount(expense)
            plannedByCategoryID[category.id, default: 0] += effective
        }

        for expense in variableExpenses {
            guard
                isInRange(expense.transactionDate),
                let category = expense.category
            else { continue }

            variableByCategoryID[category.id, default: 0] += expense.ledgerSignedAmount()
        }

        var result: [UUID: Double] = [:]
        result.reserveCapacity(categories.count)

        for category in categories {
            let planned = plannedByCategoryID[category.id, default: 0]
            let variable = variableByCategoryID[category.id, default: 0]
            result[category.id] = max(0, CurrencyFormatter.roundedToCurrency(planned + variable))
        }

        return result
    }

    private func buildLimitByCategoryID() -> [UUID: BudgetCategoryLimit] {
        let range = DateRange(start: startDate, end: endDate, calendar: .current)
        let activeBudget = BudgetRangeOverlap.pickActiveBudget(from: budgets, for: range, calendar: .current)
        let limits = activeBudget?.categoryLimits ?? []

        var lookup: [UUID: BudgetCategoryLimit] = [:]
        lookup.reserveCapacity(limits.count)
        for limit in limits {
            guard let category = limit.category else { continue }
            lookup[category.id] = limit
        }
        return lookup
    }

    // MARK: - Helpers

    private func isInRange(_ date: Date) -> Bool {
        (date >= startDate) && (date <= endDate)
    }

    private func formattedDate(_ date: Date) -> String {
        AppDateFormat.abbreviatedDate(date)
    }

    private func effectivePlannedExpenseAmount(_ expense: PlannedExpense) -> Double {
        describedAsCurrencySafe(expense.effectiveAmount())
    }

    private func resetScenarioIncomeToBaseline() {
        scenarioPlannedIncomeTotal = plannedIncomeTotal
        scenarioActualIncomeTotal = actualIncomeTotal
    }

    private func currentScenarioOverrides() -> WhatIfScenarioStore.GlobalScenarioOverrides {
        let plannedOverride = incomeOverrideValue(
            scenarioValue: scenarioPlannedIncomeTotal,
            baselineValue: plannedIncomeTotal
        )
        let actualOverride = incomeOverrideValue(
            scenarioValue: scenarioActualIncomeTotal,
            baselineValue: actualIncomeTotal
        )

        return WhatIfScenarioStore.GlobalScenarioOverrides(
            overridesByCategoryID: overridesByCategoryID,
            plannedIncomeOverride: plannedOverride,
            actualIncomeOverride: actualOverride
        )
    }

    private func incomeOverrideValue(scenarioValue: Double, baselineValue: Double) -> Double? {
        let roundedScenario = CurrencyFormatter.roundedToCurrency(max(0, scenarioValue))
        let roundedBaseline = CurrencyFormatter.roundedToCurrency(max(0, baselineValue))
        return abs(roundedScenario - roundedBaseline) < 0.000_1 ? nil : roundedScenario
    }

    // This keeps behavior stable if any values ever drift negative/NaN.
    private func describedAsCurrencySafe(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return value
    }

    private func formatRange(_ range: ClosedRange<Double>) -> String {
        if abs(range.lowerBound - range.upperBound) < 0.000_1 {
            return CurrencyFormatter.string(from: range.lowerBound)
        }

        return "\(CurrencyFormatter.string(from: range.lowerBound)) - \(CurrencyFormatter.string(from: range.upperBound))"
    }

    private func scrollCategoryIntoView(_ categoryID: UUID, with proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.20)) {
            proxy.scrollTo(categoryID, anchor: .center)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeOut(duration: 0.20)) {
                proxy.scrollTo(categoryID, anchor: .center)
            }
        }
    }
    
    private var pinnedChangePublisher: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(
            for: WhatIfScenarioStore.pinnedGlobalScenariosDidChangeName(workspaceID: workspace.id)
        )
    }

}

#if canImport(UIKit)
private extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No-op
    }
}
#endif
