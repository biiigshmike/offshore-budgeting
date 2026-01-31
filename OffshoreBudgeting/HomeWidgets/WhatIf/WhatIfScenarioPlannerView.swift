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
    let categories: [Category]
    let incomes: [Income]
    let plannedExpenses: [PlannedExpense]
    let variableExpenses: [VariableExpense]
    let startDate: Date
    let endDate: Date

    /// If provided, the planner will open with this scenario selected.
    /// Used by Home inline previews to jump straight into a pinned scenario.
    let initialScenarioID: UUID?
    
    @State private var pinnedRefreshTick: Int = 0

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
        var rows: [String] = ["Category Name,Amount"]

        for c in categories {
            let amount = scenarioByCategoryID[c.id, default: 0]
            rows.append("\"\(c.name)\",\(CurrencyFormatter.csvNumberString(from: amount))")
        }

        rows.append("\"Savings/Remaining\",\(CurrencyFormatter.csvNumberString(from: scenarioSavings))")
        return rows.joined(separator: "\n")
    }

    // MARK: - Export UI state

    @State private var showExportSheet: Bool = false
    @State private var shareItems: [Any] = []
    @State private var showExportOptions: Bool = false

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
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
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
        .onReceive(pinnedChangePublisher) { _ in
            pinnedRefreshTick += 1
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
        .alert("Delete this scenario?", isPresented: $showDeleteConfirm) {
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

            Button {
                exportSheetRoute = .options
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
            }
            .accessibilityLabel("Export")
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
                        Button("Export as CSV") {
                            dismiss()
                            onSelect(.csv)
                        }

                        Button("Export as PDF") {
                            dismiss()
                            onSelect(.pdf)
                        }

                        Button("Export as Text") {
                            dismiss()
                            onSelect(.txt)
                        }
                    } header: {
                        Text("Choose a file format.")
                    }
                }
                .navigationTitle("Export")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
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
                        store.setGlobalScenarioPinned(selectedScenarioID, isPinned: false)
                    } label: {
                        Label("Unpin from Home", systemImage: "pin.slash")
                    }
                } else {
                    Button {
                        store.setGlobalScenarioPinned(selectedScenarioID, isPinned: true)
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
            Image(systemName: "ellipsis")
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
        let candidate = initialScenarioID ?? restored
        let chosen = candidate ?? scenarios.sorted { $0.lastAccessed > $1.lastAccessed }.first?.id

        selectedScenarioID = chosen

        if let chosen {
            loadScenarioIntoUI(id: chosen)
        } else {
            overridesByCategoryID = [:]
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
        lines.append("Generated: \(Date().formatted(date: .abbreviated, time: .shortened))")
        lines.append("")
        lines.append("Scenario \(savingsLabel): \(CurrencyFormatter.string(from: savingsValueMagnitude))")
        lines.append("Actual Savings: \(CurrencyFormatter.string(from: actualSavings))")
        lines.append("")
        lines.append("Categories")

        for c in categories {
            let amount = scenarioByCategoryID[c.id, default: 0]
            lines.append("• \(c.name): \(CurrencyFormatter.string(from: amount))")
        }

        lines.append("")
        lines.append("Savings/Remaining: \(CurrencyFormatter.string(from: scenarioSavings))")
        return lines.joined(separator: "\n")
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
        let clamped = max(0, CurrencyFormatter.roundedToCurrency(newValue))

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
            cleaned[id] = max(0, CurrencyFormatter.roundedToCurrency(value))
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
            result[category.id] = max(0, CurrencyFormatter.roundedToCurrency(planned + variable))
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
        describedAsCurrencySafe(expense.effectiveAmount())
    }

    // This keeps behavior stable if any values ever drift negative/NaN.
    private func describedAsCurrencySafe(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return value
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
