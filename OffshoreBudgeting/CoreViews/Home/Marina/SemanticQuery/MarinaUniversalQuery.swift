import Foundation

enum MarinaUniversalQueryOperation: String, Codable, Equatable, CaseIterable, Sendable {
    case lookup
    case list
    case count
    case sum
    case average
    case minimum
    case maximum
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
        case .minimum:
            return "minimum"
        case .maximum:
            return "maximum"
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
              descriptor.kind == .persistentModel || descriptor.entityName == "Virtual: Merchant" else {
            return unsupported(query, "That data type is not available to Marina's universal query catalog.")
        }

        guard supports(query.operation, descriptor: descriptor) else {
            return unsupported(query, "Universal \(query.operation.rawValue) is not supported for \(descriptor.displayName).")
        }

        let allRows = rows(for: descriptor, provider: provider, query: query)
        let matchingRows = filtered(allRows, query: query)

        switch query.operation {
        case .count:
            return .handled(countCard(query: query, descriptor: descriptor, rows: matchingRows))
        case .list:
            return .handled(listCard(query: query, descriptor: descriptor, rows: matchingRows))
        case .lookup, .detail:
            return .handled(detailCard(query: query, descriptor: descriptor, rows: matchingRows))
        case .sum:
            return aggregate(query: query, descriptor: descriptor, rows: matchingRows, mode: .sum)
        case .average:
            return aggregate(query: query, descriptor: descriptor, rows: matchingRows, mode: .average)
        case .minimum:
            return aggregate(query: query, descriptor: descriptor, rows: matchingRows, mode: .minimum)
        case .maximum:
            return aggregate(query: query, descriptor: descriptor, rows: matchingRows, mode: .maximum)
        case .rank:
            return .handled(rankCard(query: query, descriptor: descriptor, rows: matchingRows))
        case .groupBreakdown:
            return .handled(groupBreakdownCard(query: query, descriptor: descriptor, rows: matchingRows))
        case .compare:
            return compare(query: query, descriptor: descriptor, rows: allRows)
        case .simulate:
            return unsupported(query, "Simulation must use a domain calculator, not the generic model query executor.")
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
        case .sum, .average, .minimum, .maximum, .rank, .groupBreakdown, .compare:
            return descriptor.isQueryable
                && descriptor.amountFields.isEmpty == false
                && (
                    descriptor.isAggregatable
                    || supported.contains(operation.catalogOperationName.lowercased())
                    || supported.contains("total")
                    || supported.contains("balance")
                )
        case .simulate:
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
                    if let field = filter.field?.marinaNilIfBlank {
                        return fieldMatches(filter, row: row, field: field)
                    }
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

    private func fieldMatches(
        _ filter: MarinaUniversalQueryFilter,
        row: UniversalRow,
        field: String
    ) -> Bool {
        let key = normalized(field)
        let haystack = row.attributes[key] ?? row.detailRows.first {
            normalized($0.label) == key
        }?.value

        guard let haystack else { return false }

        switch filter.match {
        case .uncategorized:
            return row.isUncategorized
        case .exact:
            return normalized(haystack) == normalized(filter.value)
        case .contains:
            return normalized(haystack).contains(normalized(filter.value))
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
        let sortedRows: [UniversalRow]
        switch query.ranking {
        case .newest:
            sortedRows = rows.sorted { lhs, rhs in
                switch (lhs.date, rhs.date) {
                case (.some(let lhsDate), .some(let rhsDate)):
                    if lhsDate == rhsDate { return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending }
                    return lhsDate > rhsDate
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            }
        default:
            sortedRows = rows
        }
        let shown = Array(sortedRows.prefix(limit(for: query)))
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
            rows: [
                MarinaWorkspaceAggregationCard.Row(
                    label: row.title,
                    value: row.value,
                    amount: row.amount,
                    date: row.date,
                    objectType: row.objectType,
                    sourceID: row.id,
                    sortValue: row.amount
                )
            ] + row.detailRows,
            traceSummary: trace(query: query, descriptor: descriptor, resultCount: rows.count)
        )
    }

    private enum AggregateMode {
        case sum
        case average
        case minimum
        case maximum
    }

    private func aggregate(
        query: MarinaUniversalQueryIR,
        descriptor: MarinaEntityDescriptor,
        rows: [UniversalRow],
        mode: AggregateMode
    ) -> MarinaUniversalQueryExecutionResult {
        let amountRows = rows.filter { $0.amount != nil }
        guard amountRows.isEmpty == false else {
            return unsupported(query, "\(descriptor.displayName) does not expose a numeric amount for \(query.operation.rawValue).")
        }

        let values = amountRows.compactMap(\.amount)
        let amount: Double
        let title: String
        switch mode {
        case .sum:
            amount = values.reduce(0, +)
            title = "Total \(descriptor.displayName)"
        case .average:
            amount = values.reduce(0, +) / Double(values.count)
            title = "Average \(descriptor.displayName)"
        case .minimum:
            amount = values.min() ?? 0
            title = "Minimum \(descriptor.displayName)"
        case .maximum:
            amount = values.max() ?? 0
            title = "Maximum \(descriptor.displayName)"
        }

        return .handled(
            MarinaWorkspaceAggregationCard(
                title: title,
                subtitle: scopeLabel(query),
                primaryValue: currency(amount),
                rows: evidenceRows(amountRows.sorted { abs($0.amount ?? 0) > abs($1.amount ?? 0) }.prefix(limit(for: query))),
                traceSummary: trace(query: query, descriptor: descriptor, resultCount: amountRows.count)
            )
        )
    }

    private func rankCard(
        query: MarinaUniversalQueryIR,
        descriptor: MarinaEntityDescriptor,
        rows: [UniversalRow]
    ) -> MarinaWorkspaceAggregationCard {
        let ranked = rows
            .filter { $0.amount != nil }
            .sorted { lhs, rhs in
                switch query.ranking {
                case .newest:
                    switch (lhs.date, rhs.date) {
                    case (.some(let lhsDate), .some(let rhsDate)):
                        if lhsDate == rhsDate { return (lhs.amount ?? 0) > (rhs.amount ?? 0) }
                        return lhsDate > rhsDate
                    case (.some, .none):
                        return true
                    case (.none, .some):
                        return false
                    case (.none, .none):
                        return (lhs.amount ?? 0) > (rhs.amount ?? 0)
                    }
                case .smallest, .bottom, .leastFrequent:
                    return (lhs.amount ?? 0) < (rhs.amount ?? 0)
                case .top, .largest, .mostFrequent, nil:
                    return (lhs.amount ?? 0) > (rhs.amount ?? 0)
                }
            }
            .prefix(limit(for: query))

        return MarinaWorkspaceAggregationCard(
            title: "Ranked \(pluralDisplayName(descriptor.displayName))",
            subtitle: scopeLabel(query),
            primaryValue: ranked.first?.amount.map(currency),
            rows: evidenceRows(ranked),
            traceSummary: trace(query: query, descriptor: descriptor, resultCount: rows.count)
        )
    }

    private func groupBreakdownCard(
        query: MarinaUniversalQueryIR,
        descriptor: MarinaEntityDescriptor,
        rows: [UniversalRow]
    ) -> MarinaWorkspaceAggregationCard {
        let key = query.grouping?.marinaNilIfBlank.map(normalized) ?? defaultGroupingKey(for: descriptor)
        var groups: [String: Double] = [:]

        for row in rows {
            guard let amount = row.amount else { continue }
            let label = groupLabel(row: row, key: key)
            groups[label, default: 0] += amount
        }

        let ranked = groups
            .map { (label: $0.key, amount: $0.value) }
            .sorted { lhs, rhs in
                if lhs.amount == rhs.amount {
                    return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
                }
                return lhs.amount > rhs.amount
            }
            .prefix(limit(for: query))

        return MarinaWorkspaceAggregationCard(
            title: "\(descriptor.displayName) Breakdown",
            subtitle: scopeLabel(query),
            primaryValue: currency(groups.values.reduce(0, +)),
            rows: ranked.map {
                MarinaWorkspaceAggregationCard.Row(
                    label: $0.label,
                    value: currency($0.amount),
                    amount: $0.amount,
                    sortValue: $0.amount
                )
            },
            traceSummary: trace(query: query, descriptor: descriptor, resultCount: groups.count)
        )
    }

    private func compare(
        query: MarinaUniversalQueryIR,
        descriptor: MarinaEntityDescriptor,
        rows: [UniversalRow]
    ) -> MarinaUniversalQueryExecutionResult {
        guard let currentRange = query.dateRange else {
            return unsupported(query, "A comparison needs a date range.")
        }

        let previousRange = previousEquivalentRange(to: currentRange)
        let currentRows = filtered(rows, query: query)
        let previousRows = filtered(
            rows,
            query: MarinaUniversalQueryIR(
                operation: query.operation,
                modelName: query.modelName,
                filters: query.filters,
                relationships: query.relationships,
                amountBasis: query.amountBasis,
                dateRange: previousRange,
                dateSource: query.dateSource,
                grouping: query.grouping,
                ranking: query.ranking,
                limit: query.limit,
                workspaceScopePolicy: query.workspaceScopePolicy,
                presentationShape: query.presentationShape,
                evidenceRowType: query.evidenceRowType
            )
        )
        let current = currentRows.compactMap(\.amount).reduce(0, +)
        let previous = previousRows.compactMap(\.amount).reduce(0, +)
        let delta = current - previous

        return .handled(
            MarinaWorkspaceAggregationCard(
                title: "\(descriptor.displayName) Comparison",
                subtitle: "\(rangeLabel(currentRange)) vs \(rangeLabel(previousRange))",
                primaryValue: currency(current),
                rows: [
                    .init(label: "Current period", value: currency(current), amount: current, sortValue: current),
                    .init(label: "Previous period", value: currency(previous), amount: previous, sortValue: previous),
                    .init(label: "Change", value: signedCurrency(delta), amount: delta, sortValue: delta)
                ],
                traceSummary: trace(query: query, descriptor: descriptor, resultCount: currentRows.count)
            )
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
        provider: MarinaDataProvider,
        query: MarinaUniversalQueryIR
    ) -> [UniversalRow] {
        switch descriptor.entityName {
        case "Workspace":
            if query.workspaceScopePolicy == .selectedWorkspace {
                guard let workspace = provider.fetchWorkspace() else { return [] }
                return [
                    row(
                        id: workspace.id,
                        modelName: descriptor.entityName,
                        objectType: .workspace,
                        title: workspace.name,
                        value: "Current workspace",
                        details: [("Type", "Workspace"), ("Color", workspace.hexColor)],
                        attributes: ["scope": "selected", "type": "workspace"]
                    )
                ]
            }
            return provider.fetchAllWorkspaces().map {
                row(
                    id: $0.id,
                    modelName: descriptor.entityName,
                    objectType: .workspace,
                    title: $0.name,
                    value: "Workspace",
                    details: [("Type", "Workspace"), ("Color", $0.hexColor)],
                    attributes: ["scope": "global", "type": "workspace"]
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
                row(id: $0.id, modelName: modelName, objectType: .budget, title: $0.name, value: "\(shortDate($0.startDate))-\(shortDate($0.endDate))", date: $0.startDate, details: [("Type", "Budget"), ("Starts", formatDate($0.startDate)), ("Ends", formatDate($0.endDate))], attributes: ["type": "budget"])
            }
        case "BudgetCategoryLimit":
            return catalog.budgetCategoryLimits.map {
                let title = "\($0.category?.name ?? "Uncategorized") limit"
                let value = [$0.minAmount.map { "min \(currency($0))" }, $0.maxAmount.map { "max \(currency($0))" }].compactMap { $0 }.joined(separator: ", ")
                return row(id: $0.id, modelName: modelName, objectType: nil, title: title, value: value.isEmpty ? "Limit" : value, amount: $0.maxAmount ?? $0.minAmount, details: [("Type", "Budget category limit"), ("Budget", $0.budget?.name ?? "Unknown"), ("Category", $0.category?.name ?? "Uncategorized")], attributes: ["budget": $0.budget?.name ?? "Unknown", "category": $0.category?.name ?? "Uncategorized", "type": "budget category limit"])
            }
        case "Card":
            return catalog.cards.map {
                row(id: $0.id, modelName: modelName, objectType: .card, title: $0.name, value: "Card", details: [("Type", "Card"), ("Theme", $0.theme), ("Effect", $0.effect)], attributes: ["type": "card"])
            }
        case "BudgetCardLink":
            return catalog.budgetCardLinks.map {
                row(id: $0.id, modelName: modelName, objectType: nil, title: $0.card?.name ?? "Linked card", value: $0.budget?.name ?? "Budget link", date: $0.budget?.startDate, details: [("Type", "Budget card link"), ("Budget", $0.budget?.name ?? "Unknown"), ("Card", $0.card?.name ?? "Unknown")], attributes: ["budget": $0.budget?.name ?? "Unknown", "card": $0.card?.name ?? "Unknown", "type": "budget card link"])
            }
        case "BudgetPresetLink":
            return catalog.budgetPresetLinks.map {
                row(id: $0.id, modelName: modelName, objectType: nil, title: $0.preset?.title ?? "Linked preset", value: $0.budget?.name ?? "Budget link", date: $0.budget?.startDate, details: [("Type", "Budget preset link"), ("Budget", $0.budget?.name ?? "Unknown"), ("Preset", $0.preset?.title ?? "Unknown")], attributes: ["budget": $0.budget?.name ?? "Unknown", "preset": $0.preset?.title ?? "Unknown", "type": "budget preset link"])
            }
        case "Category":
            return catalog.categories.map {
                row(id: $0.id, modelName: modelName, objectType: .category, title: $0.name, value: "Category", details: [("Type", "Category"), ("Color", $0.hexColor)], attributes: ["type": "category"])
            }
        case "Preset":
            return catalog.presets.map {
                row(id: $0.id, modelName: modelName, objectType: .preset, title: $0.title, value: currency($0.plannedAmount), amount: $0.plannedAmount, details: [("Type", "Preset"), ("Amount", currency($0.plannedAmount)), ("Schedule", $0.frequency.rawValue), ("Status", $0.isArchived ? "Archived" : "Active")], attributes: ["status": $0.isArchived ? "archived" : "active", "schedule": $0.frequency.rawValue, "type": "preset"])
            }
        case "PlannedExpense":
            return catalog.plannedExpenses.map {
                row(id: $0.id, modelName: modelName, objectType: .plannedExpense, title: $0.title, value: "\(currency($0.effectiveAmount())) • \(shortDate($0.expenseDate))", amount: $0.effectiveAmount(), date: $0.expenseDate, details: [("Type", "Planned expense"), ("Date", formatDate($0.expenseDate)), ("Planned", currency($0.plannedAmount)), ("Actual", $0.actualAmount > 0 ? currency($0.actualAmount) : "Not recorded"), ("Card", $0.card?.name ?? "Unassigned"), ("Category", $0.category?.name ?? "Uncategorized")], attributes: ["card": $0.card?.name ?? "Unassigned", "category": $0.category?.name ?? "Uncategorized", "type": "planned expense"], isUncategorized: $0.category == nil)
            }
        case "VariableExpense":
            return catalog.variableExpenses.map {
                row(id: $0.id, modelName: modelName, objectType: .variableExpense, title: $0.descriptionText, value: "\(currency(SavingsMathService.variableBudgetImpactAmount(for: $0))) • \(shortDate($0.transactionDate))", amount: SavingsMathService.variableBudgetImpactAmount(for: $0), date: $0.transactionDate, details: [("Type", "Transaction"), ("Date", formatDate($0.transactionDate)), ("Amount", currency(SavingsMathService.variableBudgetImpactAmount(for: $0))), ("Card", $0.card?.name ?? "Unassigned"), ("Category", $0.category?.name ?? "Uncategorized"), ("Merchant", MerchantNormalizer.displayName($0.descriptionText)), ("Kind", $0.kindRaw)], attributes: ["card": $0.card?.name ?? "Unassigned", "category": $0.category?.name ?? "Uncategorized", "merchant": MerchantNormalizer.displayName($0.descriptionText), "kind": $0.kindRaw, "type": "transaction"], isUncategorized: $0.category == nil)
            }
        case "Virtual: Merchant":
            let grouped = Dictionary(grouping: catalog.variableExpenses) {
                MerchantNormalizer.displayName($0.descriptionText)
            }
            return grouped.compactMap { merchant, expenses in
                guard merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                      let representative = expenses.sorted(by: { $0.transactionDate > $1.transactionDate }).first else {
                    return nil
                }
                let total = expenses.reduce(0.0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }
                return row(
                    id: representative.id,
                    modelName: modelName,
                    objectType: .variableExpense,
                    title: merchant,
                    value: "\(expenses.count) transaction\(expenses.count == 1 ? "" : "s")",
                    amount: total,
                    date: representative.transactionDate,
                    details: [
                        ("Type", "Merchant"),
                        ("Transactions", "\(expenses.count)"),
                        ("Total", currency(total)),
                        ("Latest", formatDate(representative.transactionDate))
                    ],
                    attributes: ["merchant": merchant, "type": "merchant"]
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case "AllocationAccount":
            return catalog.allocationAccounts.map {
                row(id: $0.id, modelName: modelName, objectType: .reconciliationAccount, title: $0.name, value: currency(AllocationLedgerService.balance(for: $0)), amount: AllocationLedgerService.balance(for: $0), details: [("Type", "Reconciliation account"), ("Color", $0.hexColor), ("Status", $0.isArchived ? "Archived" : "Active"), ("Balance", currency(AllocationLedgerService.balance(for: $0)))], attributes: ["status": $0.isArchived ? "archived" : "active", "type": "reconciliation account"])
            }
        case "ExpenseAllocation":
            return catalog.expenseAllocations.map {
                let title = $0.expense?.descriptionText ?? $0.plannedExpense?.title ?? "Expense allocation"
                let date = $0.expense?.transactionDate ?? $0.plannedExpense?.expenseDate
                return row(id: $0.id, modelName: modelName, objectType: .expenseAllocation, title: title, value: currency($0.allocatedAmount), amount: $0.allocatedAmount, date: date, details: [("Type", "Expense allocation"), ("Amount", currency($0.allocatedAmount)), ("Account", $0.account?.name ?? "Unassigned"), ("Expense", title)], attributes: ["account": $0.account?.name ?? "Unassigned", "type": "expense allocation"])
            }
        case "AllocationSettlement":
            return catalog.allocationSettlements.map {
                row(id: $0.id, modelName: modelName, objectType: .reconciliationItem, title: $0.note.isEmpty ? "Reconciliation settlement" : $0.note, value: "\(currency($0.amount)) • \(shortDate($0.date))", amount: $0.amount, date: $0.date, details: [("Type", "Reconciliation settlement"), ("Date", formatDate($0.date)), ("Amount", currency($0.amount)), ("Account", $0.account?.name ?? "Unassigned")], attributes: ["account": $0.account?.name ?? "Unassigned", "type": "reconciliation settlement"])
            }
        case "SavingsAccount":
            return catalog.savingsAccounts.map {
                row(id: $0.id, modelName: modelName, objectType: .savingsAccount, title: $0.name, value: currency($0.total), amount: $0.total, details: [("Type", "Savings account"), ("Balance", currency($0.total))], attributes: ["type": "savings account"])
            }
        case "SavingsLedgerEntry":
            return catalog.savingsLedgerEntries.map {
                row(id: $0.id, modelName: modelName, objectType: .savingsLedgerEntry, title: $0.note.isEmpty ? $0.kindRaw : $0.note, value: "\(currency($0.amount)) • \(shortDate($0.date))", amount: $0.amount, date: $0.date, details: [("Type", "Savings ledger entry"), ("Date", formatDate($0.date)), ("Amount", currency($0.amount)), ("Account", $0.account?.name ?? "Savings"), ("Kind", $0.kindRaw)], attributes: ["account": $0.account?.name ?? "Savings", "kind": $0.kindRaw, "type": "savings ledger entry"])
            }
        case "ImportMerchantRule":
            return catalog.importMerchantRules.map {
                row(id: $0.id, modelName: modelName, objectType: .importMerchantRule, title: $0.preferredName ?? $0.merchantKey, value: $0.preferredCategory?.name ?? "No category", details: [("Type", "Import merchant rule"), ("Merchant key", $0.merchantKey), ("Preferred name", $0.preferredName ?? "None"), ("Preferred category", $0.preferredCategory?.name ?? "None")], attributes: ["category": $0.preferredCategory?.name ?? "None", "type": "import merchant rule"])
            }
        case "AssistantAliasRule":
            return catalog.assistantAliasRules.map {
                row(id: $0.id, modelName: modelName, objectType: .assistantAliasRule, title: $0.aliasKey, value: $0.targetValue, details: [("Type", "Assistant alias"), ("Alias", $0.aliasKey), ("Target", $0.targetValue), ("Entity type", $0.entityType.rawValue)], attributes: ["entity type": $0.entityType.rawValue, "type": "assistant alias"])
            }
        case "IncomeSeries":
            return catalog.incomeSeries.map {
                row(id: $0.id, modelName: modelName, objectType: .incomeSeries, title: $0.source, value: "\(currency($0.amount)) • \($0.frequency.rawValue)", amount: $0.amount, date: $0.startDate, details: [("Type", $0.isPlanned ? "Planned income series" : "Income series"), ("Amount", currency($0.amount)), ("Schedule", $0.frequency.rawValue), ("Starts", formatDate($0.startDate))], attributes: ["source": $0.source, "income status": $0.isPlanned ? "planned" : "actual", "schedule": $0.frequency.rawValue, "type": "income series"])
            }
        case "Income":
            return catalog.incomes.map {
                row(id: $0.id, modelName: modelName, objectType: .income, title: $0.source, value: "\(currency($0.amount)) • \(shortDate($0.date))", amount: $0.amount, date: $0.date, details: [("Type", $0.isPlanned ? "Planned income" : "Actual income"), ("Date", formatDate($0.date)), ("Amount", currency($0.amount))], attributes: ["source": $0.source, "income status": $0.isPlanned ? "planned" : "actual", "is planned": $0.isPlanned ? "true" : "false", "type": "income"])
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
        attributes: [String: String] = [:],
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
            attributes: normalizedAttributes(attributes),
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

    private func rangeLabel(_ range: HomeQueryDateRange) -> String {
        "\(shortDate(range.startDate))-\(shortDate(range.endDate))"
    }

    private func signedCurrency(_ value: Double) -> String {
        if value > 0 { return "+\(currency(value))" }
        if value < 0 { return "-\(currency(abs(value)))" }
        return currency(0)
    }

    private func previousEquivalentRange(to range: HomeQueryDateRange) -> HomeQueryDateRange {
        let duration = range.endDate.timeIntervalSince(range.startDate)
        let previousEnd = range.startDate.addingTimeInterval(-1)
        return HomeQueryDateRange(
            startDate: previousEnd.addingTimeInterval(-duration),
            endDate: previousEnd
        )
    }

    private func defaultGroupingKey(for descriptor: MarinaEntityDescriptor) -> String {
        switch descriptor.entityName {
        case "Income", "IncomeSeries":
            return "source"
        case "VariableExpense", "PlannedExpense", "BudgetCategoryLimit":
            return "category"
        case "ExpenseAllocation", "AllocationSettlement", "SavingsLedgerEntry":
            return "account"
        default:
            return "type"
        }
    }

    private func groupLabel(row: UniversalRow, key: String) -> String {
        row.attributes[key]?.marinaNilIfBlank
            ?? row.detailRows.first { normalized($0.label) == key }?.value.marinaNilIfBlank
            ?? "Other"
    }

    private func normalizedAttributes(_ attributes: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: attributes.map { (normalized($0.key), $0.value) })
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
    let attributes: [String: String]
    let isUncategorized: Bool

    var searchText: String {
        ([title, value, modelName] + detailRows.flatMap { [$0.label, $0.value] })
            .joined(separator: " ")
    }
}

private extension String {
    var marinaNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum MarinaUniversalIntentAdjudication: Equatable {
    case original
    case universal(MarinaUniversalQueryIR, reason: String)
}

enum MarinaSemanticCatalogCompilation: Equatable {
    case none
    case universal(MarinaUniversalQueryIR, reason: String)
    case formula(MarinaFormulaIR, reason: String)
    case clarification(MarinaTypedClarification)
    case unsupported(MarinaTypedUnsupportedResponse)
}

enum MarinaAnswerPlanExecutable: Equatable {
    case universal(MarinaUniversalQueryIR)
    case formula(MarinaFormulaIR)
}

struct MarinaAnswerPlanMetadata: Equatable {
    let confidence: MarinaCandidateConfidence
    let amountBasis: MarinaAmountField?
    let dateSource: MarinaDateSource
    let refinementChoices: [MarinaClarificationChoice]

    init(
        confidence: MarinaCandidateConfidence,
        amountBasis: MarinaAmountField? = nil,
        dateSource: MarinaDateSource = .none,
        refinementChoices: [MarinaClarificationChoice] = []
    ) {
        self.confidence = confidence
        self.amountBasis = amountBasis
        self.dateSource = dateSource
        self.refinementChoices = refinementChoices
    }
}

enum MarinaAnswerPlan: Equatable {
    case original
    case execute(MarinaAnswerPlanExecutable, metadata: MarinaAnswerPlanMetadata, reason: String)
    case clarify(MarinaTypedClarification, reason: String)
    case refuse(MarinaTypedUnsupportedResponse, reason: String)
}

@MainActor
struct MarinaAnswerPlanner {
    private let compiler: MarinaSemanticCatalogCompiler

    init(catalog: MarinaEntityCatalog? = nil) {
        compiler = MarinaSemanticCatalogCompiler(catalog: catalog)
    }

    func plan(
        prompt: String,
        interpretation: MarinaTurnInterpretation,
        candidate: MarinaQueryPlanCandidate,
        outcome: MarinaPlanValidationOutcome,
        context: MarinaTurnContext
    ) -> MarinaAnswerPlan {
        switch compiler.compile(
            prompt: prompt,
            interpretation: interpretation,
            candidate: candidate,
            outcome: outcome,
            context: context
        ) {
        case .universal(let query, let reason):
            return .execute(
                .universal(query),
                metadata: MarinaAnswerPlanMetadata(
                    confidence: candidate.confidence,
                    amountBasis: query.amountBasis,
                    dateSource: query.dateSource,
                    refinementChoices: refinementChoices(from: outcome)
                ),
                reason: reason
            )
        case .formula(let formulaIR, let reason):
            return .execute(
                .formula(formulaIR),
                metadata: MarinaAnswerPlanMetadata(
                    confidence: candidate.confidence,
                    refinementChoices: refinementChoices(from: outcome)
                ),
                reason: reason
            )
        case .clarification(let clarification):
            return .clarify(clarification, reason: "semanticCatalogCompilerClarification")
        case .unsupported(let unsupported):
            return .refuse(unsupported, reason: "semanticCatalogCompilerUnsupported")
        case .none:
            return .original
        }
    }

    private func refinementChoices(from outcome: MarinaPlanValidationOutcome) -> [MarinaClarificationChoice] {
        if case .clarification(let clarification) = outcome {
            return clarification.actionableChoices
        }
        return []
    }
}

@MainActor
struct MarinaUniversalIntentAdjudicator {
    private let compiler: MarinaSemanticCatalogCompiler

    init(catalog: MarinaEntityCatalog? = nil) {
        compiler = MarinaSemanticCatalogCompiler(catalog: catalog)
    }

    func adjudicate(
        interpretation: MarinaTurnInterpretation,
        prompt: String,
        candidate: MarinaQueryPlanCandidate,
        outcome: MarinaPlanValidationOutcome,
        context: MarinaTurnContext
    ) -> MarinaUniversalIntentAdjudication {
        switch compiler.compile(
            prompt: prompt,
            interpretation: interpretation,
            candidate: candidate,
            outcome: outcome,
            context: context
        ) {
        case .universal(let query, let reason):
            return .universal(query, reason: reason)
        case .none, .formula, .clarification, .unsupported:
            return .original
        }
    }
}

@MainActor
struct MarinaSemanticCatalogCompiler {
    private let catalog: MarinaEntityCatalog

    init(catalog: MarinaEntityCatalog? = nil) {
        self.catalog = catalog ?? .current
    }

    func compile(
        prompt: String,
        interpretation: MarinaTurnInterpretation,
        candidate: MarinaQueryPlanCandidate,
        outcome: MarinaPlanValidationOutcome,
        context: MarinaTurnContext
    ) -> MarinaSemanticCatalogCompilation {
        guard isSafeReadPrompt(prompt) else {
            return .none
        }

        let normalizedPrompt = normalized(prompt)
        guard let descriptor = descriptor(
            for: normalizedPrompt,
            interpretation: interpretation,
            candidate: candidate
        ) else {
            return .none
        }

        let operation = operation(
            for: normalizedPrompt,
            descriptor: descriptor,
            interpretation: interpretation,
            candidate: candidate
        )
        guard shouldAdjudicate(
            interpretation: interpretation,
            candidate: candidate,
            outcome: outcome,
            normalizedPrompt: normalizedPrompt,
            descriptor: descriptor,
            operation: operation
        ) else {
            return .none
        }
        guard supports(operation, descriptor: descriptor) else {
            return .none
        }

        let dateRange = dateRange(
            in: prompt,
            candidate: candidate,
            context: context
        )
        let query = MarinaUniversalQueryIR(
            operation: operation,
            modelName: descriptor.entityName,
            filters: filters(
                in: normalizedPrompt,
                interpretation: interpretation,
                candidate: candidate,
                descriptor: descriptor,
                operation: operation
            ),
            amountBasis: amountBasis(for: descriptor, normalizedPrompt: normalizedPrompt),
            dateRange: dateRange,
            dateSource: dateRange == nil ? .none : .promptExplicit,
            grouping: grouping(
                in: normalizedPrompt,
                interpretation: interpretation,
                candidate: candidate,
                descriptor: descriptor
            ),
            ranking: ranking(in: normalizedPrompt, candidate: candidate),
            limit: MarinaResultLimitExtractor().limit(in: prompt) ?? candidate.limit,
            workspaceScopePolicy: workspaceScopePolicy(for: descriptor, normalizedPrompt: normalizedPrompt),
            presentationShape: responseShape(for: operation),
            evidenceRowType: descriptor.evidenceRowType
        )
        return .universal(
            query,
            reason: "semanticCatalogCompiler:model:\(descriptor.entityName):operation:\(operation.rawValue)"
        )
    }

    private func shouldAdjudicate(
        interpretation: MarinaTurnInterpretation,
        candidate: MarinaQueryPlanCandidate,
        outcome: MarinaPlanValidationOutcome,
        normalizedPrompt: String,
        descriptor: MarinaEntityDescriptor,
        operation: MarinaUniversalQueryOperation
    ) -> Bool {
        if selectedWorkspaceIdentityQuestion(normalizedPrompt, descriptor: descriptor) == false,
           hasExplicitNamedTargetSignal(in: normalizedPrompt) {
            return false
        }

        switch interpretation.result {
        case .unsupported:
            return true
        case .clarification(let clarification):
            return clarification.actionableChoices.count <= 1
                || canCompileThroughClarification(
                    clarification,
                    normalizedPrompt: normalizedPrompt,
                    descriptor: descriptor,
                    operation: operation
                )
        case .query:
            if case .unsupported = outcome { return true }
            if case .clarification(let clarification) = outcome {
                return canCompileThroughClarification(
                    clarification,
                    normalizedPrompt: normalizedPrompt,
                    descriptor: descriptor,
                    operation: operation
                )
            }
            if case .executable = outcome {
                return hasSpecializedRoute(candidate: candidate) == false
            }
            return false
        }
    }

    private func canCompileThroughClarification(
        _ clarification: MarinaTypedClarification,
        normalizedPrompt: String,
        descriptor: MarinaEntityDescriptor,
        operation: MarinaUniversalQueryOperation
    ) -> Bool {
        switch clarification.kind {
        case .missingTarget, .lowConfidence:
            break
        case .ambiguousTarget, .missingDateRange, .ambiguousDateRange, .unsupportedShape:
            return false
        }

        if selectedWorkspaceIdentityQuestion(normalizedPrompt, descriptor: descriptor) {
            return true
        }

        guard operation != .detail, operation != .lookup else {
            return false
        }
        return hasExplicitNamedTargetSignal(in: normalizedPrompt) == false
    }

    private func isSafeReadPrompt(_ prompt: String) -> Bool {
        guard MarinaRoutePatternRegistry.isReadOnlyStep5Mutation(prompt) == nil else {
            return false
        }
        let normalizedPrompt = normalized(prompt)
        let adviceTerms = [
            "should i invest", "should i buy", "should i sell", "financial advice",
            "investment advice", "tax advice", "legal advice", "credit advice",
            "insurance advice"
        ]
        return adviceTerms.contains { normalizedPrompt.contains($0) } == false
    }

    private func descriptor(
        for normalizedPrompt: String,
        interpretation: MarinaTurnInterpretation,
        candidate: MarinaQueryPlanCandidate
    ) -> MarinaEntityDescriptor? {
        if let detailDescriptor = descriptorFromRequestedDetail(
            requestedDetail(from: interpretation, candidate: candidate)
        ) {
            return detailDescriptor
        }

        let rankedMatches = rankedDescriptorMatches(in: normalizedPrompt)
        if let promptMatch = rankedMatches.first,
           shouldPreferPromptDescriptor(promptMatch, interpretation: interpretation, candidate: candidate) {
            return promptMatch.descriptor
        }

        if let semanticQuery = semanticQuery(from: interpretation),
           let descriptor = catalog.descriptor(for: entityName(for: semanticQuery.subject)) {
            return descriptor
        }
        if let descriptor = descriptor(from: candidate.semanticCommand?.datasets.first) {
            return descriptor
        }

        if semanticWorkspaceReference(in: normalizedPrompt) {
            return catalog.descriptor(for: "Workspace")
        }
        if descriptorMatches("Income", normalizedPrompt: normalizedPrompt) {
            return catalog.descriptor(for: "Income")
        }
        if descriptorMatches("SavingsLedgerEntry", normalizedPrompt: normalizedPrompt)
            || descriptorMatches("SavingsAccount", normalizedPrompt: normalizedPrompt) {
            if savingsPromptNeedsLedger(normalizedPrompt) {
                return catalog.descriptor(for: "SavingsLedgerEntry")
            }
            return catalog.descriptor(for: "SavingsAccount")
        }

        return rankedMatches.first?.descriptor
    }

    private func requestedDetail(
        from interpretation: MarinaTurnInterpretation,
        candidate: MarinaQueryPlanCandidate
    ) -> MarinaSemanticRequestedDetail? {
        if let semanticQuery = semanticQuery(from: interpretation),
           let requestedDetail = semanticQuery.requestedDetail {
            return requestedDetail
        }
        return candidate.semanticCommand?.requestedDetail
            ?? candidate.routeIntent?.requestedDetail
    }

    private func descriptorFromRequestedDetail(
        _ detail: MarinaSemanticRequestedDetail?
    ) -> MarinaEntityDescriptor? {
        switch detail {
        case .categoryLimits:
            return catalog.descriptor(for: "BudgetCategoryLimit")
        case .linkedCards:
            return catalog.descriptor(for: "BudgetCardLink")
        case .linkedPresets:
            return catalog.descriptor(for: "BudgetPresetLink")
        case .none, .general, .date, .amount, .card, .category, .status, .schedule, .recurrence, .account, .balance, .linkedObjects, .membership:
            return nil
        }
    }

    private func shouldPreferPromptDescriptor(
        _ match: (descriptor: MarinaEntityDescriptor, score: Int),
        interpretation: MarinaTurnInterpretation,
        candidate: MarinaQueryPlanCandidate
    ) -> Bool {
        guard match.score >= 8 else { return false }
        if let semanticQuery = semanticQuery(from: interpretation),
           entityName(for: semanticQuery.subject) == match.descriptor.entityName {
            return false
        }
        if let candidateDescriptor = descriptor(from: candidate.semanticCommand?.datasets.first),
           candidateDescriptor.entityName == match.descriptor.entityName {
            return false
        }
        return true
    }

    private func rankedDescriptorMatches(
        in normalizedPrompt: String
    ) -> [(descriptor: MarinaEntityDescriptor, score: Int)] {
        catalog.descriptors
            .filter { $0.kind == .persistentModel && $0.isQueryable }
            .compactMap { descriptor in
                let score = semanticScore(for: descriptor, normalizedPrompt: normalizedPrompt)
                return score > 0 ? (descriptor, score) : nil
            }
            .sorted {
                if $0.score == $1.score {
                    return $0.descriptor.entityName < $1.descriptor.entityName
                }
                return $0.score > $1.score
            }
    }

    private func semanticScore(
        for descriptor: MarinaEntityDescriptor,
        normalizedPrompt: String
    ) -> Int {
        let aliases = aliases(for: descriptor)
        let aliasScore = aliases.reduce(0) { partial, alias in
            guard containsWholePhrase(alias, in: normalizedPrompt) else { return partial }
            let tokenCount = tokenSet(alias).count
            let weightedScore = tokenCount > 1 ? tokenCount * 4 : 2
            return max(partial, weightedScore)
        }
        guard aliasScore > 0 else { return 0 }

        var score = aliasScore
        if descriptor.entityName == "Workspace", semanticWorkspaceReference(in: normalizedPrompt) {
            score += 24
        }
        if descriptor.amountFields.isEmpty == false, amountOperationSignal(in: normalizedPrompt) {
            score += 4
        }
        if descriptor.dateFields.isEmpty == false, dateRangeSignal(in: normalizedPrompt) {
            score += 3
        }
        if fieldIdentityQuestion(in: normalizedPrompt, descriptor: descriptor) {
            score += 6
        }
        return score
    }

    private func descriptorMatches(
        _ entityName: String,
        normalizedPrompt: String
    ) -> Bool {
        guard let descriptor = catalog.descriptor(for: entityName) else { return false }
        return semanticScore(for: descriptor, normalizedPrompt: normalizedPrompt) > 0
    }

    private func semanticQuery(from interpretation: MarinaTurnInterpretation) -> MarinaSemanticQuery? {
        if case .query(let query) = interpretation.result { return query }
        return nil
    }

    private func descriptor(from dataset: MarinaSemanticCommandDataset?) -> MarinaEntityDescriptor? {
        switch dataset {
        case .workspaces:
            return catalog.descriptor(for: "Workspace")
        case .variableExpenses:
            return catalog.descriptor(for: "VariableExpense")
        case .plannedExpenses:
            return catalog.descriptor(for: "PlannedExpense")
        case .income:
            return catalog.descriptor(for: "Income")
        case .incomeSeries:
            return catalog.descriptor(for: "IncomeSeries")
        case .cards:
            return catalog.descriptor(for: "Card")
        case .categories:
            return catalog.descriptor(for: "Category")
        case .presets:
            return catalog.descriptor(for: "Preset")
        case .budgets:
            return catalog.descriptor(for: "Budget")
        case .savingsLedger:
            return catalog.descriptor(for: "SavingsLedgerEntry")
        case .reconciliation:
            return catalog.descriptor(for: "AllocationAccount")
        case .expenseAllocations:
            return catalog.descriptor(for: "ExpenseAllocation")
        case .importMerchantRules:
            return catalog.descriptor(for: "ImportMerchantRule")
        case .assistantAliasRules:
            return catalog.descriptor(for: "AssistantAliasRule")
        case nil:
            return nil
        }
    }

    private func operation(
        for normalizedPrompt: String,
        descriptor: MarinaEntityDescriptor,
        interpretation: MarinaTurnInterpretation,
        candidate: MarinaQueryPlanCandidate
    ) -> MarinaUniversalQueryOperation {
        if fieldIdentityQuestion(in: normalizedPrompt, descriptor: descriptor)
            || selectedWorkspaceIdentityQuestion(normalizedPrompt, descriptor: descriptor) {
            return .detail
        }
        if normalizedPrompt.hasPrefix("how many ") || normalizedPrompt.hasPrefix("count ") || normalizedPrompt.contains(" count ") {
            return .count
        }
        if containsAny(["average", "avg"], in: normalizedPrompt) {
            return .average
        }
        if containsAny(["smallest", "lowest", "minimum", "min "], in: normalizedPrompt) {
            return .minimum
        }
        if containsAny(["largest", "highest", "maximum", "max ", "top ", "most "], in: normalizedPrompt) {
            return .rank
        }
        if containsAny(["breakdown", " by ", " each ", " per "], in: " \(normalizedPrompt) ") {
            return descriptor.amountFields.isEmpty ? .list : .groupBreakdown
        }
        if containsAny(["compare", " versus ", " vs "], in: " \(normalizedPrompt) ") {
            return .compare
        }
        if let semanticQuery = semanticQuery(from: interpretation),
           let semanticOperation = universalOperation(from: semanticQuery.operation) {
            return semanticOperation
        }
        if let candidateOperation = universalOperation(from: candidate.operation) {
            return candidateOperation
        }
        if descriptor.entityName == "Income",
           containsWholePhrase("income", in: normalizedPrompt),
           containsAny(["list", "row", "rows", "entry", "entries"], in: normalizedPrompt) == false {
            return .sum
        }
        if normalizedPrompt.hasPrefix("list ") || normalizedPrompt.hasPrefix("show all ") || normalizedPrompt.hasPrefix("show my ") {
            return .list
        }
        if containsAny(["how much", "total", "sum", "what is my", "what are my"], in: normalizedPrompt),
           descriptor.amountFields.isEmpty == false {
            return .sum
        }
        return descriptor.amountFields.isEmpty ? .detail : .list
    }

    private func universalOperation(from operation: MarinaOperation?) -> MarinaUniversalQueryOperation? {
        switch operation {
        case .sum, .percentageShare:
            return .sum
        case .average, .median:
            return .average
        case .count:
            return .count
        case .minimum:
            return .minimum
        case .maximum:
            return .maximum
        case .rank:
            return .rank
        case .breakdown:
            return .groupBreakdown
        case .compare:
            return .compare
        case .list:
            return .list
        case .lookupDetails:
            return .detail
        case .forecast, .simulate, .none:
            return nil
        }
    }

    private func universalOperation(from operation: MarinaCandidateOperation?) -> MarinaUniversalQueryOperation? {
        switch operation {
        case .sum:
            return .sum
        case .average:
            return .average
        case .count:
            return .count
        case .minimum:
            return .minimum
        case .maximum:
            return .maximum
        case .rank:
            return .rank
        case .compare:
            return .compare
        case .listRows:
            return .list
        case .lookupDetails:
            return .detail
        case .trend:
            return .groupBreakdown
        case .forecast, .simulate, .none:
            return nil
        }
    }

    private func supports(
        _ operation: MarinaUniversalQueryOperation,
        descriptor: MarinaEntityDescriptor
    ) -> Bool {
        switch operation {
        case .lookup, .list, .count, .detail:
            return descriptor.isQueryable
        case .sum, .average, .minimum, .maximum, .rank, .groupBreakdown, .compare:
            return descriptor.amountFields.isEmpty == false
                && (
                    descriptor.isAggregatable
                    || descriptor.supportedOperations.contains { ["total", "average", "rank", "compare", "balance"].contains($0) }
                )
        case .simulate:
            return false
        }
    }

    private func dateRange(
        in prompt: String,
        candidate: MarinaQueryPlanCandidate,
        context: MarinaTurnContext
    ) -> HomeQueryDateRange? {
        candidate.semanticCommand?.dateRange
            ?? candidate.timeScopes.first?.resolvedRangeHint
            ?? MarinaDateRangeTextResolver(
                calendar: Calendar(identifier: .gregorian),
                nowProvider: { context.now }
            ).resolve(prompt, defaultPeriodUnit: context.defaultPeriodUnit)
    }

    private func filters(
        in normalizedPrompt: String,
        interpretation: MarinaTurnInterpretation,
        candidate: MarinaQueryPlanCandidate,
        descriptor: MarinaEntityDescriptor,
        operation: MarinaUniversalQueryOperation
    ) -> [MarinaUniversalQueryFilter] {
        var filters: [MarinaUniversalQueryFilter] = []
        if selectedWorkspaceIdentityQuestion(normalizedPrompt, descriptor: descriptor) {
            return filters
        }
        filters.append(contentsOf: universalFilters(
            from: semanticQuery(from: interpretation)?.filters ?? [],
            descriptor: descriptor
        ))
        if filters.isEmpty {
            filters.append(contentsOf: universalFilters(
                from: candidate.entityMentions,
                descriptor: descriptor
            ))
        }
        if descriptor.entityName == "Income" {
            if containsAny(["planned", "expected", "forecast"], in: normalizedPrompt) {
                filters.append(MarinaUniversalQueryFilter(field: "income status", value: "planned", match: .exact))
            } else if containsAny(["all income", "planned and actual", "actual and planned"], in: normalizedPrompt) == false {
                filters.append(MarinaUniversalQueryFilter(field: "income status", value: "actual", match: .exact))
            }
        }
        if descriptor.entityName == "VariableExpense", containsWholePhrase("uncategorized", in: normalizedPrompt) {
            filters.append(MarinaUniversalQueryFilter(value: "Uncategorized", match: .uncategorized))
        }
        if let containsValue = phraseAfter([" containing ", " contain "], in: normalizedPrompt) {
            filters.append(MarinaUniversalQueryFilter(value: containsValue, match: .contains))
        }
        if filters.isEmpty,
           (operation == .detail || operation == .lookup),
           let target = detailTarget(in: normalizedPrompt, descriptor: descriptor) {
            filters.append(MarinaUniversalQueryFilter(value: target, match: .contains))
        }
        return filters
    }

    private func universalFilters(
        from semanticFilters: [MarinaFilter],
        descriptor: MarinaEntityDescriptor
    ) -> [MarinaUniversalQueryFilter] {
        semanticFilters.compactMap { filter in
            let value = filter.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.isEmpty == false else { return nil }
            return MarinaUniversalQueryFilter(
                field: universalField(for: filter.relationship, descriptor: descriptor),
                value: value,
                match: filter.matchMode == .exact ? .exact : .contains
            )
        }
    }

    private func universalFilters(
        from mentions: [MarinaUnresolvedEntityMention],
        descriptor: MarinaEntityDescriptor
    ) -> [MarinaUniversalQueryFilter] {
        mentions.compactMap { mention in
            let value = mention.rawText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard value.isEmpty == false else { return nil }
            return MarinaUniversalQueryFilter(
                field: mention.typeHint.flatMap { universalField(for: $0, descriptor: descriptor) },
                value: value,
                match: mention.confidence == .high ? .exact : .contains
            )
        }
    }

    private func universalField(
        for relationship: MarinaRelationshipField,
        descriptor: MarinaEntityDescriptor
    ) -> String? {
        switch relationship {
        case .category:
            return descriptor.entityName == "Category" ? nil : "category"
        case .merchant:
            return "merchant"
        case .card:
            return descriptor.entityName == "Card" ? nil : "card"
        case .budget:
            return descriptor.entityName == "Budget" ? nil : "budget"
        case .preset:
            return descriptor.entityName == "Preset" ? nil : "preset"
        case .incomeSource:
            return "source"
        case .allocationAccount:
            return descriptor.entityName == "AllocationAccount" ? nil : "account"
        case .savingsAccount:
            return descriptor.entityName == "SavingsAccount" ? nil : "account"
        case .transaction:
            return descriptor.entityName == "VariableExpense" || descriptor.entityName == "PlannedExpense" ? nil : "transaction"
        case .workspace, .uncategorized, .unknown:
            return nil
        }
    }

    private func universalField(
        for typeHint: MarinaCandidateEntityTypeHint,
        descriptor: MarinaEntityDescriptor
    ) -> String? {
        switch typeHint {
        case .category:
            return descriptor.entityName == "Category" ? nil : "category"
        case .merchant:
            return "merchant"
        case .expense, .transaction:
            return descriptor.entityName == "VariableExpense" || descriptor.entityName == "PlannedExpense" ? nil : "transaction"
        case .card:
            return descriptor.entityName == "Card" ? nil : "card"
        case .budget:
            return descriptor.entityName == "Budget" ? nil : "budget"
        case .preset:
            return descriptor.entityName == "Preset" ? nil : "preset"
        case .incomeSource:
            return "source"
        case .allocationAccount:
            return descriptor.entityName == "AllocationAccount" ? nil : "account"
        case .savingsAccount:
            return descriptor.entityName == "SavingsAccount" ? nil : "account"
        case .workspace:
            return nil
        }
    }

    private func amountBasis(
        for descriptor: MarinaEntityDescriptor,
        normalizedPrompt: String
    ) -> MarinaAmountField? {
        switch descriptor.entityName {
        case "VariableExpense":
            return containsWholePhrase("ledger", in: normalizedPrompt) ? .ledgerSignedAmount : .budgetImpactAmount
        case "PlannedExpense":
            return .effectivePlannedAmount
        case "Income", "IncomeSeries":
            return .incomeAmount
        case "SavingsAccount", "SavingsLedgerEntry":
            return .savingsAmount
        case "ExpenseAllocation":
            return .allocatedAmount
        case "AllocationAccount", "AllocationSettlement":
            return .reconciliationBalance
        case "Preset":
            return .plannedAmount
        default:
            return .amount
        }
    }

    private func grouping(
        in normalizedPrompt: String,
        interpretation: MarinaTurnInterpretation,
        candidate: MarinaQueryPlanCandidate,
        descriptor: MarinaEntityDescriptor
    ) -> String? {
        if let semanticGrouping = semanticQuery(from: interpretation)?.grouping {
            return groupingName(for: semanticGrouping.dimension)
        }
        if let candidateGrouping = candidate.grouping {
            return groupingName(for: candidateGrouping.dimension)
        }
        if containsWholePhrase("source", in: normalizedPrompt) { return "source" }
        if containsWholePhrase("category", in: normalizedPrompt) { return "category" }
        if containsWholePhrase("card", in: normalizedPrompt) { return "card" }
        if containsWholePhrase("account", in: normalizedPrompt) { return "account" }
        if containsWholePhrase("kind", in: normalizedPrompt) || containsWholePhrase("type", in: normalizedPrompt) { return "kind" }
        switch descriptor.entityName {
        case "Income":
            return "source"
        case "VariableExpense", "PlannedExpense", "BudgetCategoryLimit":
            return "category"
        case "SavingsLedgerEntry", "ExpenseAllocation", "AllocationSettlement":
            return "account"
        default:
            return nil
        }
    }

    private func groupingName(for dimension: MarinaGroupingDimensionCandidate) -> String? {
        switch dimension {
        case .category:
            return "category"
        case .merchant:
            return "merchant"
        case .card:
            return "card"
        case .incomeSource:
            return "source"
        case .allocationAccount:
            return "account"
        case .transaction:
            return "transaction"
        case .preset:
            return "preset"
        case .savingsLedgerEntry:
            return "kind"
        case .day:
            return "day"
        case .week:
            return "week"
        case .month:
            return "month"
        }
    }

    private func ranking(
        in normalizedPrompt: String,
        candidate: MarinaQueryPlanCandidate
    ) -> MarinaRankingDirectionCandidate? {
        if let direction = candidate.ranking?.direction { return direction }
        if containsAny(["smallest", "lowest", "bottom", "least"], in: normalizedPrompt) { return .smallest }
        if containsAny(["newest", "latest", "recent"], in: normalizedPrompt) { return .newest }
        if containsAny(["top", "largest", "highest", "most"], in: normalizedPrompt) { return .largest }
        return nil
    }

    private func workspaceScopePolicy(
        for descriptor: MarinaEntityDescriptor,
        normalizedPrompt: String
    ) -> MarinaUniversalWorkspaceScopePolicy {
        if selectedWorkspaceIdentityQuestion(normalizedPrompt, descriptor: descriptor) {
            return .selectedWorkspace
        }
        return descriptor.entityName == "Workspace" ? .explicitGlobal : .selectedWorkspace
    }

    private func responseShape(for operation: MarinaUniversalQueryOperation) -> MarinaResponseShape {
        switch operation {
        case .count, .sum, .average, .minimum, .maximum, .lookup, .detail:
            return .summaryCard
        case .rank:
            return .rankedList
        case .groupBreakdown:
            return .groupedBreakdown
        case .list:
            return .relationshipList
        case .compare:
            return .comparison
        case .simulate:
            return .unsupported
        }
    }

    private func entityName(for subject: MarinaSubject) -> String {
        switch subject {
        case .variableExpenses:
            return "VariableExpense"
        case .plannedExpenses:
            return "PlannedExpense"
        case .income:
            return "Income"
        case .budgets:
            return "Budget"
        case .cards:
            return "Card"
        case .categories, .uncategorizedExpenses:
            return "Category"
        case .presets:
            return "Preset"
        case .savingsAccounts:
            return "SavingsAccount"
        case .savingsLedgerEntries:
            return "SavingsLedgerEntry"
        case .reconciliationAccounts:
            return "AllocationAccount"
        case .reconciliationItems:
            return "AllocationSettlement"
        case .workspaces:
            return "Workspace"
        case .merchant:
            return "VariableExpense"
        case .incomeSource:
            return "Income"
        }
    }

    func aliases(for descriptor: MarinaEntityDescriptor) -> [String] {
        var aliases = [
            normalized(splitCamelCase(descriptor.entityName)),
            normalized(descriptor.displayName)
        ]
        if let lookup = descriptor.lookupObjectType {
            aliases.append(normalized(lookup.rawValue))
        }
        let entityNoun = normalized(splitCamelCase(descriptor.entityName))
        let displayNoun = normalized(descriptor.displayName)
        let nouns = [entityNoun, displayNoun].filter { $0.isEmpty == false }
        for field in descriptor.displayFields + descriptor.searchableFields + descriptor.dateFields + descriptor.amountFields {
            let fieldAlias = normalized(field)
            guard fieldAlias.isEmpty == false else { continue }
            for noun in nouns {
                aliases.append("\(noun) \(fieldAlias)")
                aliases.append("\(fieldAlias) \(noun)")
            }
        }
        for relationship in descriptor.relationships {
            let relationshipAlias = normalized(splitCamelCase(relationship.name))
            guard relationshipAlias.isEmpty == false else { continue }
            for noun in nouns {
                aliases.append("\(noun) \(relationshipAlias)")
                aliases.append("\(relationshipAlias) \(noun)")
            }
        }
        aliases.append(contentsOf: semanticAliases(for: descriptor.entityName).map(normalized))
        aliases.append(contentsOf: aliases.map(pluralized))

        var seen: Set<String> = []
        return aliases.filter { alias in
            guard alias.isEmpty == false, seen.contains(alias) == false else { return false }
            seen.insert(alias)
            return true
        }
    }

    private func semanticAliases(for entityName: String) -> [String] {
        switch entityName {
        case "Workspace":
            return [
                "workspace",
                "selected workspace",
                "current workspace",
                "active workspace",
                "this workspace",
                "workspace name",
                "selected workspace name",
                "current workspace name"
            ]
        case "Budget":
            return ["budget", "active budget", "current budget", "budget period", "budget range"]
        case "BudgetCategoryLimit":
            return ["category limit", "budget limit", "budget category limit", "category goal"]
        case "BudgetCardLink":
            return ["linked card", "budget card link", "budget linked card"]
        case "BudgetPresetLink":
            return ["linked preset", "budget preset link", "budget linked preset"]
        case "Card":
            return ["card", "account card", "spending card"]
        case "Category":
            return ["category", "spending category"]
        case "Preset":
            return ["preset", "recurring preset", "template", "planned template"]
        case "VariableExpense":
            return ["transaction", "purchase", "expense", "variable expense", "spending", "spend", "ledger row"]
        case "AllocationAccount":
            return ["allocation account", "reconciliation account", "shared balance account"]
        case "AllocationSettlement":
            return ["allocation settlement", "settlement", "reconciliation item", "settlement row"]
        case "SavingsLedgerEntry":
            return ["savings ledger entry", "savings activity", "savings transaction", "savings movement", "savings ledger", "savings"]
        case "SavingsAccount":
            return ["savings account", "savings balance", "savings total"]
        case "ImportMerchantRule":
            return ["import merchant rule", "merchant rule", "import rule"]
        case "AssistantAliasRule":
            return ["assistant alias rule", "marina alias", "alias rule", "alias"]
        case "IncomeSeries":
            return ["income series", "income schedule", "recurring income", "planned income schedule"]
        case "Income":
            return ["income entry", "income", "actual income", "planned income", "income source", "paycheck"]
        case "PlannedExpense":
            return ["planned expense", "planned transaction", "bill", "planned bill", "upcoming expense"]
        case "ExpenseAllocation":
            return ["expense allocation", "allocation row", "allocation"]
        default:
            return []
        }
    }

    private func detailTarget(
        in normalizedPrompt: String,
        descriptor: MarinaEntityDescriptor
    ) -> String? {
        let aliases = aliases(for: descriptor).sorted { $0.count > $1.count }
        var value = normalizedPrompt
            .replacingOccurrences(of: #"^(show|find|list|what is|what are|which is|which are)\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\b(my|me|the|a|an|current|selected|active|this|name|of|in|about|please)\b"#, with: " ", options: .regularExpression)
        for alias in aliases {
            value = value.replacingOccurrences(of: #"\b\#(NSRegularExpression.escapedPattern(for: alias))\b"#, with: " ", options: .regularExpression)
        }
        value = normalized(value)
        return value.isEmpty ? nil : value
    }

    private func phraseAfter(_ delimiters: [String], in normalizedPrompt: String) -> String? {
        for delimiter in delimiters {
            if let range = normalizedPrompt.range(of: delimiter) {
                let suffix = normalizedPrompt[range.upperBound...]
                return String(suffix)
                    .replacingOccurrences(of: #"^(a|an|the)\s+"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .marinaNilIfBlank
            }
        }
        return nil
    }

    private func containsAny(_ needles: [String], in haystack: String) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    private func containsAnyToken(_ needles: [String], in normalizedPrompt: String) -> Bool {
        let tokens = tokenSet(normalizedPrompt)
        return needles.contains { tokens.contains($0) }
    }

    private func containsWholePhrase(_ phrase: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        return text.range(of: #"(^|\s)\#(escaped)($|\s)"#, options: .regularExpression) != nil
    }

    private func semanticWorkspaceReference(in normalizedPrompt: String) -> Bool {
        guard containsWholePhrase("workspace", in: normalizedPrompt) else { return false }
        let tokens = tokenSet(normalizedPrompt)
        if tokens.contains("current") || tokens.contains("selected") || tokens.contains("active") || tokens.contains("this") {
            return true
        }
        return (tokens.contains("what") || tokens.contains("which"))
            && (tokens.contains("in") || tokens.contains("using") || tokens.contains("selected") || tokens.contains("name"))
    }

    private func selectedWorkspaceIdentityQuestion(
        _ normalizedPrompt: String,
        descriptor: MarinaEntityDescriptor
    ) -> Bool {
        descriptor.entityName == "Workspace" && semanticWorkspaceReference(in: normalizedPrompt)
    }

    private func fieldIdentityQuestion(
        in normalizedPrompt: String,
        descriptor: MarinaEntityDescriptor
    ) -> Bool {
        let tokens = tokenSet(normalizedPrompt)
        let asksIdentity = tokens.contains("name")
            || tokens.contains("called")
            || tokens.contains("which")
            || tokens.contains("what")
        guard asksIdentity else { return false }

        let fieldTokens = Set(
            descriptor.displayFields
                .flatMap { tokenSet(normalized($0)) }
                + descriptor.searchableFields.flatMap { tokenSet(normalized($0)) }
        )
        if tokens.contains("name"), fieldTokens.contains("name") {
            return true
        }
        return selectedWorkspaceIdentityQuestion(normalizedPrompt, descriptor: descriptor)
    }

    private func amountOperationSignal(in normalizedPrompt: String) -> Bool {
        containsAny(["how much", "total", "sum", "amount", "average", "avg", "largest", "highest", "lowest", "smallest"], in: normalizedPrompt)
            || containsAnyToken(["spend", "spending", "income", "savings", "balance"], in: normalizedPrompt)
    }

    private func dateRangeSignal(in normalizedPrompt: String) -> Bool {
        containsAny(
            ["this month", "last month", "this week", "last week", "today", "yesterday", "quarter", "year"],
            in: normalizedPrompt
        )
    }

    private func savingsPromptNeedsLedger(_ normalizedPrompt: String) -> Bool {
        containsAny(
            [
                "activity",
                "movement",
                "transaction",
                "ledger",
                "entry",
                "this month",
                "last month",
                "this week",
                "last week",
                "today",
                "yesterday"
            ],
            in: normalizedPrompt
        )
    }

    private func hasExplicitNamedTargetSignal(in normalizedPrompt: String) -> Bool {
        if containsAny([" at ", " from ", " on ", " named ", " called "], in: " \(normalizedPrompt) ") {
            if containsAny([" from each ", " by source ", " each source ", " per source "], in: " \(normalizedPrompt) ") {
                return false
            }
            return true
        }
        return false
    }

    private func hasSpecializedRoute(candidate: MarinaQueryPlanCandidate) -> Bool {
        guard let kind = candidate.routeIntent?.kind else { return false }
        switch kind {
        case .generic, .databaseLookup, .currentWorkspace:
            return false
        default:
            return true
        }
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tokenSet(_ value: String) -> Set<String> {
        Set(value.split(separator: " ").map(String.init))
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
            .marinaNilIfBlank
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
                    .marinaNilIfBlank
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
