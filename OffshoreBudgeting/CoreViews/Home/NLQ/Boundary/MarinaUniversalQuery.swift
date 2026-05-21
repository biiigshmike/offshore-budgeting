import Foundation

enum MarinaUniversalQueryOperation: String, Codable, Equatable, CaseIterable, Sendable {
    case lookup
    case list
    case count
    case sum
    case average
    case rank
    case groupBreakdown
    case compare
    case detail
    case simulate

    var catalogOperationName: String {
        switch self {
        case .lookup, .detail:
            return "lookupDetails"
        case .list:
            return "list"
        case .count:
            return "count"
        case .sum:
            return "total"
        case .average:
            return "average"
        case .rank:
            return "rank"
        case .groupBreakdown:
            return "groupedBreakdown"
        case .compare:
            return "compare"
        case .simulate:
            return "simulate"
        }
    }
}

enum MarinaUniversalWorkspaceScopePolicy: String, Codable, Equatable, Sendable {
    case selectedWorkspace
    case explicitGlobal
}

enum MarinaUniversalFilterMatch: String, Codable, Equatable, Sendable {
    case exact
    case contains
    case uncategorized
}

struct MarinaUniversalQueryFilter: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let field: String?
    let value: String
    let match: MarinaUniversalFilterMatch

    init(
        id: UUID = UUID(),
        field: String? = nil,
        value: String,
        match: MarinaUniversalFilterMatch = .contains
    ) {
        self.id = id
        self.field = field
        self.value = value
        self.match = match
    }
}

struct MarinaUniversalQueryIR: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let operation: MarinaUniversalQueryOperation
    let modelName: String
    let filters: [MarinaUniversalQueryFilter]
    let relationships: [String]
    let amountBasis: MarinaAmountField?
    let dateRange: HomeQueryDateRange?
    let dateSource: MarinaDateSource
    let grouping: String?
    let ranking: MarinaRankingDirectionCandidate?
    let limit: Int?
    let workspaceScopePolicy: MarinaUniversalWorkspaceScopePolicy
    let presentationShape: MarinaResponseShape
    let evidenceRowType: String

    init(
        id: UUID = UUID(),
        operation: MarinaUniversalQueryOperation,
        modelName: String,
        filters: [MarinaUniversalQueryFilter] = [],
        relationships: [String] = [],
        amountBasis: MarinaAmountField? = nil,
        dateRange: HomeQueryDateRange? = nil,
        dateSource: MarinaDateSource = .none,
        grouping: String? = nil,
        ranking: MarinaRankingDirectionCandidate? = nil,
        limit: Int? = nil,
        workspaceScopePolicy: MarinaUniversalWorkspaceScopePolicy,
        presentationShape: MarinaResponseShape,
        evidenceRowType: String
    ) {
        self.id = id
        self.operation = operation
        self.modelName = modelName
        self.filters = filters
        self.relationships = relationships
        self.amountBasis = amountBasis
        self.dateRange = dateRange
        self.dateSource = dateSource
        self.grouping = grouping
        self.ranking = ranking
        self.limit = limit
        self.workspaceScopePolicy = workspaceScopePolicy
        self.presentationShape = presentationShape
        self.evidenceRowType = evidenceRowType
    }
}

enum MarinaUniversalQueryExecutionResult: Equatable {
    case handled(MarinaWorkspaceAggregationCard)
    case unsupported(MarinaTypedUnsupportedResponse)
}

@MainActor
struct MarinaUniversalQueryExecutor {
    private let catalog: MarinaEntityCatalog

    init(catalog: MarinaEntityCatalog? = nil) {
        self.catalog = catalog ?? .current
    }

    func execute(
        _ query: MarinaUniversalQueryIR,
        provider: MarinaDataProvider
    ) -> MarinaUniversalQueryExecutionResult {
        guard let descriptor = catalog.descriptor(for: query.modelName),
              descriptor.kind == .persistentModel else {
            return unsupported(query, "That data type is not available to Marina's universal query catalog.")
        }

        guard supports(query.operation, descriptor: descriptor) else {
            return unsupported(query, "Universal \(query.operation.rawValue) is not supported for \(descriptor.displayName).")
        }

        let allRows = rows(for: descriptor, provider: provider)
        let matchingRows = filtered(allRows, query: query)

        switch query.operation {
        case .count:
            return .handled(countCard(query: query, descriptor: descriptor, rows: matchingRows))
        case .list:
            return .handled(listCard(query: query, descriptor: descriptor, rows: matchingRows))
        case .lookup, .detail:
            return .handled(detailCard(query: query, descriptor: descriptor, rows: matchingRows))
        case .sum, .average, .rank, .groupBreakdown, .compare, .simulate:
            return unsupported(query, "That aggregation must use a domain calculator, not the generic model query executor.")
        }
    }

