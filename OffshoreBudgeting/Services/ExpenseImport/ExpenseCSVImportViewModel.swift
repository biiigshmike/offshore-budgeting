//
//  ExpenseCSVImportViewModel.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/25/26.
//

import Foundation
import SwiftData
import Combine
import UniformTypeIdentifiers

@MainActor
final class ExpenseCSVImportViewModel: ObservableObject {

    enum ImportMode: Equatable {
        case cardTransactions
        case incomeOnly
    }

    // MARK: - Tuning

    /// Duplicate window for matching already-entered expenses and planned expenses.
    /// Keep relatively tight (±3 days) to avoid false positives while handling “clearing” delays.
    private let duplicateDayWindow: Int = 3

    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private enum ImportDocumentKind {
        case csv
        case pdf
        case image
        case unsupported
    }

    private enum ImportLoadError: LocalizedError {
        case unsupportedFileType
        case missingCardForCardTransactions
        case noIncomeRowsFound

        var errorDescription: String? {
            switch self {
            case .unsupportedFileType:
                return "Unsupported file type. Choose a CSV, PDF, or image."
            case .missingCardForCardTransactions:
                return "No card was selected for this import."
            case .noIncomeRowsFound:
                return "No income rows were found in this file."
            }
        }
    }

    let mode: ImportMode

    @Published var state: State = .idle
    @Published private(set) var rows: [ExpenseCSVImportRow] = []
    @Published private(set) var categories: [Category] = []
    @Published private(set) var allocationAccounts: [AllocationAccount] = []

    // Option 1 memory dictionary keyed by merchantKey.
    private var learnedRules: [String: ImportMerchantRule] = [:]

    private var existingExpenses: [VariableExpense] = []
    private var existingPlannedExpenses: [PlannedExpense] = []
    private var existingIncomes: [Income] = []

    init(mode: ImportMode = .cardTransactions) {
        self.mode = mode
    }

    // MARK: - Grouped rows

    var blockedRows: [ExpenseCSVImportRow] { rows.filter { $0.isBlocked }.sorted { $0.sourceLine < $1.sourceLine } }
    var readyRows: [ExpenseCSVImportRow] { rows.filter { !$0.isBlocked && $0.bucket == .ready }.sorted { $0.sourceLine < $1.sourceLine } }
    var possibleMatchRows: [ExpenseCSVImportRow] { rows.filter { !$0.isBlocked && $0.bucket == .possibleMatch }.sorted { $0.sourceLine < $1.sourceLine } }
    var paymentRows: [ExpenseCSVImportRow] { rows.filter { !$0.isBlocked && $0.bucket == .payment }.sorted { $0.sourceLine < $1.sourceLine } }
    var possibleDuplicateRows: [ExpenseCSVImportRow] { rows.filter { !$0.isBlocked && $0.bucket == .possibleDuplicate }.sorted { $0.sourceLine < $1.sourceLine } }
    var needsMoreDataRows: [ExpenseCSVImportRow] { rows.filter { !$0.isBlocked && $0.bucket == .needsMoreData }.sorted { $0.sourceLine < $1.sourceLine } }

    var canCommit: Bool {
        rows.contains { !$0.isBlocked && $0.includeInImport && !$0.isMissingRequiredData }
    }

    var commitSummaryText: String {
        let included = rows.filter { $0.includeInImport }
        let expCount = included.filter { $0.kind == .expense && !$0.isMissingRequiredData }.count
        let incCount = included.filter { $0.kind == .income && !$0.isMissingRequiredData }.count
        let blockedCount = blockedRows.count

        switch mode {
        case .cardTransactions:
            return "\(localizedInt(expCount)) expenses, \(localizedInt(incCount)) incomes will be imported."
        case .incomeOnly:
            if blockedCount > 0 {
                return "\(localizedInt(incCount)) incomes will be imported. \(localizedInt(blockedCount)) expense rows were skipped."
            }
            return "\(localizedInt(incCount)) incomes will be imported."
        }
    }

