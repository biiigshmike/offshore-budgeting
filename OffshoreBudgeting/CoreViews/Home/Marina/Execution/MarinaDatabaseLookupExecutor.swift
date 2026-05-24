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
                let score = matchScore(search: search, result: result, mode: request.lookupMode)
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
        if request.lookupMode == .broadSearch,
           shouldClarifyBroadExactMatches(request.objectTypes),
           let collisionChoices = broadSearchIdentityRelationshipCollision(
            search: search,
            matches: exactTypeMatches
           ) {
            return MarinaDatabaseLookupResponse(
                request: request,
                results: [],
                ambiguityChoices: Array(collisionChoices.prefix(request.limit))
            )
        }
        let exactObjectTypes = Set(exactTypeMatches.map(\.objectType))
        if request.requestedDetail == .general,
           exactObjectTypes.count > 1,
           shouldClarifyBroadExactMatches(request.objectTypes) {
            return MarinaDatabaseLookupResponse(
                request: request,
                results: [],
                ambiguityChoices: Array(broadExactAmbiguityChoices(exactTypeMatches).prefix(request.limit))
            )
        }

        if request.requestedDetail != .general,
           exactTypeMatches.count > 1 {
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

    private func broadExactAmbiguityChoices(_ matches: [MarinaDatabaseLookupResult]) -> [MarinaDatabaseLookupResult] {
        let rowMatches = matches
            .filter { $0.objectType == .variableExpense || $0.objectType == .plannedExpense }
            .sorted { lhs, rhs in
                if lhs.objectType != rhs.objectType {
                    return ambiguityRank(lhs.objectType) < ambiguityRank(rhs.objectType)
                }
                return (lhs.date ?? .distantFuture) < (rhs.date ?? .distantFuture)
            }
        return representativeStoredObjectMatches(matches) + rowMatches
    }

    private func representativeStoredObjectMatches(_ matches: [MarinaDatabaseLookupResult]) -> [MarinaDatabaseLookupResult] {
        var bestByType: [MarinaLookupObjectType: MarinaDatabaseLookupResult] = [:]
        for match in matches where match.objectType != .variableExpense && match.objectType != .plannedExpense {
            if let existing = bestByType[match.objectType] {
                if (match.date ?? .distantPast) > (existing.date ?? .distantPast) {
                    bestByType[match.objectType] = match
                }
            } else {
                bestByType[match.objectType] = match
            }
        }
        return bestByType.values.sorted { lhs, rhs in
            let lhsRank = ambiguityRank(lhs.objectType)
            let rhsRank = ambiguityRank(rhs.objectType)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func ambiguityRank(_ type: MarinaLookupObjectType) -> Int {
        switch type {
        case .category:
            return 0
        case .card:
            return 1
        case .variableExpense:
            return 2
        case .plannedExpense:
            return 3
        case .budget:
            return 4
        case .preset:
            return 5
        case .income, .incomeSeries:
            return 6
        case .savingsAccount, .savingsLedgerEntry:
            return 7
        case .reconciliationAccount, .reconciliationItem, .expenseAllocation:
            return 8
        case .importMerchantRule, .assistantAliasRule, .workspace, .unknown:
            return 9
        }
    }

    private func candidateResults(provider: MarinaDataProvider) -> [MarinaDatabaseLookupResult] {
        var results: [MarinaDatabaseLookupResult] = []
        let workspaceName = provider.fetchWorkspace()?.name

        for budget in provider.fetchAllBudgets() {
            let linkedCards = (budget.cardLinks ?? []).compactMap { $0.card?.name }.sorted()
            let linkedPresets = (budget.presetLinks ?? []).compactMap { $0.preset?.title }.sorted()
            let limitNames = (budget.categoryLimits ?? []).compactMap { limit -> String? in
                guard let category = limit.category else { return nil }
                let values = [
                    limit.minAmount.map { "min \(CurrencyFormatter.string(from: $0))" },
                    limit.maxAmount.map { "max \(CurrencyFormatter.string(from: $0))" }
                ].compactMap { $0 }
                return values.isEmpty ? category.name : "\(category.name) (\(values.joined(separator: ", ")))"
            }.sorted()
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
                    ("Ends", formatDate(budget.endDate)),
                    ("Linked cards", linkedCards.isEmpty ? "None" : linkedCards.joined(separator: ", ")),
                    ("Linked presets", linkedPresets.isEmpty ? "None" : linkedPresets.joined(separator: ", ")),
                    ("Category limits", limitNames.isEmpty ? "None" : limitNames.joined(separator: ", "))
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

        for series in provider.fetchAllIncomeSeries() {
            results.append(result(
                id: series.id,
                objectType: .incomeSeries,
                title: series.source,
                subtitle: series.isPlanned ? "Planned income series" : "Income series",
                date: series.startDate,
                amount: series.amount,
                workspaceName: workspaceName,
                details: [
                    ("Type", series.isPlanned ? "Planned income series" : "Income series"),
                    ("Amount", CurrencyFormatter.string(from: series.amount)),
                    ("Schedule", series.frequency.rawValue),
                    ("Starts", formatDate(series.startDate)),
                    ("Ends", formatDate(series.endDate))
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
            let ledgerTotal = provider.fetchAllVariableExpenses()
                .filter { $0.card?.id == card.id }
                .reduce(0.0) { $0 + $1.ledgerSignedAmount() }
            let spendTotal = provider.fetchAllVariableExpenses()
                .filter { $0.card?.id == card.id }
                .reduce(0.0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }
            results.append(result(
                id: card.id,
                objectType: .card,
                title: card.name,
                subtitle: "Card",
                amount: ledgerTotal,
                workspaceName: workspaceName,
                details: [
                    ("Type", "Card"),
                    ("Theme", card.theme),
                    ("Effect", card.effect),
                    ("Ledger total", CurrencyFormatter.string(from: ledgerTotal)),
                    ("Budget impact", CurrencyFormatter.string(from: spendTotal))
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

        for allocation in provider.fetchAllExpenseAllocations() {
            let linkedExpense = allocation.expense?.descriptionText ?? allocation.plannedExpense?.title ?? "Unlinked allocation"
            let linkedDate = allocation.expense?.transactionDate ?? allocation.plannedExpense?.expenseDate
            results.append(result(
                id: allocation.id,
                objectType: .expenseAllocation,
                title: linkedExpense,
                subtitle: "Expense allocation",
                date: linkedDate,
                amount: allocation.allocatedAmount,
                accountName: allocation.account?.name,
                workspaceName: workspaceName,
                details: [
                    ("Type", "Expense allocation"),
                    ("Amount", CurrencyFormatter.string(from: allocation.allocatedAmount)),
                    ("Account", allocation.account?.name ?? "Unassigned"),
                    ("Expense", linkedExpense)
                ]
            ))
        }

        for rule in provider.fetchAllImportMerchantRules() {
            results.append(result(
                id: rule.id,
                objectType: .importMerchantRule,
                title: rule.preferredName ?? rule.merchantKey,
                subtitle: "Import merchant rule",
                categoryName: rule.preferredCategory?.name,
                workspaceName: workspaceName,
                details: [
                    ("Type", "Import merchant rule"),
                    ("Merchant key", rule.merchantKey),
                    ("Preferred name", rule.preferredName ?? "None"),
                    ("Preferred category", rule.preferredCategory?.name ?? "None")
                ]
            ))
        }

        for rule in provider.fetchAllAssistantAliasRules() {
            results.append(result(
                id: rule.id,
                objectType: .assistantAliasRule,
                title: rule.aliasKey,
                subtitle: "Assistant alias",
                workspaceName: workspaceName,
                details: [
                    ("Type", "Assistant alias"),
                    ("Alias", rule.aliasKey),
                    ("Target", rule.targetValue),
                    ("Entity type", rule.entityType.rawValue)
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

    private func shouldClarifyBroadExactMatches(_ objectTypes: [MarinaLookupObjectType]) -> Bool {
        if objectTypes.contains(.unknown) { return true }
        return Set(objectTypes) == Set(MarinaLookupObjectType.safeDefaultSearchTypes)
    }

    private func matchScore(
        search: String,
        result: MarinaDatabaseLookupResult,
        mode: MarinaLookupMode
    ) -> Int {
        switch mode {
        case .entityDetail:
            return score(
                search: search,
                candidates: identityCandidates(for: result),
                allowsTokenOverlap: false
            )
        case .relatedRows, .relationship, .broadSearch:
            return score(search: search, candidates: broadCandidates(for: result))
        }
    }

    private func broadSearchIdentityRelationshipCollision(
        search: String,
        matches: [MarinaDatabaseLookupResult]
    ) -> [MarinaDatabaseLookupResult]? {
        guard search.isEmpty == false else { return nil }
        let identityMatches = matches.filter {
            score(search: search, candidates: identityCandidates(for: $0), allowsTokenOverlap: false) == 100
        }
        guard identityMatches.isEmpty == false else { return nil }

        let relatedMatches = matches.filter { result in
            score(search: search, candidates: relationshipCandidates(for: result)) == 100
                && identityMatches.contains(where: { $0.id == result.id && $0.objectType == result.objectType }) == false
        }
        guard relatedMatches.isEmpty == false else { return nil }

        let identityChoices = representativeStoredObjectMatches(identityMatches)
        return (identityChoices.isEmpty ? identityMatches : identityChoices)
            + relatedMatches.sorted { lhs, rhs in
                if lhs.objectType != rhs.objectType {
                    return ambiguityRank(lhs.objectType) < ambiguityRank(rhs.objectType)
                }
                return (lhs.date ?? .distantFuture) < (rhs.date ?? .distantFuture)
            }
    }

    private func identityCandidates(for result: MarinaDatabaseLookupResult) -> [String] {
        [result.title]
    }

    private func relationshipCandidates(for result: MarinaDatabaseLookupResult) -> [String] {
        [
            result.cardName,
            result.categoryName,
            result.accountName
        ].compactMap { $0 }
    }

    private func broadCandidates(for result: MarinaDatabaseLookupResult) -> [String] {
        [
            result.title,
            result.cardName,
            result.categoryName,
            result.accountName,
            result.workspaceName
        ].compactMap { $0 }
    }

    private func score(
        search: String,
        candidates rawCandidates: [String],
        allowsTokenOverlap: Bool = true
    ) -> Int {
        let candidates = rawCandidates.map(normalized)

        if candidates.contains(search) {
            return 100
        }
        if candidates.contains(where: { $0.contains(search) || search.contains($0) }) {
            return 70
        }
        guard allowsTokenOverlap else { return 0 }

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