    private func supports(
        _ operation: MarinaUniversalQueryOperation,
        descriptor: MarinaEntityDescriptor
    ) -> Bool {
        let supported = Set(descriptor.supportedOperations.map { $0.lowercased() })
        switch operation {
        case .lookup, .detail:
            return descriptor.isQueryable && supported.contains("lookupdetails")
        case .list:
            return descriptor.isQueryable && supported.contains("list")
        case .count:
            return descriptor.isQueryable && supported.contains("count")
        case .sum, .average, .rank, .groupBreakdown, .compare, .simulate:
            return supported.contains(operation.catalogOperationName.lowercased())
        }
    }

    private func filtered(
        _ rows: [UniversalRow],
        query: MarinaUniversalQueryIR
    ) -> [UniversalRow] {
        rows
            .filter { row in
                guard let range = query.dateRange else { return true }
                guard let date = row.date else { return false }
                return date >= range.startDate && date <= range.endDate
            }
            .filter { row in
                query.filters.allSatisfy { filter in
                    switch filter.match {
                    case .uncategorized:
                        return row.isUncategorized
                    case .exact:
                        return normalized(row.searchText) == normalized(filter.value)
                            || normalized(row.title) == normalized(filter.value)
                    case .contains:
                        return normalized(row.searchText).contains(normalized(filter.value))
                    }
                }
            }
    }

    private func countCard(
        query: MarinaUniversalQueryIR,
        descriptor: MarinaEntityDescriptor,
        rows: [UniversalRow]
    ) -> MarinaWorkspaceAggregationCard {
        let count = rows.count
        return MarinaWorkspaceAggregationCard(
            title: countTitle(descriptor: descriptor, query: query),
            subtitle: scopeLabel(query),
            primaryValue: "\(count)",
            rows: evidenceRows(rows.prefix(limit(for: query))),
            traceSummary: trace(query: query, descriptor: descriptor, resultCount: count)
        )
    }

    private func listCard(
        query: MarinaUniversalQueryIR,
        descriptor: MarinaEntityDescriptor,
        rows: [UniversalRow]
    ) -> MarinaWorkspaceAggregationCard {
        let shown = Array(rows.prefix(limit(for: query)))
        return MarinaWorkspaceAggregationCard(
            title: listTitle(descriptor: descriptor, query: query),
            subtitle: scopeLabel(query),
            primaryValue: shown.isEmpty ? "0" : "\(rows.count)",
            rows: evidenceRows(shown),
            traceSummary: trace(query: query, descriptor: descriptor, resultCount: rows.count)
        )
    }

    private func detailCard(
        query: MarinaUniversalQueryIR,
        descriptor: MarinaEntityDescriptor,
        rows: [UniversalRow]
    ) -> MarinaWorkspaceAggregationCard {
        guard let row = rows.first else {
            let search = query.filters.first?.value
            return MarinaWorkspaceAggregationCard(
                title: "No Matching \(descriptor.displayName)",
                subtitle: search.map { "No \(descriptor.displayName) matched \"\($0)\"." },
                rows: [],
                traceSummary: trace(query: query, descriptor: descriptor, resultCount: 0)
            )
        }

        return MarinaWorkspaceAggregationCard(
            title: "I found \(row.title).",
            subtitle: descriptor.displayName,
            primaryValue: row.amount.map(currency),
            rows: row.detailRows,
            traceSummary: trace(query: query, descriptor: descriptor, resultCount: rows.count)
        )
    }

    private func unsupported(
        _ query: MarinaUniversalQueryIR,
        _ message: String
    ) -> MarinaUniversalQueryExecutionResult {
        .unsupported(
            MarinaTypedUnsupportedResponse(
                kind: .unsupportedCombination,
                message: message,
                candidate: nil
            )
        )
    }