    private func localizedInt(_ value: Int) -> String {
        AppNumberFormat.integer(value)
    }

    // MARK: - Public

    func prepare(workspace: Workspace, modelContext: ModelContext) {
        // Categories
        let cats = (workspace.categories ?? [])
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        categories = cats

        let accounts = (workspace.allocationAccounts ?? [])
            .filter { !$0.isArchived }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        allocationAccounts = accounts

        // Learned rules (Option 1)
        learnedRules = ImportLearningStore.fetchRules(for: workspace, modelContext: modelContext)
    }

    func load(
        url: URL,
        workspace: Workspace,
        card: Card?,
        modelContext: ModelContext,
        referenceDate: Date? = nil
    ) {
        state = .loading

        do {
            switch mode {
            case .cardTransactions:
                guard let card else {
                    throw ImportLoadError.missingCardForCardTransactions
                }
                existingExpenses = card.variableExpenses ?? []
                existingPlannedExpenses = card.plannedExpenses ?? []
                existingIncomes = card.incomes ?? []

            case .incomeOnly:
                existingExpenses = []
                existingPlannedExpenses = []
                existingIncomes = workspace.incomes ?? []
            }

            let parsed = try parseImportedDocument(url: url, referenceDate: referenceDate)
            let mapped = ExpenseCSVImportMapper.map(
                csv: parsed,
                categories: categories,
                existingExpenses: existingExpenses,
                existingPlannedExpenses: existingPlannedExpenses,
                existingIncomes: existingIncomes,
                learnedRules: learnedRules
            )
            let adjusted = Self.applyImportModeRules(mapped, mode: mode)
            if mode == .incomeOnly && !adjusted.contains(where: { !$0.isBlocked && $0.kind == .income }) {
                throw ImportLoadError.noIncomeRowsFound
            }
            rows = adjusted
            state = .loaded
        } catch {
            state = .failed(errorMessage(for: error))
        }
    }

