import Foundation

struct MarinaFormulaRequest: Equatable, Sendable {
    let surface: MarinaUniversalEntitySurface
    let operation: MarinaSemanticOperation
    let measure: MarinaSemanticMeasure
    let dateRange: HomeQueryDateRange?
    let comparisonDateRange: HomeQueryDateRange?
    let filters: [MarinaRowFilter]
    let search: MarinaRowSearchClause?
    let groupBy: MarinaRowGroupTarget?
    let limit: Int?
    let whatIfAmount: Double?
}

enum MarinaFormulaResult: Equatable, Sendable {
    case metric(MarinaFormulaMetric)
    case rows([MarinaQueryableRow])
    case groups([MarinaFormulaGroup])
    case unsupported(MarinaCapabilityFailureReason)
}

struct MarinaFormulaMetric: Equatable, Sendable {
    let value: MarinaValue
    let evidenceRows: [MarinaQueryableRow]
    let measure: MarinaSemanticMeasure
    let source: MarinaFormulaSource
}

struct MarinaFormulaGroup: Equatable, Sendable {
    let displayName: String
    let value: MarinaValue
    let evidenceRows: [MarinaQueryableRow]
    let measure: MarinaSemanticMeasure
    let source: MarinaFormulaSource
}

enum MarinaFormulaSource: String, Codable, Equatable, Sendable {
    case homeQueryEngine
    case savingsMathService
    case savingsAccountService
    case allocationLedgerService
    case marinaBudgetFormulaCalculator
    case safeSpendTodayCalculator
    case homeCategoryLimitsAggregator
    case rowBackedFallback
}

enum MarinaMeasureExecutionKind: Equatable, Sendable {
    case rowBacked(field: MarinaFieldKey)
    case formulaBacked
    case unsupported(MarinaCapabilityFailureReason)
}

struct MarinaFormulaRegistry: Sendable {
    let now: Date
    let calendar: Calendar

    init(
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.now = now
        self.calendar = calendar
    }

    func supports(
        measure: MarinaSemanticMeasure,
        surface: MarinaUniversalEntitySurface
    ) -> Bool {
        supportedOperation(measure: measure, surface: surface) != nil
    }

    func supports(
        measure: MarinaSemanticMeasure,
        surface: MarinaUniversalEntitySurface,
        operation: MarinaSemanticOperation
    ) -> Bool {
        supportedOperation(measure: measure, surface: surface) == operation
    }