    private func rows(
        for descriptor: MarinaEntityDescriptor,
        provider: MarinaDataProvider
    ) -> [UniversalRow] {
        switch descriptor.entityName {
        case "Workspace":
            return provider.fetchAllWorkspaces().map {
                row(
                    id: $0.id,
                    modelName: descriptor.entityName,
                    objectType: .workspace,
                    title: $0.name,
                    value: "Workspace",
                    details: [("Type", "Workspace"), ("Color", $0.hexColor)]
                )
            }
        default:
            guard let catalog = try? provider.workspaceReadStore.fetchCatalog() else { return [] }
            return scopedRows(for: descriptor.entityName, catalog: catalog)
        }
    }

    private func scopedRows(
        for modelName: String,
        catalog: MarinaWorkspaceReadCatalog
    ) -> [UniversalRow] {
        switch modelName {
        case "Budget":
            return catalog.budgets.map {
                row(id: $0.id, modelName: modelName, objectType: .budget, title: $0.name, value: "\(shortDate($0.startDate))-\(shortDate($0.endDate))", date: $0.startDate, details: [("Type", "Budget"), ("Starts", formatDate($0.startDate)), ("Ends", formatDate($0.endDate))])
            }
        case "BudgetCategoryLimit":
            return catalog.budgetCategoryLimits.map {
                let title = "\($0.category?.name ?? "Uncategorized") limit"
                let value = [$0.minAmount.map { "min \(currency($0))" }, $0.maxAmount.map { "max \(currency($0))" }].compactMap { $0 }.joined(separator: ", ")
                return row(id: $0.id, modelName: modelName, objectType: nil, title: title, value: value.isEmpty ? "Limit" : value, amount: $0.maxAmount ?? $0.minAmount, details: [("Type", "Budget category limit"), ("Budget", $0.budget?.name ?? "Unknown"), ("Category", $0.category?.name ?? "Uncategorized")])
            }
        case "Card":
            return catalog.cards.map {
                row(id: $0.id, modelName: modelName, objectType: .card, title: $0.name, value: "Card", details: [("Type", "Card"), ("Theme", $0.theme), ("Effect", $0.effect)])
            }
        case "BudgetCardLink":
            return catalog.budgetCardLinks.map {
                row(id: $0.id, modelName: modelName, objectType: nil, title: $0.card?.name ?? "Linked card", value: $0.budget?.name ?? "Budget link", date: $0.budget?.startDate, details: [("Type", "Budget card link"), ("Budget", $0.budget?.name ?? "Unknown"), ("Card", $0.card?.name ?? "Unknown")])
            }
        case "BudgetPresetLink":
            return catalog.budgetPresetLinks.map {
                row(id: $0.id, modelName: modelName, objectType: nil, title: $0.preset?.title ?? "Linked preset", value: $0.budget?.name ?? "Budget link", date: $0.budget?.startDate, details: [("Type", "Budget preset link"), ("Budget", $0.budget?.name ?? "Unknown"), ("Preset", $0.preset?.title ?? "Unknown")])
            }
        case "Category":
            return catalog.categories.map {
                row(id: $0.id, modelName: modelName, objectType: .category, title: $0.name, value: "Category", details: [("Type", "Category"), ("Color", $0.hexColor)])
            }
        case "Preset":
            return catalog.presets.map {
                row(id: $0.id, modelName: modelName, objectType: .preset, title: $0.title, value: currency($0.plannedAmount), amount: $0.plannedAmount, details: [("Type", "Preset"), ("Amount", currency($0.plannedAmount)), ("Schedule", $0.frequency.rawValue), ("Status", $0.isArchived ? "Archived" : "Active")])
            }
        case "PlannedExpense":
            return catalog.plannedExpenses.map {
                row(id: $0.id, modelName: modelName, objectType: .plannedExpense, title: $0.title, value: "\(currency($0.effectiveAmount())) • \(shortDate($0.expenseDate))", amount: $0.effectiveAmount(), date: $0.expenseDate, details: [("Type", "Planned expense"), ("Date", formatDate($0.expenseDate)), ("Planned", currency($0.plannedAmount)), ("Actual", $0.actualAmount > 0 ? currency($0.actualAmount) : "Not recorded"), ("Category", $0.category?.name ?? "Uncategorized")], isUncategorized: $0.category == nil)
            }
        case "VariableExpense":
            return catalog.variableExpenses.map {
                row(id: $0.id, modelName: modelName, objectType: .variableExpense, title: $0.descriptionText, value: "\(currency($0.ledgerDisplayAmount())) • \(shortDate($0.transactionDate))", amount: $0.ledgerDisplayAmount(), date: $0.transactionDate, details: [("Type", "Transaction"), ("Date", formatDate($0.transactionDate)), ("Amount", currency($0.ledgerDisplayAmount())), ("Card", $0.card?.name ?? "Unassigned"), ("Category", $0.category?.name ?? "Uncategorized")], isUncategorized: $0.category == nil)
            }
        case "AllocationAccount":
            return catalog.allocationAccounts.map {
                row(id: $0.id, modelName: modelName, objectType: .reconciliationAccount, title: $0.name, value: $0.isArchived ? "Archived" : "Active", details: [("Type", "Reconciliation account"), ("Color", $0.hexColor), ("Status", $0.isArchived ? "Archived" : "Active")])
            }
        case "ExpenseAllocation":
            return catalog.expenseAllocations.map {
                let title = $0.expense?.descriptionText ?? $0.plannedExpense?.title ?? "Expense allocation"
                let date = $0.expense?.transactionDate ?? $0.plannedExpense?.expenseDate
                return row(id: $0.id, modelName: modelName, objectType: .expenseAllocation, title: title, value: currency($0.allocatedAmount), amount: $0.allocatedAmount, date: date, details: [("Type", "Expense allocation"), ("Amount", currency($0.allocatedAmount)), ("Account", $0.account?.name ?? "Unassigned"), ("Expense", title)])
            }
        case "AllocationSettlement":
            return catalog.allocationSettlements.map {
                row(id: $0.id, modelName: modelName, objectType: .reconciliationItem, title: $0.note.isEmpty ? "Reconciliation settlement" : $0.note, value: "\(currency($0.amount)) • \(shortDate($0.date))", amount: $0.amount, date: $0.date, details: [("Type", "Reconciliation settlement"), ("Date", formatDate($0.date)), ("Amount", currency($0.amount)), ("Account", $0.account?.name ?? "Unassigned")])
            }
        case "SavingsAccount":
            return catalog.savingsAccounts.map {
                row(id: $0.id, modelName: modelName, objectType: .savingsAccount, title: $0.name, value: currency($0.total), amount: $0.total, details: [("Type", "Savings account"), ("Balance", currency($0.total))])
            }
        case "SavingsLedgerEntry":
            return catalog.savingsLedgerEntries.map {
                row(id: $0.id, modelName: modelName, objectType: .savingsLedgerEntry, title: $0.note.isEmpty ? $0.kindRaw : $0.note, value: "\(currency($0.amount)) • \(shortDate($0.date))", amount: $0.amount, date: $0.date, details: [("Type", "Savings ledger entry"), ("Date", formatDate($0.date)), ("Amount", currency($0.amount)), ("Account", $0.account?.name ?? "Savings")])
            }
        case "ImportMerchantRule":
            return catalog.importMerchantRules.map {
                row(id: $0.id, modelName: modelName, objectType: .importMerchantRule, title: $0.preferredName ?? $0.merchantKey, value: $0.preferredCategory?.name ?? "No category", details: [("Type", "Import merchant rule"), ("Merchant key", $0.merchantKey), ("Preferred name", $0.preferredName ?? "None"), ("Preferred category", $0.preferredCategory?.name ?? "None")])
            }
        case "AssistantAliasRule":
            return catalog.assistantAliasRules.map {
                row(id: $0.id, modelName: modelName, objectType: .assistantAliasRule, title: $0.aliasKey, value: $0.targetValue, details: [("Type", "Assistant alias"), ("Alias", $0.aliasKey), ("Target", $0.targetValue), ("Entity type", $0.entityType.rawValue)])
            }
        case "IncomeSeries":
            return catalog.incomeSeries.map {
                row(id: $0.id, modelName: modelName, objectType: .incomeSeries, title: $0.source, value: "\(currency($0.amount)) • \($0.frequency.rawValue)", amount: $0.amount, date: $0.startDate, details: [("Type", $0.isPlanned ? "Planned income series" : "Income series"), ("Amount", currency($0.amount)), ("Schedule", $0.frequency.rawValue), ("Starts", formatDate($0.startDate))])
            }
        case "Income":
            return catalog.incomes.map {
                row(id: $0.id, modelName: modelName, objectType: .income, title: $0.source, value: "\(currency($0.amount)) • \(shortDate($0.date))", amount: $0.amount, date: $0.date, details: [("Type", $0.isPlanned ? "Planned income" : "Income"), ("Date", formatDate($0.date)), ("Amount", currency($0.amount))])
            }
        default:
            return []
        }
    }

