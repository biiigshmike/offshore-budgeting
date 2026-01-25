//
//  WhatIfScenarioPlannerView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/25/26.
//

import SwiftUI

struct WhatIfScenarioPlannerView: View {

    let workspace: Workspace
    let categories: [Category]
    let incomes: [Income]
    let plannedExpenses: [PlannedExpense]
    let variableExpenses: [VariableExpense]
    let startDate: Date
    let endDate: Date

    // Baseline = “Actual” values per category for this range
    @State private var baselineByCategoryID: [UUID: Double] = [:]

    // Overrides = scenario adjustments (global per workspace)
    @State private var overridesByCategoryID: [UUID: Double] = [:]

    // Scenario values rendered in UI (override ?? baseline)
    @State private var scenarioByCategoryID: [UUID: Double] = [:]

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

    @AppStorage("general_currencyCode")
    private var currencyCode: String = "USD"

    private var store: WhatIfScenarioStore {
        WhatIfScenarioStore(workspaceID: workspace.id)
    }

    private var pinnedScenarioID: UUID? {
        store.loadPinnedGlobalScenarioID()
    }

    private var isPinnedSelection: Bool {
        guard let selectedScenarioID else { return false }
        return pinnedScenarioID == selectedScenarioID
    }

    // MARK: - Derived (baseline totals)

    private var actualIncomeTotal: Double {
        incomes
            .filter { !$0.isPlanned }
            .filter { isInRange($0.date) }
            .reduce(0) { $0 + $1.amount }
    }

    private var plannedExpensesEffectiveTotal: Double {
        plannedExpenses
            .filter { isInRange($0.expenseDate) }
            .reduce(0) { $0 + effectivePlannedExpenseAmount($1) }
    }

    private var variableExpensesTotal: Double {
        variableExpenses
            .filter { isInRange($0.transactionDate) }
            .reduce(0) { $0 + $1.amount }
    }

    private var actualSavings: Double {
        actualIncomeTotal - (plannedExpensesEffectiveTotal + variableExpensesTotal)
    }

    // MARK: - Scenario totals

    private var scenarioTotalSpend: Double {
        categories.reduce(0) { partial, category in
            partial + (scenarioByCategoryID[category.id, default: 0])
        }
    }

    private var scenarioSavings: Double {
        actualIncomeTotal - scenarioTotalSpend
    }

    private var subtitleText: String {
        "\(formattedDate(startDate)) - \(formattedDate(endDate))"
    }

    private var savingsLabel: String {
        scenarioSavings >= 0 ? "Savings" : "Over"
    }

    private var savingsColor: Color {
        scenarioSavings >= 0 ? .green : .red
    }