    @MainActor
    func evaluate(
        request: MarinaFormulaRequest,
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaFormulaResult {
        guard supports(measure: request.measure, surface: request.surface, operation: request.operation) else {
            return .unsupported(.measureNotAvailable)
        }

        switch request.measure {
        case .savingsTotal:
            return savingsTotal(request: request, snapshot: snapshot)
        case .reconciliationBalance:
            return reconciliationBalance(request: request, snapshot: snapshot)
        case .remainingRoom, .safeDailySpend:
            return safeSpendMetric(request: request, snapshot: snapshot)
        case .amount,
             .plannedAmount,
             .actualAmount,
             .effectiveAmount,
             .budgetImpact,
             .incomeAmount,
             .categoryAvailability,
             .burnRate,
             .projectedSpend,
             .paceDifference,
             .coverageRatio,
             .recurringBurden,
             .concentration,
             .color,
             .name:
            return .unsupported(.measureNotAvailable)
        }
    }

    private func supportedOperation(
        measure: MarinaSemanticMeasure,
        surface: MarinaUniversalEntitySurface
    ) -> MarinaSemanticOperation? {
        switch (surface, measure) {
        case (.semantic(.savingsAccount), .savingsTotal),
             (.semantic(.reconciliationAccount), .reconciliationBalance):
            return .sum
        case (.semantic(.budget), .remainingRoom),
             (.semantic(.budget), .safeDailySpend):
            return .forecast
        case (.semantic(_), _),
             (.unifiedExpenses, _),
             (.savingsLedgerEntries, _),
             (.reconciliationLedgerEntries, _):
            return nil
        }
    }

    @MainActor
    private func savingsTotal(
        request: MarinaFormulaRequest,
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaFormulaResult {
        switch resolvedAccount(
            surface: MarinaUniversalEntitySurface.semantic(.savingsAccount),
            request: request,
            snapshot: snapshot,
            accounts: snapshot.savingsAccounts
        ) {
        case let .success((account, evidenceRows)):
            return .metric(
                MarinaFormulaMetric(
                    value: .money(SavingsAccountService.balance(for: account)),
                    evidenceRows: evidenceRows,
                    measure: request.measure,
                    source: .savingsAccountService
                )
            )
        case let .failure(reason):
            return .unsupported(reason)
        }
    }

    @MainActor
    private func reconciliationBalance(
        request: MarinaFormulaRequest,
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaFormulaResult {
        switch resolvedAccount(
            surface: MarinaUniversalEntitySurface.semantic(.reconciliationAccount),
            request: request,
            snapshot: snapshot,
            accounts: snapshot.reconciliationAccounts
        ) {
        case let .success((account, evidenceRows)):
            let value: Double
            if let dateRange = request.dateRange {
                value = AllocationLedgerService.chargeActivity(
                    for: account,
                    startDate: dateRange.startDate,
                    endDate: dateRange.endDate
                )
            } else {
                value = AllocationLedgerService.balance(for: account)
            }

            return .metric(
                MarinaFormulaMetric(
                    value: .money(value),
                    evidenceRows: evidenceRows,
                    measure: request.measure,
                    source: .allocationLedgerService
                )
            )
        case let .failure(reason):
            return .unsupported(reason)
        }
    }

    private func safeSpendMetric(
        request: MarinaFormulaRequest,
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaFormulaResult {
        guard let dateRange = request.dateRange else {
            return .unsupported(.missingDateField)
        }

        let summary = SafeSpendTodayCalculator.calculate(
            budgetingPeriod: budgetingPeriod(for: dateRange),
            rangeStart: dateRange.startDate,
            rangeEnd: dateRange.endDate,
            budgets: snapshot.budgets,
            categories: snapshot.categories,
            incomes: snapshot.incomes,
            plannedExpenses: snapshot.homeCalculationPlannedExpenses,
            variableExpenses: snapshot.homeCalculationVariableExpenses,
            savingsEntries: snapshot.savingsEntries,
            now: now,
            calendar: calendar
        )
        let value: Double
        switch request.measure {
        case .remainingRoom:
            value = summary.periodRemainingRoom
        case .safeDailySpend:
            value = summary.safeToSpendToday
        case .amount,
             .plannedAmount,
             .actualAmount,
             .effectiveAmount,
             .budgetImpact,
             .savingsTotal,
             .incomeAmount,
             .reconciliationBalance,
             .categoryAvailability,
             .burnRate,
             .projectedSpend,
             .paceDifference,
             .coverageRatio,
             .recurringBurden,
             .concentration,
             .color,
             .name:
            return .unsupported(.measureNotAvailable)
        }

        return .metric(
            MarinaFormulaMetric(
                value: .money(value),
                evidenceRows: evidenceRows(surface: .semantic(.budget), request: request, snapshot: snapshot),
                measure: request.measure,
                source: .safeSpendTodayCalculator
            )
        )
    }

    private func budgetingPeriod(for range: HomeQueryDateRange) -> BudgetingPeriod {
        let start = calendar.startOfDay(for: range.startDate)
        let end = calendar.startOfDay(for: range.endDate)
        return start == end ? .daily : .monthly
    }

    private func evidenceRows(
        surface: MarinaUniversalEntitySurface,
        request: MarinaFormulaRequest,
        snapshot: MarinaWorkspaceSnapshot
    ) -> [MarinaQueryableRow] {
        guard let descriptor = MarinaEntityCatalog().descriptor(for: surface),
              var rows = MarinaEntityAdapterRegistry().rows(for: surface, from: snapshot) else {
            return []
        }

        let rowEngine = MarinaRowOperationEngine()
        if let search = request.search {
            rows = rowEngine.search(rows, clause: search, descriptor: descriptor)
        }
        rows = rowEngine.filter(rows, filters: request.filters)
        return rowEngine.limit(rows, to: request.limit)
    }

    private func resolvedAccount<Account>(
        surface: MarinaUniversalEntitySurface,
        request: MarinaFormulaRequest,
        snapshot: MarinaWorkspaceSnapshot,
        accounts: [Account]
    ) -> FormulaAccountResolution<Account> where Account: AnyObject {
        guard request.filters.isEmpty == false || request.search != nil else {
            return .failure(.unresolvedEntity)
        }

        let rows = evidenceRows(surface: surface, request: request, snapshot: snapshot)
        guard rows.count == 1 else {
            return rows.isEmpty ? .failure(.unresolvedEntity) : .failure(.ambiguousEntity)
        }

        let row = rows[0]
        guard let account = accounts.first(where: { objectID($0) == row.id }) else {
            return .failure(.unresolvedEntity)
        }

        return .success((account, rows))
    }

    private func objectID(_ account: AnyObject) -> UUID? {
        switch account {
        case let savingsAccount as SavingsAccount:
            return savingsAccount.id
        case let allocationAccount as AllocationAccount:
            return allocationAccount.id
        default:
            return nil
        }
    }
}

private enum FormulaAccountResolution<Account> {
    case success((Account, [MarinaQueryableRow]))
    case failure(MarinaCapabilityFailureReason)
}