    func loadClipboard(
        text: String,
        workspace: Workspace,
        card: Card?,
        modelContext: ModelContext,
        referenceDate: Date? = nil
    ) {
        state = .loading

        do {
            switch mode {
            case .cardTransactions:
                guard let card else {
                    throw ImportLoadError.missingCardForCardTransactions
                }
                existingExpenses = card.variableExpenses ?? []
                existingPlannedExpenses = card.plannedExpenses ?? []
                existingIncomes = card.incomes ?? []

            case .incomeOnly:
                existingExpenses = []
                existingPlannedExpenses = []
                existingIncomes = workspace.incomes ?? []
            }

            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                throw ShortcutImportPreviewError.emptyClipboard
            }

            let parsed: ParsedCSV
            if let csvParsed = try parseAsCSVIfPossible(from: normalized) {
                parsed = csvParsed
            } else {
                let lines = normalized
                    .split(whereSeparator: \.isNewline)
                    .map(String.init)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                guard !lines.isEmpty else {
                    throw ShortcutImportPreviewError.emptyClipboard
                }

                parsed = try ExpenseImageImportParser.parse(
                    recognizedLines: lines,
                    referenceDate: referenceDate ?? .now
                )
            }

            let mapped = ExpenseCSVImportMapper.map(
                csv: parsed,
                categories: categories,
                existingExpenses: existingExpenses,
                existingPlannedExpenses: existingPlannedExpenses,
                existingIncomes: existingIncomes,
                learnedRules: learnedRules
            )
            let adjusted = Self.applyImportModeRules(mapped, mode: mode)
            if mode == .incomeOnly && !adjusted.contains(where: { !$0.isBlocked && $0.kind == .income }) {
                throw ImportLoadError.noIncomeRowsFound
            }

            rows = adjusted
            state = .loaded
        } catch {
            state = .failed(errorMessage(for: error))
        }
    }

    func toggleInclude(rowID: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == rowID }) else { return }
        if rows[idx].isBlocked {
            rows[idx].includeInImport = false
            return
        }

        // If the row is missing required data, do not allow checking.
        if rows[idx].finalMerchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rows[idx].includeInImport = false
            return
        }
        if rows[idx].kind == .expense, rows[idx].selectedCategory == nil {
            rows[idx].includeInImport = false
            return
        }

        rows[idx].includeInImport.toggle()
    }

    func setCategory(rowID: UUID, category: Category?) {
        guard let idx = rows.firstIndex(where: { $0.id == rowID }) else { return }
        rows[idx].selectedCategory = category

        // If they manually set a category in Possible Matches, allow them to include.
        if rows[idx].bucket == .possibleMatch || rows[idx].bucket == .possibleDuplicate {
            // stay unchecked unless user checks it
        }

        // Recompute duplicate hint since category can be used as a fallback signal.
        let normalized = MerchantNormalizer.normalizeKey(rows[idx].finalMerchant)
        if rows[idx].kind == .expense {
            rows[idx].isDuplicateHint = looksLikeDuplicateExpense(
                date: rows[idx].finalDate,
                amount: rows[idx].finalAmount,
                merchantKey: normalized,
                categoryID: rows[idx].selectedCategory?.id
            )
        } else {
            rows[idx].isDuplicateHint = looksLikeDuplicateIncome(date: rows[idx].finalDate, amount: rows[idx].finalAmount, merchantKey: normalized)
        }

        rows[idx].recomputeBucket()
    }

    func setMerchant(rowID: UUID, merchant: String) {
        guard let idx = rows.firstIndex(where: { $0.id == rowID }) else { return }

        rows[idx].finalMerchant = merchant

        // Recompute duplicate hint based on the edited merchant.
        let normalized = MerchantNormalizer.normalizeKey(merchant)
        if rows[idx].kind == .expense {
            rows[idx].isDuplicateHint = looksLikeDuplicateExpense(
                date: rows[idx].finalDate,
                amount: rows[idx].finalAmount,
                merchantKey: normalized,
                categoryID: rows[idx].selectedCategory?.id
            )
        } else {
            rows[idx].isDuplicateHint = looksLikeDuplicateIncome(date: rows[idx].finalDate, amount: rows[idx].finalAmount, merchantKey: normalized)
        }

        rows[idx].recomputeBucket()
    }

    func setDate(rowID: UUID, date: Date) {
        guard let idx = rows.firstIndex(where: { $0.id == rowID }) else { return }
        rows[idx].finalDate = Calendar.current.startOfDay(for: date)

        let normalized = MerchantNormalizer.normalizeKey(rows[idx].finalMerchant)
        if rows[idx].kind == .expense {
            rows[idx].isDuplicateHint = looksLikeDuplicateExpense(
                date: rows[idx].finalDate,
                amount: rows[idx].finalAmount,
                merchantKey: normalized,
                categoryID: rows[idx].selectedCategory?.id
            )
        } else {
            rows[idx].isDuplicateHint = looksLikeDuplicateIncome(
                date: rows[idx].finalDate,
                amount: rows[idx].finalAmount,
                merchantKey: normalized
            )
        }

        rows[idx].recomputeBucket()
    }

    func setKind(rowID: UUID, kind: ExpenseCSVImportKind) {
        if mode == .incomeOnly { return }
        guard let idx = rows.firstIndex(where: { $0.id == rowID }) else { return }
        if rows[idx].kind == kind { return }

        let wasIncluded = rows[idx].includeInImport
        rows[idx].kind = kind

        if kind == .income {
            rows[idx].selectedCategory = nil
            rows[idx].selectedAllocationAccount = nil
            rows[idx].allocationAmountText = ""
            rows[idx].bucket = .payment
        } else {
            if rows[idx].selectedCategory == nil {
                rows[idx].selectedCategory = rows[idx].suggestedCategory
            }
        }

        let normalized = MerchantNormalizer.normalizeKey(rows[idx].finalMerchant)
        if rows[idx].kind == .expense {
            rows[idx].isDuplicateHint = looksLikeDuplicateExpense(
                date: rows[idx].finalDate,
                amount: rows[idx].finalAmount,
                merchantKey: normalized,
                categoryID: rows[idx].selectedCategory?.id
            )
            rows[idx].bucket = bucketForExpenseRow(rows[idx])
        } else {
            rows[idx].isDuplicateHint = looksLikeDuplicateIncome(date: rows[idx].finalDate, amount: rows[idx].finalAmount, merchantKey: normalized)
            rows[idx].bucket = .payment
        }

        let canInclude = !rows[idx].isMissingRequiredData && !rows[idx].isDuplicateHint
        let includeDefault = (rows[idx].bucket == .ready || rows[idx].bucket == .payment)
        rows[idx].includeInImport = (wasIncluded && canInclude) ? true : (includeDefault && canInclude)

        rows[idx].recomputeBucket()
    }

    func toggleRemember(rowID: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == rowID }) else { return }
        if rows[idx].isBlocked { return }
        rows[idx].rememberMapping.toggle()
    }

    func setAllocationAccount(rowID: UUID, account: AllocationAccount?) {
        guard let idx = rows.firstIndex(where: { $0.id == rowID }) else { return }
        rows[idx].selectedAllocationAccount = account
        if account == nil {
            rows[idx].allocationAmountText = ""
        }
    }

    func setAllocationAmount(rowID: UUID, amountText: String) {
        guard let idx = rows.firstIndex(where: { $0.id == rowID }) else { return }
        rows[idx].allocationAmountText = amountText
    }

    func commitImport(workspace: Workspace, card: Card?, modelContext: ModelContext) {
        let importable = rows.filter { !$0.isBlocked && $0.includeInImport && !$0.isMissingRequiredData }

        for row in importable {
            switch row.kind {
            case .expense:
                guard let card else { continue }
                let category = row.selectedCategory
                let exp = VariableExpense(
                    descriptionText: row.finalMerchant,
                    amount: row.finalAmount,
                    transactionDate: row.finalDate,
                    workspace: workspace,
                    card: card,
                    category: category
                )
                modelContext.insert(exp)

                if let account = row.selectedAllocationAccount,
                   let allocationAmount = row.parsedAllocationAmount(cappedTo: row.finalAmount),
                   allocationAmount > 0 {
                    let allocation = ExpenseAllocation(
                        allocatedAmount: allocationAmount,
                        createdAt: .now,
                        updatedAt: .now,
                        workspace: workspace,
                        account: account,
                        expense: exp
                    )
                    modelContext.insert(allocation)
                    exp.allocation = allocation
                }

                if row.rememberMapping {
                    let preferredName = row.finalMerchant.trimmingCharacters(in: .whitespacesAndNewlines)
                    let primaryKey = row.sourceMerchantKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    let secondaryKey = row.descriptionMerchantKey.trimmingCharacters(in: .whitespacesAndNewlines)

                    if !primaryKey.isEmpty {
                        ImportLearningStore.upsertRule(
                            merchantKey: primaryKey,
                            preferredName: preferredName.isEmpty ? nil : preferredName,
                            preferredCategory: category,
                            workspace: workspace,
                            modelContext: modelContext
                        )
                    }

                    if secondaryKey != primaryKey, !secondaryKey.isEmpty {
                        ImportLearningStore.upsertRule(
                            merchantKey: secondaryKey,
                            preferredName: preferredName.isEmpty ? nil : preferredName,
                            preferredCategory: category,
                            workspace: workspace,
                            modelContext: modelContext
                        )
                    }
                }

            case .income:
                let inc = Income(
                    source: row.finalMerchant,
                    amount: row.finalAmount,
                    date: row.finalDate,
                    isPlanned: false,
                    isException: false,
                    workspace: workspace,
                    series: nil,
                    card: card
                )
                modelContext.insert(inc)

                if row.rememberMapping {
                    let preferredName = row.finalMerchant.trimmingCharacters(in: .whitespacesAndNewlines)
                    let primaryKey = row.sourceMerchantKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    let secondaryKey = row.descriptionMerchantKey.trimmingCharacters(in: .whitespacesAndNewlines)

                    if !primaryKey.isEmpty {
                        ImportLearningStore.upsertRule(
                            merchantKey: primaryKey,
                            preferredName: preferredName.isEmpty ? nil : preferredName,
                            preferredCategory: nil,
                            workspace: workspace,
                            modelContext: modelContext
                        )
                    }

                    if secondaryKey != primaryKey, !secondaryKey.isEmpty {
                        ImportLearningStore.upsertRule(
                            merchantKey: secondaryKey,
                            preferredName: preferredName.isEmpty ? nil : preferredName,
                            preferredCategory: nil,
                            workspace: workspace,
                            modelContext: modelContext
                        )
                    }
                }
            }
        }

        try? modelContext.save()
    }

    // MARK: - Duplicate hints

    nonisolated static func applyImportModeRules(_ rows: [ExpenseCSVImportRow], mode: ImportMode) -> [ExpenseCSVImportRow] {
        switch mode {
        case .cardTransactions:
            return rows.map { row in
                var updated = row
                updated.blockedReason = nil
                return updated
            }

        case .incomeOnly:
            return rows.map { row in
                var updated = row

                if updated.kind == .expense {
                    updated.blockedReason = "Expense rows are skipped when importing from Income."
                    updated.includeInImport = false
                    updated.rememberMapping = false
                    return updated
                }

                updated.blockedReason = nil
                return updated
            }
        }
    }

    private func looksLikeDuplicateExpense(date: Date, amount: Double, merchantKey: String, categoryID: UUID?) -> Bool {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        let candidateDays = candidateDaysSet(around: day, calendar: cal, windowDays: duplicateDayWindow)

        var dayAmountMatches: [VariableExpense] = []
        dayAmountMatches.reserveCapacity(4)

        for e in existingExpenses {
            if abs(e.amount - amount) > 0.0001 { continue }
            let eDay = cal.startOfDay(for: e.transactionDate)
            if !candidateDays.contains(eDay) { continue }

            dayAmountMatches.append(e)
            if MerchantNormalizer.normalizeKey(e.descriptionText) == merchantKey { return true }
        }

        if dayAmountMatches.isEmpty { return false }

        if dayAmountMatches.count == 1 { return true }

        if looksLikeDuplicatePlannedExpense(date: date, amount: amount, merchantKey: merchantKey, categoryID: categoryID, calendar: cal) {
            return true
        }

        guard let categoryID else { return false }
        let sameCategory = dayAmountMatches.filter { $0.category?.id == categoryID }
        if sameCategory.isEmpty { return false }

        if sameCategory.count == 1 { return true }
        return false
    }

    private func looksLikeDuplicatePlannedExpense(
        date: Date,
        amount: Double,
        merchantKey: String,
        categoryID: UUID?,
        calendar: Calendar
    ) -> Bool {
        let day = calendar.startOfDay(for: date)
        let candidateDays = candidateDaysSet(around: day, calendar: calendar, windowDays: duplicateDayWindow)

        var dayAmountMatches: [PlannedExpense] = []
        dayAmountMatches.reserveCapacity(4)

        for p in existingPlannedExpenses {
            let effectiveAmount = (abs(p.actualAmount) > 0.0001) ? p.actualAmount : p.plannedAmount
            if abs(effectiveAmount - amount) > 0.0001 { continue }
            let pDay = calendar.startOfDay(for: p.expenseDate)
            if !candidateDays.contains(pDay) { continue }

            dayAmountMatches.append(p)
            if MerchantNormalizer.normalizeKey(p.title) == merchantKey { return true }
        }

        if dayAmountMatches.isEmpty { return false }

        if dayAmountMatches.count == 1 { return true }

        guard let categoryID else { return false }
        let sameCategory = dayAmountMatches.filter { $0.category?.id == categoryID }
        if sameCategory.isEmpty { return false }
        if sameCategory.count == 1 { return true }
        return false
    }

    private func looksLikeDuplicateIncome(date: Date, amount: Double, merchantKey: String) -> Bool {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)

        for i in existingIncomes {
            if abs(i.amount - amount) > 0.0001 { continue }
            let iDay = cal.startOfDay(for: i.date)
            if iDay != day { continue }
            if MerchantNormalizer.normalizeKey(i.source) == merchantKey { return true }
        }

        return false
    }

    private func candidateDaysSet(around day: Date, calendar: Calendar, windowDays: Int) -> Set<Date> {
        var days: [Date] = [day]
        if windowDays <= 0 { return Set(days) }

        for offset in 1...windowDays {
            if let earlier = calendar.date(byAdding: .day, value: -offset, to: day) {
                days.append(calendar.startOfDay(for: earlier))
            }
            if let later = calendar.date(byAdding: .day, value: offset, to: day) {
                days.append(calendar.startOfDay(for: later))
            }
        }

        return Set(days)
    }

    private func bucketForExpenseRow(_ row: ExpenseCSVImportRow) -> ExpenseCSVImportBucket {
        if row.isDuplicateHint { return .possibleDuplicate }
        guard let selectedCategory = row.selectedCategory else { return .needsMoreData }

        if let suggestedCategory = row.suggestedCategory, suggestedCategory.id == selectedCategory.id {
            if row.suggestedConfidence >= CategoryMatchingEngine.readyThreshold { return .ready }
            if row.suggestedConfidence >= CategoryMatchingEngine.possibleThreshold { return .possibleMatch }
            return .possibleMatch
        }

        return .ready
    }

    // MARK: - Import document routing

    private func parseImportedDocument(url: URL, referenceDate: Date?) throws -> ParsedCSV {
        switch detectDocumentKind(for: url) {
        case .csv:
            return try CSVParser.parse(url: url)
        case .pdf:
            if let paystubParsed = try? PaystubPDFImportParser.parse(url: url) {
                return paystubParsed
            }
            return try StatementPDFImportParser.parse(url: url)
        case .image:
            return try ExpenseImageImportParser.parse(url: url, referenceDate: referenceDate ?? .now)
        case .unsupported:
            throw ImportLoadError.unsupportedFileType
        }
    }

    private func detectDocumentKind(for url: URL) -> ImportDocumentKind {
        let ext = url.pathExtension.lowercased()
        if ext == "csv" {
            return .csv
        }
        if ext == "pdf" {
            return .pdf
        }

        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp"]
        if imageExtensions.contains(ext) {
            return .image
        }

        if let type = UTType(filenameExtension: ext), type.conforms(to: .image) {
            return .image
        }
        if let type = UTType(filenameExtension: ext), type.conforms(to: .commaSeparatedText) {
            return .csv
        }
        if let type = UTType(filenameExtension: ext), type.conforms(to: .pdf) {
            return .pdf
        }

        return .unsupported
    }

    private func errorMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let message = localized.errorDescription,
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return message
        }
        return (error as NSError).localizedDescription
    }

    private func parseAsCSVIfPossible(from text: String) throws -> ParsedCSV? {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let separators = [",", "\t", ";"]
        guard separators.contains(where: { firstLine.contains($0) }) else { return nil }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("offshore-shortcuts-clipboard-\(UUID().uuidString).csv")
        try text.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        return try CSVParser.parse(url: tempURL)
    }
}
