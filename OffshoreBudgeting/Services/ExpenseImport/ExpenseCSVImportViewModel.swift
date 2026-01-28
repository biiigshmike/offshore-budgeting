//
//  ExpenseCSVImportViewModel.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/25/26.
//

import Foundation
import SwiftData
import Combine

@MainActor
final class ExpenseCSVImportViewModel: ObservableObject {

    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published var state: State = .idle
    @Published private(set) var rows: [ExpenseCSVImportRow] = []
    @Published private(set) var categories: [Category] = []

    // Option 1 memory dictionary keyed by merchantKey.
    private var learnedRules: [String: ImportMerchantRule] = [:]

    private var existingExpenses: [VariableExpense] = []
    private var existingPlannedExpenses: [PlannedExpense] = []
    private var existingIncomes: [Income] = []

    // MARK: - Grouped rows

    var readyRows: [ExpenseCSVImportRow] { rows.filter { $0.bucket == .ready }.sorted { $0.sourceLine < $1.sourceLine } }
    var possibleMatchRows: [ExpenseCSVImportRow] { rows.filter { $0.bucket == .possibleMatch }.sorted { $0.sourceLine < $1.sourceLine } }
    var paymentRows: [ExpenseCSVImportRow] { rows.filter { $0.bucket == .payment }.sorted { $0.sourceLine < $1.sourceLine } }
    var possibleDuplicateRows: [ExpenseCSVImportRow] { rows.filter { $0.bucket == .possibleDuplicate }.sorted { $0.sourceLine < $1.sourceLine } }
    var needsMoreDataRows: [ExpenseCSVImportRow] { rows.filter { $0.bucket == .needsMoreData }.sorted { $0.sourceLine < $1.sourceLine } }

    var canCommit: Bool {
        rows.contains { $0.includeInImport && !$0.isMissingRequiredData }
    }

    var commitSummaryText: String {
        let included = rows.filter { $0.includeInImport }
        let expCount = included.filter { $0.kind == .expense && !$0.isMissingRequiredData }.count
        let incCount = included.filter { $0.kind == .income && !$0.isMissingRequiredData }.count
        return "\(expCount) expenses, \(incCount) incomes will be imported."
    }

    // MARK: - Public

    func prepare(workspace: Workspace, modelContext: ModelContext) {
        // Categories
        let cats = (workspace.categories ?? [])
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        categories = cats

        // Learned rules (Option 1)
        learnedRules = ImportLearningStore.fetchRules(for: workspace, modelContext: modelContext)
    }

    func load(url: URL, workspace: Workspace, card: Card, modelContext: ModelContext) {
        state = .loading

        do {
            existingExpenses = card.variableExpenses ?? []
            existingPlannedExpenses = card.plannedExpenses ?? []
            existingIncomes = card.incomes ?? []

            let parsed = try CSVParser.parse(url: url)
            let mapped = ExpenseCSVImportMapper.map(
                csv: parsed,
                categories: categories,
                existingExpenses: existingExpenses,
                existingPlannedExpenses: existingPlannedExpenses,
                existingIncomes: existingIncomes,
                learnedRules: learnedRules
            )
            rows = mapped
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func toggleInclude(rowID: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == rowID }) else { return }

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

        // If they manually set a category in Possible Matches, we allow them to include.
        if rows[idx].bucket == .possibleMatch || rows[idx].bucket == .possibleDuplicate {
            // stay unchecked unless user checks it
        }

        // Recompute duplicate hint since we can use category as a fallback signal.
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

    func setKind(rowID: UUID, kind: ExpenseCSVImportKind) {
        guard let idx = rows.firstIndex(where: { $0.id == rowID }) else { return }
        if rows[idx].kind == kind { return }

        let wasIncluded = rows[idx].includeInImport
        rows[idx].kind = kind

        if kind == .income {
            rows[idx].selectedCategory = nil
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
        rows[idx].rememberMapping.toggle()
    }

    func commitImport(workspace: Workspace, card: Card, modelContext: ModelContext) {
        let importable = rows.filter { $0.includeInImport && !$0.isMissingRequiredData }

        for row in importable {
            switch row.kind {
            case .expense:
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

    private func looksLikeDuplicateExpense(date: Date, amount: Double, merchantKey: String, categoryID: UUID?) -> Bool {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)

        var dayAmountMatches: [VariableExpense] = []
        dayAmountMatches.reserveCapacity(4)

        for e in existingExpenses {
            if abs(e.amount - amount) > 0.0001 { continue }
            let eDay = cal.startOfDay(for: e.transactionDate)
            if eDay != day { continue }

            dayAmountMatches.append(e)
            if MerchantNormalizer.normalizeKey(e.descriptionText) == merchantKey { return true }
        }

        if dayAmountMatches.isEmpty { return false }

        guard let categoryID else { return false }
        let sameCategory = dayAmountMatches.filter { $0.category?.id == categoryID }
        if sameCategory.isEmpty { return false }

        if dayAmountMatches.count == 1 { return true }
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
}