    private func row(
        id: UUID,
        modelName: String,
        objectType: MarinaLookupObjectType?,
        title: String,
        value: String,
        amount: Double? = nil,
        date: Date? = nil,
        details: [(String, String)],
        isUncategorized: Bool = false
    ) -> UniversalRow {
        UniversalRow(
            id: id,
            modelName: modelName,
            objectType: objectType,
            title: title,
            value: value,
            amount: amount,
            date: date,
            detailRows: details.map { .init(label: $0.0, value: $0.1) },
            isUncategorized: isUncategorized
        )
    }

    private func evidenceRows<S: Sequence>(_ rows: S) -> [MarinaWorkspaceAggregationCard.Row] where S.Element == UniversalRow {
        rows.map {
            MarinaWorkspaceAggregationCard.Row(
                id: $0.id,
                label: $0.title,
                value: $0.value,
                amount: $0.amount,
                date: $0.date,
                objectType: $0.objectType,
                sourceID: $0.id,
                sortValue: $0.date?.timeIntervalSince1970 ?? $0.amount
            )
        }
    }

    private func countTitle(
        descriptor: MarinaEntityDescriptor,
        query: MarinaUniversalQueryIR
    ) -> String {
        "Count of \(pluralDisplayName(descriptor.displayName))"
    }

