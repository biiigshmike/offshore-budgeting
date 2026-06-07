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
    let details: [MarinaFormulaMetricDetail]

    init(
        value: MarinaValue,
        evidenceRows: [MarinaQueryableRow],
        measure: MarinaSemanticMeasure,
        source: MarinaFormulaSource,
        details: [MarinaFormulaMetricDetail] = []
    ) {
        self.value = value
        self.evidenceRows = evidenceRows
        self.measure = measure
        self.source = source
        self.details = details
    }
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
    case marinaSavingsForecastCalculator
    case savingsMathService
    case savingsAccountService
    case allocationLedgerService
    case marinaBudgetFormulaCalculator
    case safeSpendTodayCalculator
    case homeCategoryLimitsAggregator
    case homeCategoryMetricsCalculator
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
        supportedOperations(measure: measure, surface: surface).isEmpty == false
    }

    func supports(
        measure: MarinaSemanticMeasure,
        surface: MarinaUniversalEntitySurface,
        operation: MarinaSemanticOperation
    ) -> Bool {
        supportedOperations(measure: measure, surface: surface).contains(operation)
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
            if request.surface == .semantic(.savingsAccount), request.operation == .forecast {
                return forecastSavingsMetric(request: request, snapshot: snapshot)
            }
            return savingsTotal(request: request, snapshot: snapshot)
        case .reconciliationBalance:
            return reconciliationBalance(request: request, snapshot: snapshot)
        case .remainingRoom, .safeDailySpend:
            return safeSpendMetric(request: request, snapshot: snapshot)
        case .burnRate,
             .projectedSpend,
             .paceDifference,
             .coverageRatio:
            return budgetPaceMetric(request: request, snapshot: snapshot)
        case .categoryAvailability,
             .concentration:
            return categoryMetric(request: request, snapshot: snapshot)
        case .recurringBurden:
            return recurringBurdenMetric(request: request, snapshot: snapshot)
        case .amount,
             .plannedAmount,
             .actualAmount,
             .effectiveAmount,
             .budgetImpact,
             .incomeAmount,
             .color,
             .name:
            return .unsupported(.measureNotAvailable)
        }
    }

    private func supportedOperations(
        measure: MarinaSemanticMeasure,
        surface: MarinaUniversalEntitySurface
    ) -> Set<MarinaSemanticOperation> {
        switch (surface, measure) {
        case (.semantic(.savingsAccount), .savingsTotal):
            return [.sum, .forecast]
        case (.semantic(.reconciliationAccount), .reconciliationBalance):
            return [.sum]
        case (.semantic(.budget), .remainingRoom),
             (.semantic(.budget), .safeDailySpend):
            return [.forecast]
        case (.semantic(.budget), .burnRate):
            return [.average]
        case (.semantic(.budget), .projectedSpend):
            return [.forecast]
        case (.semantic(.budget), .paceDifference):
            return [.compare]
        case (.semantic(.budget), .coverageRatio):
            return [.forecast]
        case (.semantic(.income), .coverageRatio):
            return [.share]
        case (.semantic(.category), .categoryAvailability):
            return [.forecast]
        case (.semantic(.category), .concentration):
            return [.share]
        case (.semantic(.preset), .recurringBurden):
            return [.sum]
        case (.semantic(_), _),
             (.unifiedExpenses, _),
             (.savingsLedgerEntries, _),
             (.reconciliationLedgerEntries, _):
            return []
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

    private func budgetPaceMetric(
        request: MarinaFormulaRequest,
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaFormulaResult {
        guard let dateRange = request.dateRange else {
            return .unsupported(.missingDateField)
        }

        let inputs = MarinaBudgetFormulaCalculator.inputs(
            snapshot: snapshot,
            range: dateRange,
            now: now,
            calendar: calendar
        )
        let evidenceRows = evidenceRows(surface: request.surface, request: request, snapshot: snapshot)

        switch request.measure {
        case .burnRate:
            guard let burnRate = MarinaBudgetFormulaCalculator.burnRate(
                actualSpend: inputs.actualSpendToDate,
                elapsedDays: inputs.progress.elapsedDays
            ) else {
                return .unsupported(.unsupportedCombination)
            }
            return metric(
                value: .money(burnRate),
                request: request,
                evidenceRows: evidenceRows,
                details: [
                    .init(.spentSoFar, value: .money(inputs.actualSpendToDate), style: .money),
                    .init(.elapsedDays, value: .integer(inputs.progress.elapsedDays), style: .integer),
                    .init(.averagePerDay, value: .money(burnRate), style: .money)
                ]
            )

        case .projectedSpend:
            guard let burnRate = MarinaBudgetFormulaCalculator.burnRate(
                actualSpend: inputs.actualSpendToDate,
                elapsedDays: inputs.progress.elapsedDays
            ),
                  let projectedSpend = MarinaBudgetFormulaCalculator.projectedSpend(
                    burnRate: burnRate,
                    totalDays: inputs.progress.totalDays
                  ) else {
                return .unsupported(.unsupportedCombination)
            }
            return metric(
                value: .money(projectedSpend),
                request: request,
                evidenceRows: evidenceRows,
                details: [
                    .init(.spentSoFar, value: .money(inputs.actualSpendToDate), style: .money),
                    .init(.averagePerDay, value: .money(burnRate), style: .money),
                    .init(.projectedTotal, value: .money(projectedSpend), style: .money)
                ]
            )

        case .paceDifference:
            guard let paceDifference = MarinaBudgetFormulaCalculator.paceDifference(
                actualSpend: inputs.actualSpendToDate,
                plannedSpend: inputs.plannedSpend,
                elapsedPercent: inputs.progress.elapsedPercent
            ) else {
                return .unsupported(.unsupportedCombination)
            }
            let expectedByNow = inputs.plannedSpend * inputs.progress.elapsedPercent
            return metric(
                value: .money(paceDifference),
                request: request,
                evidenceRows: evidenceRows,
                details: [
                    .init(.spentSoFar, value: .money(inputs.actualSpendToDate), style: .money),
                    .init(.expectedByNow, value: .money(expectedByNow), style: .money),
                    .init(.paceDifference, value: .money(paceDifference), style: .deltaMoney)
                ]
            )

        case .coverageRatio:
            guard let coverageRatio = MarinaBudgetFormulaCalculator.coverageRatio(
                income: inputs.coverageIncome,
                plannedExpenses: inputs.plannedSpend
            ) else {
                return .unsupported(.unsupportedCombination)
            }
            let difference = inputs.coverageIncome - inputs.plannedSpend
            return metric(
                value: .number(coverageRatio),
                request: request,
                evidenceRows: evidenceRows,
                details: [
                    .init(.income, value: .money(inputs.coverageIncome), style: .money),
                    .init(.plannedExpenses, value: .money(inputs.plannedSpend), style: .money),
                    .init(.coveragePercent, value: .number(coverageRatio), style: .percent),
                    .init(.difference, value: .money(difference), style: .deltaMoney)
                ]
            )

        case .amount,
             .plannedAmount,
             .actualAmount,
             .effectiveAmount,
             .budgetImpact,
             .savingsTotal,
             .incomeAmount,
             .reconciliationBalance,
             .categoryAvailability,
             .remainingRoom,
             .safeDailySpend,
             .recurringBurden,
             .concentration,
             .color,
             .name:
            return .unsupported(.measureNotAvailable)
        }
    }

    private func metric(
        value: MarinaValue,
        request: MarinaFormulaRequest,
        evidenceRows: [MarinaQueryableRow],
        details: [MarinaFormulaMetricDetail],
        source: MarinaFormulaSource = .marinaBudgetFormulaCalculator
    ) -> MarinaFormulaResult {
        .metric(
            MarinaFormulaMetric(
                value: value,
                evidenceRows: evidenceRows,
                measure: request.measure,
                source: source,
                details: details
            )
        )
    }

    private func categoryMetric(
        request: MarinaFormulaRequest,
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaFormulaResult {
        guard let dateRange = request.dateRange else {
            return .unsupported(.missingDateField)
        }

        switch request.measure {
        case .categoryAvailability:
            return categoryAvailabilityMetric(request: request, snapshot: snapshot, dateRange: dateRange)
        case .concentration:
            return categoryConcentrationMetric(request: request, snapshot: snapshot, dateRange: dateRange)
        case .amount,
             .plannedAmount,
             .actualAmount,
             .effectiveAmount,
             .budgetImpact,
             .savingsTotal,
             .incomeAmount,
             .reconciliationBalance,
             .remainingRoom,
             .burnRate,
             .projectedSpend,
             .safeDailySpend,
             .paceDifference,
             .coverageRatio,
             .recurringBurden,
             .color,
             .name:
            return .unsupported(.measureNotAvailable)
        }
    }

    private func categoryAvailabilityMetric(
        request: MarinaFormulaRequest,
        snapshot: MarinaWorkspaceSnapshot,
        dateRange: HomeQueryDateRange
    ) -> MarinaFormulaResult {
        let result = HomeCategoryLimitsAggregator.build(
            budgets: snapshot.budgets,
            categories: snapshot.categories,
            plannedExpenses: snapshot.homeCalculationPlannedExpenses,
            variableExpenses: snapshot.homeCalculationVariableExpenses,
            rangeStart: dateRange.startDate,
            rangeEnd: dateRange.endDate,
            calendar: calendar
        )

        guard let activeBudget = result.activeBudget,
              result.metrics.isEmpty == false else {
            return .unsupported(.unsupportedCombination)
        }

        return metric(
            value: .integer(result.metrics.count),
            request: request,
            evidenceRows: [],
            details: [
                .init(.activeBudget, value: .text(activeBudget.name)),
                .init(.overCount, value: .integer(result.overCount), style: .integer),
                .init(.nearCount, value: .integer(result.nearCount), style: .integer),
                .init(.categoryCount, value: .integer(result.metrics.count), style: .integer)
            ],
            source: .homeCategoryLimitsAggregator
        )
    }

    private func categoryConcentrationMetric(
        request: MarinaFormulaRequest,
        snapshot: MarinaWorkspaceSnapshot,
        dateRange: HomeQueryDateRange
    ) -> MarinaFormulaResult {
        let result = HomeCategoryMetricsCalculator.calculate(
            categories: snapshot.categories,
            plannedExpenses: snapshot.homeCalculationPlannedExpenses,
            variableExpenses: snapshot.homeCalculationVariableExpenses,
            rangeStart: dateRange.startDate,
            rangeEnd: dateRange.endDate
        )

        guard result.totalSpent > 0 else {
            return .unsupported(.unsupportedCombination)
        }

        let selected: (name: String, total: Double)?
        let categoryRows = evidenceRows(surface: request.surface, request: request, snapshot: snapshot)
        if request.filters.isEmpty == false || request.search != nil {
            guard categoryRows.count == 1 else {
                return categoryRows.isEmpty ? .unsupported(.unresolvedEntity) : .unsupported(.ambiguousEntity)
            }
            let row = categoryRows[0]
            let metric = result.metrics.first { $0.categoryID == row.id }
            selected = (row.displayName, metric?.totalSpent ?? 0)
        } else {
            selected = result.metrics.first.map { ($0.categoryName, $0.totalSpent) }
        }

        guard let selected,
              let concentration = MarinaBudgetFormulaCalculator.concentration(
                partTotal: selected.total,
                wholeTotal: result.totalSpent
              ) else {
            return .unsupported(.unsupportedCombination)
        }

        return metric(
            value: .number(concentration),
            request: request,
            evidenceRows: [],
            details: [
                .init(.category, value: .text(selected.name)),
                .init(.categorySpend, value: .money(selected.total), style: .money),
                .init(.totalSpend, value: .money(result.totalSpent), style: .money),
                .init(.concentration, value: .number(concentration), style: .percent)
            ],
            source: .homeCategoryMetricsCalculator
        )
    }

    private func recurringBurdenMetric(
        request: MarinaFormulaRequest,
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaFormulaResult {
        guard let dateRange = request.dateRange else {
            return .unsupported(.missingDateField)
        }

        let recurringTotal = MarinaBudgetFormulaCalculator.plannedExpenseTotal(
            snapshot: snapshot,
            range: dateRange,
            recurringOnly: true
        )
        let plannedExpenseTotal = MarinaBudgetFormulaCalculator.plannedExpenseTotal(
            snapshot: snapshot,
            range: dateRange
        )

        guard let recurringBurden = MarinaBudgetFormulaCalculator.recurringBurden(
            recurringTotal: recurringTotal,
            plannedExpenseTotal: plannedExpenseTotal
        ) else {
            return .unsupported(.unsupportedCombination)
        }

        return metric(
            value: .number(recurringBurden),
            request: request,
            evidenceRows: [],
            details: [
                .init(.recurringTotal, value: .money(recurringTotal), style: .money),
                .init(.plannedExpenses, value: .money(plannedExpenseTotal), style: .money),
                .init(.recurringBurden, value: .number(recurringBurden), style: .percent)
            ]
        )
    }

    private func forecastSavingsMetric(
        request: MarinaFormulaRequest,
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaFormulaResult {
        guard let dateRange = request.dateRange else {
            return .unsupported(.missingDateField)
        }

        let summary = MarinaSavingsForecastCalculator.calculate(
            range: dateRange,
            incomes: snapshot.incomes,
            plannedExpenses: snapshot.homeCalculationPlannedExpenses,
            variableExpenses: snapshot.homeCalculationVariableExpenses,
            savingsEntries: snapshot.savingsEntries
        )

        guard summary.hasActivity else {
            return .unsupported(.unsupportedCombination)
        }

        return metric(
            value: .money(summary.projectedSavings),
            request: request,
            evidenceRows: [],
            details: [
                .init(.projectedSavings, value: .money(summary.projectedSavings), style: .money),
                .init(.actualSavings, value: .money(summary.actualSavings), style: .money),
                .init(.gapToProjected, value: .money(summary.gapToProjected), style: .deltaMoney),
                .init(.forecastStatus, value: .text(summary.statusLine))
            ],
            source: .marinaSavingsForecastCalculator
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