    private var savingsValueMagnitude: Double {
        scenarioSavings >= 0 ? scenarioSavings : abs(scenarioSavings)
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
        Scenario \(savingsLabel): \(CurrencyFormatter.string(from: savingsValueMagnitude))
        Actual Savings: \(CurrencyFormatter.string(from: actualSavings))

        """

        let lines: [String] = categories.map { c in
            let actual = baselineByCategoryID[c.id, default: 0]
            let planned = scenarioByCategoryID[c.id, default: 0]
            let delta = planned - actual
            let sign = delta >= 0 ? "+" : "-"
            let deltaText = "\(sign)\(CurrencyFormatter.string(from: abs(delta)))"

            return "\(c.name): \(CurrencyFormatter.string(from: planned)) (Actual \(CurrencyFormatter.string(from: actual)), \(deltaText))"
        }

        return header + "\n" + totals + lines.joined(separator: "\n")
    }

    private var exportCSV: String {
        var rows: [String] = ["Category,Scenario,Actual,Delta"]
        rows.append("Scenario \(savingsLabel),\(savingsValueMagnitude),\(actualSavings),\(scenarioSavings - actualSavings)")

        for c in categories {
            let actual = baselineByCategoryID[c.id, default: 0]
            let planned = scenarioByCategoryID[c.id, default: 0]
            let delta = planned - actual
            rows.append("\"\(c.name)\",\(planned),\(actual),\(delta)")
        }

        return rows.joined(separator: "\n")
    }

    // MARK: - Donut slices

    private var donutSlices: [DonutSlice] {
        var slices: [DonutSlice] = categories.compactMap { category in
            let value = scenarioByCategoryID[category.id, default: 0]
            guard value > 0 else { return nil }
            let color = Color(hex: category.hexColor) ?? .secondary
            return DonutSlice(id: category.id, title: category.name, value: value, color: color)
        }

        if savingsValueMagnitude > 0 {
            let role: DonutSliceRole = (scenarioSavings >= 0) ? .savings : .over
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
                .animation(.snappy(duration: 0.25), value: scenarioSavings)

                scenarioMetaRow
                    .listRowSeparator(.hidden)
            }

            Section("Categories") {
                if categories.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No categories yet")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("Create categories first, then come back to plan scenarios.")
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
                            baselineAmount: baselineByCategoryID[category.id, default: 0],
                            amount: bindingForCategory(category.id),
                            step: 10,
                            currencyCode: currencyCode
                        )
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                resetCategoryToBaseline(category.id)
                            } label: {
                                Label("Reset", systemImage: "arrow.counterclockwise")
                            }
                            .tint(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("What If?")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("What If?")
                        .font(.headline)
                    Text(subtitleText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                scenarioMenu
            }

            #if canImport(UIKit)
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }
                    .font(.subheadline.weight(.semibold))
            }
            #endif
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
        .alert("New Scenario", isPresented: $showNewScenarioPrompt) {
            TextField("Name", text: $newScenarioName)
            Button("Create") { createScenario() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Create a named scenario for this workspace.")
        }
        .alert("Rename Scenario", isPresented: $showRenamePrompt) {
            TextField("Name", text: $renameScenarioName)
            Button("Save") { renameScenario() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Rename the current scenario.")
        }
        .alert("Duplicate Scenario", isPresented: $showDuplicatePrompt) {
            TextField("Name", text: $duplicateScenarioName)
            Button("Duplicate") { duplicateScenario() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Make a copy of the current scenario.")
        }
        .confirmationDialog("Delete this scenario?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Scenario", role: .destructive) { deleteScenario() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    // MARK: - Header / Meta

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Scenario • \(selectedScenarioName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(scenarioSavings, format: CurrencyFormatter.currencyStyle())
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(savingsColor)
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Actual Savings")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(actualSavings, format: CurrencyFormatter.currencyStyle())
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(actualSavings >= 0 ? .green : .red)
                }
            }
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

            ShareLink(item: exportText) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
            }
            .accessibilityLabel("Share scenario summary")

            ShareLink(item: exportCSV) {
                Image(systemName: "tablecells")
                    .font(.system(size: 14, weight: .semibold))
            }
            .accessibilityLabel("Share scenario CSV")
        }
        .padding(.vertical, 4)
    }

    private var scenarioMenu: some View {
        Menu {
            Section("Scenarios") {
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
                        store.setPinnedGlobalScenarioID(nil)
                    } label: {
                        Label("Unpin from Home", systemImage: "pin.slash")
                    }
                } else {
                    Button {
                        store.setPinnedGlobalScenarioID(selectedScenarioID)
                    } label: {
                        Label("Pin to Home", systemImage: "pin")
                    }
                }

                Divider()
            }

            Button {
                newScenarioName = "Scenario"
                showNewScenarioPrompt = true
            } label: {
                Label("New Scenario", systemImage: "plus")
            }

            Button {
                duplicateScenarioName = "\(selectedScenarioName) Copy"
                showDuplicatePrompt = true
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
            .disabled(selectedScenarioID == nil)

            Button {
                renameScenarioName = selectedScenarioName
                showRenamePrompt = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .disabled(selectedScenarioID == nil)

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(scenarios.count <= 1 || selectedScenarioID == nil)

        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 16, weight: .semibold))
                .accessibilityLabel("Scenario options")
        }
    }

    // MARK: - Scenario Lifecycle (GLOBAL)

    private func loadEverythingIfNeeded() {
        guard didLoad == false else { return }

        baselineByCategoryID = buildBaselineByCategoryID()

        scenarios = store.listGlobalScenarios()

        if scenarios.isEmpty {
            let created = store.createGlobalScenario(name: "Default", overrides: [:])
            scenarios = store.listGlobalScenarios()
            selectedScenarioID = created.id
            overridesByCategoryID = [:]
            rebuildScenarioFromOverrides(animated: false)
            didLoad = true
            return
        }

        let restored = store.loadSelectedGlobalScenarioID()
        let chosen = restored ?? scenarios.sorted { $0.lastAccessed > $1.lastAccessed }.first?.id

        selectedScenarioID = chosen

        if let chosen {
            loadScenarioIntoUI(id: chosen)
        } else {
            overridesByCategoryID = [:]
            rebuildScenarioFromOverrides(animated: false)
        }

        didLoad = true
    }

    private func loadScenarioIntoUI(id: UUID) {
        let loadedOverrides = store.loadGlobalScenario(scenarioID: id) ?? [:]
        overridesByCategoryID = sanitizeOverrides(loadedOverrides)

        store.setSelectedGlobalScenarioID(id)
        scenarios = store.listGlobalScenarios()

        rebuildScenarioFromOverrides(animated: true)
    }

    private func selectScenario(_ id: UUID) {
        selectedScenarioID = id
    }

    private func createScenario() {
        let created = store.createGlobalScenario(name: newScenarioName, overrides: [:])
        scenarios = store.listGlobalScenarios()
        selectedScenarioID = created.id
        overridesByCategoryID = [:]
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

        scenarios = store.listGlobalScenarios()

        let next = store.loadSelectedGlobalScenarioID()
            ?? scenarios.sorted { $0.lastAccessed > $1.lastAccessed }.first?.id

        selectedScenarioID = next

        if let next {
            loadScenarioIntoUI(id: next)
        } else {
            overridesByCategoryID = [:]
            rebuildScenarioFromOverrides(animated: true)
        }
    }

    // MARK: - Editing / Overrides

    private func resetCategoryToBaseline(_ categoryID: UUID) {
        overridesByCategoryID.removeValue(forKey: categoryID)
        rebuildScenarioFromOverrides(animated: true)
        persistIfReady()
    }

    private func setScenarioValue(_ newValue: Double, for categoryID: UUID) {
        let baseline = baselineByCategoryID[categoryID, default: 0]
        let clamped = max(0, newValue)

        // If it matches baseline, remove override (keeps payload clean)
        if abs(clamped - baseline) < 0.000_1 {
            overridesByCategoryID.removeValue(forKey: categoryID)
        } else {
            overridesByCategoryID[categoryID] = clamped
        }

        rebuildScenarioFromOverrides(animated: false)
        persistIfReady()
    }

    private func rebuildScenarioFromOverrides(animated: Bool) {
        let ids = categories.map { $0.id }
        let rebuilt = store.applyGlobalScenario(
            overrides: overridesByCategoryID,
            baselineByCategoryID: baselineByCategoryID,
            categories: ids
        )

        if animated {
            withAnimation(.snappy(duration: 0.20)) {
                scenarioByCategoryID = rebuilt
            }
        } else {
            scenarioByCategoryID = rebuilt
        }
    }

    private func sanitizeOverrides(_ overrides: [UUID: Double]) -> [UUID: Double] {
        // Keep only keys that still exist, and clamp values
        let validIDs = Set(categories.map { $0.id })
        var cleaned: [UUID: Double] = [:]
        cleaned.reserveCapacity(overrides.count)

        for (id, value) in overrides where validIDs.contains(id) {
            cleaned[id] = max(0, value)
        }

        return cleaned
    }

    private func persistIfReady() {
        guard didLoad, let id = selectedScenarioID else { return }
        store.saveGlobalScenario(overridesByCategoryID, scenarioID: id)
        scenarios = store.listGlobalScenarios()
    }

    // MARK: - Scenario binding

    private func bindingForCategory(_ id: UUID) -> Binding<Double> {
        Binding(
            get: { scenarioByCategoryID[id, default: 0] },
            set: { newValue in
                withAnimation(.snappy(duration: 0.20)) {
                    setScenarioValue(newValue, for: id)
                }
            }
        )
    }

    // MARK: - Baseline builder

    private func buildBaselineByCategoryID() -> [UUID: Double] {
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

            variableByCategoryID[category.id, default: 0] += expense.amount
        }

        var result: [UUID: Double] = [:]
        result.reserveCapacity(categories.count)

        for category in categories {
            let planned = plannedByCategoryID[category.id, default: 0]
            let variable = variableByCategoryID[category.id, default: 0]
            result[category.id] = max(0, planned + variable)
        }

        return result
    }

    // MARK: - Helpers

    private func isInRange(_ date: Date) -> Bool {
        (date >= startDate) && (date <= endDate)
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted))
    }

    private func effectivePlannedExpenseAmount(_ expense: PlannedExpense) -> Double {
        expense.actualAmount > 0 ? describedAsCurrencySafe(expense.actualAmount) : describedAsCurrencySafe(expense.plannedAmount)
    }

    // This keeps behavior stable if any values ever drift negative/NaN.
    private func describedAsCurrencySafe(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return value
    }
}

#if canImport(UIKit)
private extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif
