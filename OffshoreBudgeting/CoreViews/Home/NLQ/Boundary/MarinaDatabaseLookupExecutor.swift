import Foundation

@MainActor
struct MarinaDatabaseLookupExecutor {
    func execute(
        _ request: MarinaDatabaseLookupRequest,
        provider: MarinaDataProvider
    ) -> MarinaDatabaseLookupResponse {
        let request = request.clamped
        let allowedTypes = Set(expandedTypes(request.objectTypes))
        let search = normalized(request.searchText)

        let scoredResults = candidateResults(provider: provider)
            .filter { allowedTypes.contains($0.objectType) }
            .filter { result in
                request.dateRange.map { range in dateRangeContains(result.date, range: range) } ?? true
            }
            .compactMap { result -> (MarinaDatabaseLookupResult, Int)? in
                guard search.isEmpty == false else {
                    return (result, 1)
                }
                let score = matchScore(search: search, result: result)
                return score > 0 ? (result, score) : nil
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return (lhs.0.date ?? .distantPast) > (rhs.0.date ?? .distantPast)
                }
                return lhs.1 > rhs.1
            }

        let bestResults: [MarinaDatabaseLookupResult]
        if request.requestedDetail != .general,
           scoredResults.contains(where: { $0.1 == 100 }) {
            bestResults = scoredResults.filter { $0.1 == 100 }.map(\.0)
        } else {
            bestResults = scoredResults.map(\.0)
        }

        let exactTypeMatches = scoredResults
            .filter { $0.1 == 100 }
            .map(\.0)
        let exactObjectTypes = Set(exactTypeMatches.map(\.objectType))
        if request.objectTypes.contains(.unknown),
           request.requestedDetail == .general,
           exactObjectTypes.count > 1 {
            return MarinaDatabaseLookupResponse(
                request: request,
                results: [],
                ambiguityChoices: Array(exactTypeMatches.prefix(request.limit))
            )
        }

        return MarinaDatabaseLookupResponse(
            request: request,
            results: Array(bestResults.prefix(request.limit))
        )
    }

    private func candidateResults(provider: MarinaDataProvider) -> [MarinaDatabaseLookupResult] {
        var results: [MarinaDatabaseLookupResult] = []
        let workspaceName = provider.fetchWorkspace()?.name

        for budget in provider.fetchAllBudgets() {
            results.append(result(
                id: budget.id,
                objectType: .budget,
                title: budget.name,
                subtitle: "Budget",
                date: budget.startDate,
                workspaceName: workspaceName,
                details: [
                    ("Type", "Budget"),
                    ("Starts", formatDate(budget.startDate)),
                    ("Ends", formatDate(budget.endDate))
                ]
            ))
        }

        for income in provider.fetchAllIncomes() {
            results.append(result(
                id: income.id,
                objectType: .income,
                title: income.source,
                subtitle: income.isPlanned ? "Planned income" : "Income",
                date: income.date,
                amount: income.amount,
                cardName: income.card?.name,
                workspaceName: workspaceName,
                details: [
                    ("Type", income.isPlanned ? "Planned income" : "Income"),
                    ("Date", formatDate(income.date)),
                    ("Amount", CurrencyFormatter.string(from: income.amount))
                ]
            ))
        }

        for expense in provider.fetchAllVariableExpenses() {
            results.append(result(
                id: expense.id,
                objectType: .variableExpense,
                title: expense.descriptionText,
                subtitle: "Expense",
                date: expense.transactionDate,
                amount: expense.ledgerDisplayAmount(),
                cardName: expense.card?.name,
                categoryName: expense.category?.name,
                workspaceName: workspaceName,
                details: [
                    ("Type", "Expense"),
                    ("Date", formatDate(expense.transactionDate)),
                    ("Amount", CurrencyFormatter.string(from: expense.ledgerDisplayAmount())),
                    ("Card", expense.card?.name ?? "Unassigned"),
                    ("Category", expense.category?.name ?? "Uncategorized")
                ]
            ))
        }

        for expense in provider.fetchAllPlannedExpenses() {
            let effectiveAmount = expense.actualAmount > 0 ? expense.actualAmount : expense.plannedAmount
            results.append(result(
                id: expense.id,
                objectType: .plannedExpense,
                title: expense.title,
                subtitle: "Planned expense",
                date: expense.expenseDate,
                amount: effectiveAmount,
                cardName: expense.card?.name,
                categoryName: expense.category?.name,
                workspaceName: workspaceName,
                details: [
                    ("Type", "Planned expense"),
                    ("Date", formatDate(expense.expenseDate)),
                    ("Planned", CurrencyFormatter.string(from: expense.plannedAmount)),
                    ("Actual", expense.actualAmount > 0 ? CurrencyFormatter.string(from: expense.actualAmount) : "Not recorded"),
                    ("Card", expense.card?.name ?? "Unassigned"),
                    ("Category", expense.category?.name ?? "Uncategorized")
                ]
            ))
        }

        for category in provider.fetchAllCategories() {
            results.append(result(
                id: category.id,
                objectType: .category,
                title: category.name,
                subtitle: "Category",
                workspaceName: workspaceName,
                details: [
                    ("Type", "Category"),
                    ("Color", category.hexColor)
                ]
            ))
        }

        for preset in provider.fetchAllPresets() {
            results.append(result(
                id: preset.id,
                objectType: .preset,
                title: preset.title,
                subtitle: "Preset",
                amount: preset.plannedAmount,
                cardName: preset.defaultCard?.name,
                categoryName: preset.defaultCategory?.name,
                workspaceName: workspaceName,
                details: [
                    ("Type", "Preset"),
                    ("Amount", CurrencyFormatter.string(from: preset.plannedAmount)),
                    ("Schedule", preset.frequency.rawValue),
                    ("Card", preset.defaultCard?.name ?? "Unassigned"),
                    ("Category", preset.defaultCategory?.name ?? "Uncategorized"),
                    ("Status", preset.isArchived ? "Archived" : "Active")
                ]
            ))
        }

        for card in provider.fetchAllCards() {
            results.append(result(
                id: card.id,
                objectType: .card,
                title: card.name,
                subtitle: "Card",
                workspaceName: workspaceName,
                details: [
                    ("Type", "Card"),
                    ("Theme", card.theme),
                    ("Effect", card.effect)
                ]
            ))
        }

        for account in provider.fetchAllSavingsAccounts() {
            results.append(result(
                id: account.id,
                objectType: .savingsAccount,
                title: account.name,
                subtitle: "Savings account",
                amount: account.total,
                workspaceName: workspaceName,
                details: [
                    ("Type", "Savings account"),
                    ("Balance", CurrencyFormatter.string(from: account.total))
                ]
            ))
        }

        for entry in provider.fetchAllSavingsLedgerEntries() {
            results.append(result(
                id: entry.id,
                objectType: .savingsLedgerEntry,
                title: entry.note.isEmpty ? entry.kindRaw : entry.note,
                subtitle: "Savings ledger entry",
                date: entry.date,
                amount: entry.amount,
                accountName: entry.account?.name,
                workspaceName: workspaceName,
                details: [
                    ("Type", "Savings ledger entry"),
                    ("Date", formatDate(entry.date)),
                    ("Amount", CurrencyFormatter.string(from: entry.amount)),
                    ("Account", entry.account?.name ?? "Savings")
                ]
            ))
        }

        for account in provider.fetchAllAllocationAccounts() {
            results.append(result(
                id: account.id,
                objectType: .reconciliationAccount,
                title: account.name,
                subtitle: "Reconciliation account",
                workspaceName: workspaceName,
                details: [
                    ("Type", "Reconciliation account"),
                    ("Color", account.hexColor),
                    ("Status", account.isArchived ? "Archived" : "Active")
                ]
            ))
        }

        for settlement in provider.fetchAllAllocationSettlements() {
            results.append(result(
                id: settlement.id,
                objectType: .reconciliationItem,
                title: settlement.note.isEmpty ? "Reconciliation settlement" : settlement.note,
                subtitle: "Reconciliation item",
                date: settlement.date,
                amount: settlement.amount,
                accountName: settlement.account?.name,
                workspaceName: workspaceName,
                details: [
                    ("Type", "Reconciliation item"),
                    ("Date", formatDate(settlement.date)),
                    ("Amount", CurrencyFormatter.string(from: settlement.amount)),
                    ("Account", settlement.account?.name ?? "Unassigned")
                ]
            ))
        }

        if let workspace = provider.fetchWorkspace() {
            results.append(result(
                id: workspace.id,
                objectType: .workspace,
                title: workspace.name,
                subtitle: "Workspace",
                workspaceName: workspace.name,
                details: [
                    ("Type", "Workspace"),
                    ("Color", workspace.hexColor)
                ]
            ))
        }

        return results
    }

    private func result(
        id: UUID,
        objectType: MarinaLookupObjectType,
        title: String,
        subtitle: String?,
        date: Date? = nil,
        amount: Double? = nil,
        cardName: String? = nil,
        categoryName: String? = nil,
        accountName: String? = nil,
        workspaceName: String?,
        details: [(String, String)]
    ) -> MarinaDatabaseLookupResult {
        MarinaDatabaseLookupResult(
            id: id,
            objectType: objectType,
            title: title,
            subtitle: subtitle,
            date: date,
            amount: amount,
            cardName: cardName,
            categoryName: categoryName,
            accountName: accountName,
            workspaceName: workspaceName,
            detailRows: details.map { .init(label: $0.0, value: $0.1) }
        )
    }

    private func expandedTypes(_ objectTypes: [MarinaLookupObjectType]) -> [MarinaLookupObjectType] {
        if objectTypes.contains(.unknown) {
            return MarinaLookupObjectType.allCases.filter { $0 != .unknown }
        }
        return objectTypes
    }

    private func matchScore(search: String, result: MarinaDatabaseLookupResult) -> Int {
        let candidates = [
            result.title,
            result.subtitle,
            result.cardName,
            result.categoryName,
            result.accountName,
            result.workspaceName
        ].compactMap { $0 }.map(normalized)

        if candidates.contains(search) {
            return 100
        }
        if candidates.contains(where: { $0.contains(search) || search.contains($0) }) {
            return 70
        }

        let searchTokens = Set(search.split(separator: " ").map(String.init))
        guard searchTokens.isEmpty == false else { return 0 }
        let bestOverlap = candidates
            .map { candidate in
                Set(candidate.split(separator: " ").map(String.init)).intersection(searchTokens).count
            }
            .max() ?? 0
        return bestOverlap > 0 ? 25 + bestOverlap : 0
    }

    private func dateRangeContains(_ date: Date?, range: HomeQueryDateRange) -> Bool {
        guard let date else { return false }
        return date >= range.startDate && date <= range.endDate
    }

    private func normalized(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