    private func listTitle(
        descriptor: MarinaEntityDescriptor,
        query: MarinaUniversalQueryIR
    ) -> String {
        "Your \(pluralDisplayName(descriptor.displayName))"
    }

    private func pluralDisplayName(_ value: String) -> String {
        if value.hasSuffix("y") {
            return String(value.dropLast()) + "ies"
        }
        if value.hasSuffix("s") {
            return value
        }
        return value + "s"
    }

    private func scopeLabel(_ query: MarinaUniversalQueryIR) -> String? {
        query.workspaceScopePolicy == .explicitGlobal ? "All workspaces" : "Selected workspace"
    }

    private func trace(
        query: MarinaUniversalQueryIR,
        descriptor: MarinaEntityDescriptor,
        resultCount: Int
    ) -> String {
        [
            "universalQuery=model:\(descriptor.entityName)",
            "operation=\(query.operation.rawValue)",
            "scope=\(query.workspaceScopePolicy.rawValue)",
            "evidence=\(query.evidenceRowType)",
            "resultCount=\(resultCount)"
        ].joined(separator: ",")
    }

    private func limit(for query: MarinaUniversalQueryIR) -> Int {
        min(10, max(1, query.limit ?? 10))
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func currency(_ value: Double) -> String {
        CurrencyFormatter.string(from: value)
    }

    private func formatDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}

private struct UniversalRow: Equatable {
    let id: UUID
    let modelName: String
    let objectType: MarinaLookupObjectType?
    let title: String
    let value: String
    let amount: Double?
    let date: Date?
    let detailRows: [MarinaWorkspaceAggregationCard.Row]
    let isUncategorized: Bool

    var searchText: String {
        ([title, value, modelName] + detailRows.flatMap { [$0.label, $0.value] })
            .joined(separator: " ")
    }
}

private extension String {
    var nilIfBlankForV2: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
struct MarinaUniversalQueryDetector {
    private let catalog: MarinaEntityCatalog
    private let extractor = MarinaEntityCandidateExtractor()

    init(catalog: MarinaEntityCatalog? = nil) {
        self.catalog = catalog ?? .current
    }

