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

    // MARK: - Grouped rows

    var readyRows: [ExpenseCSVImportRow] { rows.filter { $0.bucket == .ready }.sorted { $0.sourceLine < $1.sourceLine } }
    var possibleMatchRows: [ExpenseCSVImportRow] { rows.filter { $0.bucket == .possibleMatch }.sorted { $0.sourceLine < $1.sourceLine } }
    var paymentRows: [ExpenseCSVImportRow] { rows.filter { $0.bucket == .payment }.sorted { $0.sourceLine < $1.sourceLine } }
    var possibleDuplicateRows: [ExpenseCSVImportRow] { rows.filter { $0.bucket == .possibleDuplicate }.sorted { $0.sourceLine < $1.sourceLine } }
    var needsMoreDataRows: [ExpenseCSVImportRow] { rows.filter { $0.bucket == .needsMoreData }.sorted { $0.sourceLine < $1.sourceLine } }

    var canCommit: Bool {
        rows.contains { $0.includeInImport && $0.bucket != .needsMoreData }
    }

    var commitSummaryText: String {
        let included = rows.filter { $0.includeInImport }
        let expCount = included.filter { $0.kind == .expense && $0.bucket != .needsMoreData }.count
        let incCount = included.filter { $0.kind == .income && $0.bucket != .needsMoreData }.count
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
            let parsed = try CSVParser.parse(url: url)
            let mapped = ExpenseCSVImportMapper.map(
                csv: parsed,
                categories: categories,
                existingExpenses: card.variableExpenses ?? [],
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

        // If row is Needs More Data, do not allow checking.
        if rows[idx].bucket == .needsMoreData {
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

        rows[idx].recomputeBucket()
    }

    func toggleRemember(rowID: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == rowID }) else { return }
        rows[idx].rememberMapping.toggle()
    }

    func commitImport(workspace: Workspace, card: Card, modelContext: ModelContext) {
        let importable = rows.filter { $0.includeInImport && $0.bucket != .needsMoreData }

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
                    ImportLearningStore.upsertRule(
                        merchantKey: MerchantNormalizer.normalize(row.finalMerchant),
                        preferredName: row.finalMerchant,
                        preferredCategory: category,
                        workspace: workspace,
                        modelContext: modelContext
                    )
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
            }
        }

        try? modelContext.save()
    }
}