    func detect(
        prompt: String,
        candidate: MarinaQueryPlanCandidate,
        provider: MarinaDataProvider,
        now: Date,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> MarinaUniversalQueryIR? {
        let normalizedPrompt = normalized(prompt)
        guard normalizedPrompt.isEmpty == false else { return nil }
        guard shouldAvoidFinanceRoute(normalizedPrompt) == false else { return nil }

        if let descriptor = modelDescriptor(in: normalizedPrompt),
           let operation = operation(in: normalizedPrompt, fallback: candidate.operation),
           shouldAvoidUniversalModelQuery(normalizedPrompt, descriptor: descriptor, operation: operation) == false {
            let detectedFilters = filters(
                in: normalizedPrompt,
                modelName: descriptor.entityName,
                operation: operation,
                prompt: prompt,
                descriptor: descriptor
            )
            return query(
                operation: operation,
                descriptor: descriptor,
                filters: detectedFilters,
                dateRange: dateRange(in: prompt, now: now, defaultPeriodUnit: defaultPeriodUnit),
                dateSource: dateRange(in: prompt, now: now, defaultPeriodUnit: defaultPeriodUnit) == nil ? .none : .promptExplicit,
                limit: explicitLimit(in: normalizedPrompt) ?? candidate.limit,
                presentationShape: operation == .count ? .summaryCard : (operation == .lookup || operation == .detail ? .summaryCard : .relationshipList)
            )
        }

        guard isBareDetailPrompt(normalizedPrompt),
              dateRange(in: prompt, now: now, defaultPeriodUnit: defaultPeriodUnit) == nil,
              let target = bareDetailTarget(from: prompt),
              let descriptor = descriptorForBareTarget(target, provider: provider) else {
            return nil
        }

        return query(
            operation: .detail,
            descriptor: descriptor,
            filters: [MarinaUniversalQueryFilter(value: target, match: .exact)],
            dateRange: nil,
            dateSource: .none,
            limit: 1,
            presentationShape: .summaryCard
        )
    }

    private func query(
        operation: MarinaUniversalQueryOperation,
        descriptor: MarinaEntityDescriptor,
        filters: [MarinaUniversalQueryFilter],
        dateRange: HomeQueryDateRange?,
        dateSource: MarinaDateSource,
        limit: Int?,
        presentationShape: MarinaResponseShape
    ) -> MarinaUniversalQueryIR {
        MarinaUniversalQueryIR(
            operation: operation,
            modelName: descriptor.entityName,
            filters: filters,
            dateRange: dateRange,
            dateSource: dateSource,
            limit: limit,
            workspaceScopePolicy: descriptor.entityName == "Workspace" ? .explicitGlobal : .selectedWorkspace,
            presentationShape: presentationShape,
            evidenceRowType: descriptor.evidenceRowType
        )
    }

    private func operation(
        in normalizedPrompt: String,
        fallback: MarinaCandidateOperation?
    ) -> MarinaUniversalQueryOperation? {
        if normalizedPrompt.hasPrefix("how many ") || normalizedPrompt.hasPrefix("count ") || normalizedPrompt.contains(" count ") {
            return .count
        }
        if normalizedPrompt.contains(" containing ") || normalizedPrompt.contains(" contain ") {
            return .list
        }
        if normalizedPrompt.hasPrefix("find ") {
            return .detail
        }
        if normalizedPrompt.hasPrefix("list ") || normalizedPrompt.hasPrefix("show my ") || normalizedPrompt.hasPrefix("show all ") {
            return .list
        }
        if normalizedPrompt.hasPrefix("show ") {
            return .detail
        }
        switch fallback {
        case .count:
            return .count
        case .listRows:
            return .list
        case .lookupDetails:
            return .detail
        default:
            return nil
        }
    }

    private func modelDescriptor(in normalizedPrompt: String) -> MarinaEntityDescriptor? {
        catalog.descriptors
            .filter { $0.kind == .persistentModel && $0.isQueryable }
            .flatMap { descriptor in
                modelAliases(for: descriptor).map { (descriptor, $0) }
            }
            .sorted {
                if $0.1.count == $1.1.count {
                    return $0.0.entityName < $1.0.entityName
                }
                return $0.1.count > $1.1.count
            }
            .first { _, alias in containsWholePhrase(alias, in: normalizedPrompt) }?
            .0
    }

    private func modelAliases(for descriptor: MarinaEntityDescriptor) -> [String] {
        var aliases: [String] = []

        func append(_ raw: String) {
            let value = normalized(splitCamelCase(raw))
            guard value.isEmpty == false else { return }
            aliases.append(value)
            aliases.append(pluralized(value))
        }

        append(descriptor.entityName)
        append(descriptor.displayName)
        if let lookup = descriptor.lookupObjectType {
            append(lookup.rawValue)
        }

        for alias in semanticAliases(for: descriptor.entityName) {
            append(alias)
        }

        var seen: Set<String> = []
        return aliases.filter { alias in
            guard seen.contains(alias) == false else { return false }
            seen.insert(alias)
            return true
        }
    }

    private func semanticAliases(for entityName: String) -> [String] {
        switch entityName {
        case "BudgetCategoryLimit":
            return ["category limit", "budget limit", "budget category limit"]
        case "BudgetCardLink":
            return ["linked card", "budget card link"]
        case "BudgetPresetLink":
            return ["linked preset", "budget preset link"]
        case "VariableExpense":
            return ["transaction", "purchase", "expense"]
        case "AllocationAccount":
            return ["allocation account", "reconciliation account", "shared balance account"]
        case "AllocationSettlement":
            return ["allocation settlement", "settlement", "reconciliation item", "settlement row"]
        case "SavingsLedgerEntry":
            return ["savings ledger entry", "savings activity", "savings transaction", "savings movement"]
        case "ImportMerchantRule":
            return ["import merchant rule", "merchant rule", "import rule"]
        case "AssistantAliasRule":
            return ["assistant alias rule", "marina alias", "alias rule", "alias"]
        case "IncomeSeries":
            return ["income series", "income schedule", "recurring income"]
        case "Income":
            return ["income entry", "income"]
        case "PlannedExpense":
            return ["planned expense", "planned transaction", "bill"]
        case "ExpenseAllocation":
            return ["expense allocation", "allocation row", "allocation"]
        default:
            return []
        }
    }

    private func filters(
        in normalizedPrompt: String,
        modelName: String,
        operation: MarinaUniversalQueryOperation,
        prompt: String,
        descriptor: MarinaEntityDescriptor
    ) -> [MarinaUniversalQueryFilter] {
        var filters: [MarinaUniversalQueryFilter] = []
        if modelName == "VariableExpense", containsWholePhrase("uncategorized", in: normalizedPrompt) {
            filters.append(MarinaUniversalQueryFilter(value: "Uncategorized", match: .uncategorized))
        }
        if let containsValue = phraseAfter([" containing ", " contain "], in: normalizedPrompt) {
            filters.append(MarinaUniversalQueryFilter(value: containsValue, match: .contains))
        }
        if filters.isEmpty,
           operation == .detail || operation == .lookup,
           let target = bareDetailTarget(from: prompt),
           isOnlyModelReference(target, descriptor: descriptor) == false {
            filters.append(MarinaUniversalQueryFilter(value: target, match: .exact))
        }
        return filters
    }

    private func shouldAvoidUniversalModelQuery(
        _ normalizedPrompt: String,
        descriptor: MarinaEntityDescriptor,
        operation: MarinaUniversalQueryOperation
    ) -> Bool {
        guard descriptor.entityName == "VariableExpense",
              operation == .list || operation == .lookup || operation == .detail,
              normalizedPrompt.hasPrefix("show ") || normalizedPrompt.hasPrefix("list ") || normalizedPrompt.hasPrefix("find ") else {
            return false
        }

        let nounPattern = #"\b(expense|expenses|transaction|transactions|purchase|purchases)\b"#
        guard normalizedPrompt.range(of: nounPattern, options: .regularExpression) != nil else {
            return false
        }

        let cleaned = normalizedPrompt
            .replacingOccurrences(of: #"^(show|list|find)\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\b(my|all|the|a|an|of|for|in|on|with|category|categories|variable)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: nounPattern, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty == false
    }

    private func descriptorForBareTarget(
        _ target: String,
        provider: MarinaDataProvider
    ) -> MarinaEntityDescriptor? {
        let extraction = extractor.extractCandidates(from: target, provider: provider)
        let storedMatches = extraction.matchesByType.flatMap(\.value).filter { match in
            match.matchType == .exact && match.entityType != .merchant && match.entityType != .expense
        }
        guard Set(storedMatches.map(\.entityType)).count == 1,
              let type = storedMatches.first?.entityType else {
            return nil
        }
        switch type {
        case .category:
            return catalog.descriptor(for: "Category")
        case .card:
            return catalog.descriptor(for: "Card")
        case .budget:
            return catalog.descriptor(for: "Budget")
        case .preset:
            return catalog.descriptor(for: "Preset")
        case .incomeSource:
            return catalog.descriptor(for: "Income")
        case .allocationAccount:
            return catalog.descriptor(for: "AllocationAccount")
        case .savingsAccount:
            return catalog.descriptor(for: "SavingsAccount")
        case .merchant, .expense:
            return nil
        }
    }

    private func shouldAvoidFinanceRoute(_ normalizedPrompt: String) -> Bool {
        if normalizedPrompt.contains("savings activity")
            || normalizedPrompt.contains("recent transaction")
            || normalizedPrompt.contains("recent transactions")
            || normalizedPrompt.contains("breakdown")
            || normalizedPrompt.contains("most recent")
            || normalizedPrompt.contains("recent ")
            || normalizedPrompt.contains("latest")
            || normalizedPrompt.contains("newest")
            || normalizedPrompt.contains("next planned expense")
            || normalizedPrompt.contains("next expense")
            || normalizedPrompt.contains("next bill")
            || normalizedPrompt.contains("upcoming planned expense")
            || normalizedPrompt.contains("upcoming expense")
            || normalizedPrompt.range(of: #"\blast\s+\d+\b"#, options: .regularExpression) != nil {
            return true
        }
        if normalizedPrompt.hasPrefix("when ")
            || normalizedPrompt.hasPrefix("what date ")
            || normalizedPrompt.hasPrefix("which date ") {
            return true
        }
        if (normalizedPrompt.contains("budget limit") || normalizedPrompt.contains("category limit"))
            && normalizedPrompt.contains("budget limits") == false
            && normalizedPrompt.contains("category limits") == false {
            return true
        }
        let financeWords = ["spend", "spent", "spending", "average", "top", "largest", "biggest", "compare", " vs ", "versus", "balance", "what if"]
        return financeWords.contains { normalizedPrompt.contains($0) }
    }

    private func isBareDetailPrompt(_ normalizedPrompt: String) -> Bool {
        normalizedPrompt.hasPrefix("show ")
            || normalizedPrompt.hasPrefix("find ")
            || normalizedPrompt.hasPrefix("lookup ")
    }

    private func bareDetailTarget(from prompt: String) -> String? {
        prompt
            .replacingOccurrences(of: #"(?i)^\s*(show|find|lookup)\s+(my\s+)?"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ?."))
            .nilIfBlankForV2
    }

    private func isOnlyModelReference(
        _ target: String,
        descriptor: MarinaEntityDescriptor
    ) -> Bool {
        let normalizedTarget = normalized(target)
        return modelAliases(for: descriptor).contains(normalizedTarget)
    }

    private func phraseAfter(_ delimiters: [String], in normalizedPrompt: String) -> String? {
        for delimiter in delimiters {
            if let range = normalizedPrompt.range(of: delimiter) {
                let suffix = normalizedPrompt[range.upperBound...]
                return String(suffix)
                    .replacingOccurrences(of: #"^(a|an|the)\s+"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfBlankForV2
            }
        }
        return nil
    }

    private func dateRange(
        in prompt: String,
        now: Date,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> HomeQueryDateRange? {
        let normalizedPrompt = normalized(prompt)
        let phrases = [
            "this month", "current month", "month to date", "last month", "previous month",
            "this week", "last week", "today", "yesterday", "this year", "last year"
        ]
        guard let phrase = phrases.first(where: { normalizedPrompt.contains($0) }) else { return nil }
        return MarinaDateResolver(calendar: Calendar(identifier: .gregorian), nowProvider: { now })
            .resolve(input: phrase, modelStartISO8601: nil, modelEndISO8601: nil, defaultPeriodUnit: defaultPeriodUnit)?
            .queryDateRange
    }

    private func explicitLimit(in normalizedPrompt: String) -> Int? {
        guard let range = normalizedPrompt.range(of: #"\b\d{1,2}\b"#, options: .regularExpression) else {
            return nil
        }
        return Int(normalizedPrompt[range])
    }

    private func containsWholePhrase(_ phrase: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        return text.range(of: #"(^|\s)\#(escaped)($|\s)"#, options: .regularExpression) != nil
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func splitCamelCase(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"([a-z0-9])([A-Z])"#, with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: #"([A-Z])([A-Z][a-z])"#, with: "$1 $2", options: .regularExpression)
    }

    private func pluralized(_ value: String) -> String {
        if value.hasSuffix("y") {
            return String(value.dropLast()) + "ies"
        }
        if value.hasSuffix("s") {
            return value
        }
        return value + "s"
    }
}
