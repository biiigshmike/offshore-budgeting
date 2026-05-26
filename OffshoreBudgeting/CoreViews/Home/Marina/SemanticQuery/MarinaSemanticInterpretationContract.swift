import Foundation

enum MarinaSemanticInterpretationContractID: String, Codable, CaseIterable, Sendable, Equatable {
    case currentWorkspace
    case activeBudgetStatus
    case periodOverview
    case budgetSummary
    case spendTotal
    case categorySpendRanking
    case entityLookup
    case savingsStatus
    case savingsActivity
    case incomeStatus
    case reconciliationBalance
    case budgetLinkedRelationships
    case plannedExpenseDueRows
    case categoryRemaining
    case safeSpendRemaining
    case transactionActivity
    case reconciliationActivity
    case presetDetails
}

enum MarinaSemanticContractDatePolicy: String, Codable, Sendable, Equatable {
    case ignored
    case optional
    case required
    case defaultHomeRange
    case currentPeriod
    case budgetRange
}

enum MarinaSemanticContractClarificationPolicy: String, Codable, Sendable, Equatable {
    case askOnAnyAmbiguity
    case autoResolveUniqueStableTarget
    case refuseIfMissingRequiredSlot
    case unsupportedWithKnownContract
}

struct MarinaSemanticInterpretationContract: Codable, Sendable, Equatable, Identifiable {
    let id: MarinaSemanticInterpretationContractID
    let metricContractID: MarinaMetricContractID?
    let subject: MarinaSubject
    let operation: MarinaCandidateOperation
    let measure: MarinaCandidateMeasure
    let responseShape: MarinaResponseShapeHint
    let allowedEntityTypes: [MarinaCandidateEntityTypeHint]
    let requiredEntityTypes: [MarinaCandidateEntityTypeHint]
    let datePolicy: MarinaSemanticContractDatePolicy
    let clarificationPolicy: MarinaSemanticContractClarificationPolicy
    let routeKind: MarinaRouteIntentKind
    let preferredExecutorRoute: MarinaPreferredExecutorRoute
    let homeMetric: HomeQueryMetric?

    var requiresEntityTarget: Bool {
        requiredEntityTypes.isEmpty == false
    }
}

struct MarinaSemanticInterpretationContractRegistry: Sendable {
    nonisolated static let current = MarinaSemanticInterpretationContractRegistry()

    let contracts: [MarinaSemanticInterpretationContract]

    init(contracts: [MarinaSemanticInterpretationContract] = Self.defaultContracts) {
        self.contracts = contracts
    }

    func contract(for id: MarinaSemanticInterpretationContractID) -> MarinaSemanticInterpretationContract? {
        contracts.first { $0.id == id }
    }

    func contract(for homeMetric: HomeQueryMetric) -> MarinaSemanticInterpretationContract? {
        contracts.first { $0.homeMetric == homeMetric }
    }

    private nonisolated static let defaultContracts: [MarinaSemanticInterpretationContract] = [
        contract(
            .currentWorkspace,
            subject: .workspaces,
            operation: .lookupDetails,
            measure: .transactionAmount,
            responseShape: .summaryCard,
            datePolicy: .ignored,
            routeKind: .currentWorkspace,
            preferredExecutorRoute: .databaseLookup
        ),
        contract(
            .activeBudgetStatus,
            subject: .budgets,
            operation: .lookupDetails,
            measure: .remainingBudget,
            responseShape: .summaryCard,
            datePolicy: .ignored,
            routeKind: .activeBudget,
            preferredExecutorRoute: .composableWorkspace
        ),
        contract(
            .periodOverview,
            metricContractID: .periodOverview,
            subject: .budgets,
            operation: .lookupDetails,
            measure: .remainingBudget,
            responseShape: .summaryCard,
            datePolicy: .defaultHomeRange,
            routeKind: .periodOverview,
            preferredExecutorRoute: .homeAdapter,
            homeMetric: .overview
        ),
        contract(
            .budgetSummary,
            metricContractID: .periodOverview,
            subject: .budgets,
            operation: .sum,
            measure: .spend,
            responseShape: .summaryCard,
            allowedEntityTypes: [.budget],
            requiredEntityTypes: [.budget],
            datePolicy: .budgetRange,
            clarificationPolicy: .askOnAnyAmbiguity,
            routeKind: .budgetSummary,
            preferredExecutorRoute: .composableWorkspace
        ),
        contract(
            .spendTotal,
            subject: .variableExpenses,
            operation: .sum,
            measure: .spend,
            responseShape: .scalarCurrency,
            allowedEntityTypes: [.category, .card, .merchant, .expense, .transaction, .allocationAccount],
            datePolicy: .optional,
            routeKind: .broadSpend,
            preferredExecutorRoute: .aggregate,
            homeMetric: .spendTotal
        ),
        contract(
            .categorySpendRanking,
            subject: .variableExpenses,
            operation: .rank,
            measure: .spend,
            responseShape: .rankedList,
            allowedEntityTypes: [.category],
            datePolicy: .currentPeriod,
            routeKind: .broadSpend,
            preferredExecutorRoute: .homeAdapter,
            homeMetric: .topCategories
        ),
        contract(
            .entityLookup,
            subject: .workspaces,
            operation: .lookupDetails,
            measure: .transactionAmount,
            responseShape: .summaryCard,
            allowedEntityTypes: MarinaCandidateEntityTypeHint.allCases,
            datePolicy: .ignored,
            routeKind: .databaseLookup,
            preferredExecutorRoute: .databaseLookup
        ),
        contract(
            .savingsStatus,
            subject: .savingsAccounts,
            operation: .lookupDetails,
            measure: .savings,
            responseShape: .summaryCard,
            allowedEntityTypes: [.savingsAccount],
            datePolicy: .currentPeriod,
            routeKind: .savingsStatus,
            preferredExecutorRoute: .homeAdapter,
            homeMetric: .savingsStatus
        ),
        contract(
            .savingsActivity,
            subject: .savingsLedgerEntries,
            operation: .listRows,
            measure: .savingsMovement,
            responseShape: .rankedList,
            allowedEntityTypes: [.savingsAccount],
            datePolicy: .optional,
            routeKind: .savingsActivity,
            preferredExecutorRoute: .workspaceAggregation
        ),
        contract(
            .incomeStatus,
            metricContractID: .incomeActualVsExpected,
            subject: .income,
            operation: .sum,
            measure: .income,
            responseShape: .summaryCard,
            allowedEntityTypes: [.incomeSource],
            datePolicy: .currentPeriod,
            routeKind: .incomePlannedVsActual,
            preferredExecutorRoute: .workspaceAggregation
        ),
        contract(
            .reconciliationBalance,
            metricContractID: .reconciliationOwedThisMonth,
            subject: .reconciliationAccounts,
            operation: .lookupDetails,
            measure: .reconciliationBalance,
            responseShape: .summaryCard,
            allowedEntityTypes: [.allocationAccount],
            requiredEntityTypes: [.allocationAccount],
            datePolicy: .optional,
            routeKind: .reconciliationBalance,
            preferredExecutorRoute: .workspaceAggregation
        ),
        contract(
            .budgetLinkedRelationships,
            subject: .budgets,
            operation: .lookupDetails,
            measure: .remainingBudget,
            responseShape: .relationshipList,
            allowedEntityTypes: [.budget, .card, .preset, .category],
            datePolicy: .budgetRange,
            routeKind: .budgetMembership,
            preferredExecutorRoute: .composableWorkspace
        ),
        contract(
            .plannedExpenseDueRows,
            subject: .plannedExpenses,
            operation: .listRows,
            measure: .presetAmount,
            responseShape: .rankedList,
            allowedEntityTypes: [.preset, .category, .card],
            datePolicy: .optional,
            routeKind: .plannedExpenseRows,
            preferredExecutorRoute: .workspaceAggregation
        ),
        contract(
            .categoryRemaining,
            subject: .budgets,
            operation: .lookupDetails,
            measure: .remainingBudget,
            responseShape: .summaryCard,
            allowedEntityTypes: [.category],
            requiredEntityTypes: [.category],
            datePolicy: .currentPeriod,
            routeKind: .budgetCategoryLimit,
            preferredExecutorRoute: .composableWorkspace
        ),
        contract(
            .safeSpendRemaining,
            subject: .budgets,
            operation: .lookupDetails,
            measure: .remainingBudget,
            responseShape: .summaryCard,
            datePolicy: .currentPeriod,
            routeKind: .generic,
            preferredExecutorRoute: .homeAdapter,
            homeMetric: .safeSpendToday
        ),
        contract(
            .transactionActivity,
            subject: .variableExpenses,
            operation: .listRows,
            measure: .transactionAmount,
            responseShape: .rankedList,
            allowedEntityTypes: [.card, .category, .merchant, .expense, .transaction],
            datePolicy: .optional,
            routeKind: .recentTransactionRows,
            preferredExecutorRoute: .composableWorkspace
        ),
        contract(
            .reconciliationActivity,
            subject: .reconciliationAccounts,
            operation: .listRows,
            measure: .reconciliationBalance,
            responseShape: .rankedList,
            allowedEntityTypes: [.allocationAccount],
            requiredEntityTypes: [.allocationAccount],
            datePolicy: .currentPeriod,
            routeKind: .reconciliationActivity,
            preferredExecutorRoute: .composableWorkspace
        ),
        contract(
            .presetDetails,
            subject: .presets,
            operation: .lookupDetails,
            measure: .presetAmount,
            responseShape: .summaryCard,
            allowedEntityTypes: [.preset],
            requiredEntityTypes: [.preset],
            datePolicy: .ignored,
            routeKind: .presetTemplateRows,
            preferredExecutorRoute: .databaseLookup
        )
    ]

    private nonisolated static func contract(
        _ id: MarinaSemanticInterpretationContractID,
        metricContractID: MarinaMetricContractID? = nil,
        subject: MarinaSubject,
        operation: MarinaCandidateOperation,
        measure: MarinaCandidateMeasure,
        responseShape: MarinaResponseShapeHint,
        allowedEntityTypes: [MarinaCandidateEntityTypeHint] = [],
        requiredEntityTypes: [MarinaCandidateEntityTypeHint] = [],
        datePolicy: MarinaSemanticContractDatePolicy,
        clarificationPolicy: MarinaSemanticContractClarificationPolicy = .autoResolveUniqueStableTarget,
        routeKind: MarinaRouteIntentKind,
        preferredExecutorRoute: MarinaPreferredExecutorRoute,
        homeMetric: HomeQueryMetric? = nil
    ) -> MarinaSemanticInterpretationContract {
        MarinaSemanticInterpretationContract(
            id: id,
            metricContractID: metricContractID,
            subject: subject,
            operation: operation,
            measure: measure,
            responseShape: responseShape,
            allowedEntityTypes: allowedEntityTypes,
            requiredEntityTypes: requiredEntityTypes,
            datePolicy: datePolicy,
            clarificationPolicy: clarificationPolicy,
            routeKind: routeKind,
            preferredExecutorRoute: preferredExecutorRoute,
            homeMetric: homeMetric
        )
    }
}

@MainActor
struct MarinaSemanticInterpretationContractResolver {
    private let registry: MarinaSemanticInterpretationContractRegistry
    private var calendar: Calendar

    init(
        registry: MarinaSemanticInterpretationContractRegistry = .current,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.registry = registry
        self.calendar = calendar
        if self.calendar.timeZone.secondsFromGMT() == 0 {
            self.calendar.timeZone = .current
        }
    }

    func resolve(
        prompt: String,
        context: MarinaTurnContext,
        priorInterpretation: MarinaCanonicalReadInterpretation? = nil,
        failureDiagnostic: MarinaFoundationModelsFailureDiagnostic? = nil
    ) -> MarinaCanonicalReadInterpretation? {
        let normalizedPrompt = normalized(prompt)
        guard normalizedPrompt.isEmpty == false,
              MarinaRoutePatternRegistry.isReadOnlyStep5Mutation(prompt) == nil else {
            return nil
        }

        if let contextInterpretation = currentContextInterpretation(
            prompt: prompt,
            normalizedPrompt: normalizedPrompt,
            failureDiagnostic: failureDiagnostic
        ) {
            return contextInterpretation
        }

        if let budgetInterpretation = budgetSummaryInterpretation(
            prompt: prompt,
            normalizedPrompt: normalizedPrompt,
            context: context,
            failureDiagnostic: failureDiagnostic
        ) {
            return budgetInterpretation
        }

        if let overviewInterpretation = periodOverviewInterpretation(
            prompt: prompt,
            normalizedPrompt: normalizedPrompt,
            context: context,
            failureDiagnostic: failureDiagnostic
        ) {
            return overviewInterpretation
        }

        if let categoryRankingInterpretation = categoryRankingInterpretation(
            prompt: prompt,
            normalizedPrompt: normalizedPrompt,
            context: context,
            failureDiagnostic: failureDiagnostic
        ) {
            return categoryRankingInterpretation
        }

        if let savingsInterpretation = savingsInterpretation(
            prompt: prompt,
            normalizedPrompt: normalizedPrompt,
            context: context,
            failureDiagnostic: failureDiagnostic
        ) {
            return savingsInterpretation
        }

        if let priorInterpretation,
           case .unsupported = priorInterpretation.result,
           let rowInterpretation = freeTextExpenseRowsInterpretation(
            prompt: prompt,
            normalizedPrompt: normalizedPrompt,
            failureDiagnostic: failureDiagnostic
           ) {
            return rowInterpretation
        }

        if let priorInterpretation,
           case .unsupported = priorInterpretation.result,
           let lookupInterpretation = bareEntityLookupInterpretation(
            prompt: prompt,
            normalizedPrompt: normalizedPrompt,
            context: context,
            failureDiagnostic: failureDiagnostic
           ) {
            return lookupInterpretation
        }

        return nil
    }

    private func currentContextInterpretation(
        prompt: String,
        normalizedPrompt: String,
        failureDiagnostic: MarinaFoundationModelsFailureDiagnostic?
    ) -> MarinaCanonicalReadInterpretation? {
        if asksForCurrentWorkspace(normalizedPrompt),
           let contract = registry.contract(for: .currentWorkspace) {
            let request = MarinaDatabaseLookupRequest(
                rawPrompt: prompt,
                searchText: "",
                objectTypes: [.workspace],
                dateRange: nil,
                limit: 1,
                requestedDetail: .general,
                lookupMode: .entityDetail
            ).clamped
            let candidate = MarinaQueryPlanCandidate(
                requestFamily: .databaseLookup,
                source: .foundationModels,
                rawPrompt: prompt,
                operation: contract.operation,
                measure: contract.measure,
                responseShapeHint: contract.responseShape,
                confidence: .high,
                databaseLookupRequest: request,
                routeIntent: routeIntent(for: contract, targetTypes: [.workspace])
            )
            return canonicalInterpretation(
                candidate: candidate,
                repairSummary: repairSummary(contract: contract, failureDiagnostic: failureDiagnostic)
            )
        }

        if asksForActiveBudget(normalizedPrompt),
           let contract = registry.contract(for: .activeBudgetStatus) {
            let candidate = MarinaQueryPlanCandidate(
                source: .foundationModels,
                rawPrompt: prompt,
                operation: contract.operation,
                measure: contract.measure,
                responseShapeHint: contract.responseShape,
                confidence: .high,
                routeIntent: routeIntent(for: contract, targetTypes: [.budget])
            )
            return canonicalInterpretation(
                candidate: candidate,
                repairSummary: repairSummary(contract: contract, failureDiagnostic: failureDiagnostic)
            )
        }

        return nil
    }

    private func budgetSummaryInterpretation(
        prompt: String,
        normalizedPrompt: String,
        context: MarinaTurnContext,
        failureDiagnostic: MarinaFoundationModelsFailureDiagnostic?
    ) -> MarinaCanonicalReadInterpretation? {
        guard mentionsBudget(normalizedPrompt),
              isBudgetLimitPrompt(normalizedPrompt) == false,
              asksForBudgetSummary(normalizedPrompt),
              let contract = registry.contract(for: .budgetSummary) else {
            return nil
        }

        let dateMention = explicitMonthMention(in: normalizedPrompt, now: context.now)
            ?? explicitDateRange(in: prompt, context: context)
        let matches = budgetMatches(
            prompt: normalizedPrompt,
            dateRange: dateMention?.range,
            provider: context.provider
        )

        if matches.count == 1, let match = matches.first {
            return budgetSummaryInterpretation(
                contract: contract,
                budget: match.budget,
                dateRange: budgetRange(match.budget),
                prompt: prompt,
                repairSummary: repairSummary(contract: contract, failureDiagnostic: failureDiagnostic)
            )
        }

        if matches.count > 1 {
            return budgetClarificationInterpretation(
                contract: contract,
                matches: matches,
                prompt: prompt,
                message: "I found more than one budget that could match that period. Choose the summary you want Marina to run.",
                failureDiagnostic: failureDiagnostic
            )
        }

        if let dateRange = dateMention?.range {
            return periodOverviewInterpretation(
                prompt: prompt,
                dateRange: dateRange,
                rawDateText: dateMention?.rawText,
                context: context,
                failureDiagnostic: failureDiagnostic
            )
        }

        return periodOverviewInterpretation(
            prompt: prompt,
            normalizedPrompt: normalizedPrompt,
            context: context,
            failureDiagnostic: failureDiagnostic
        )
    }

    private func periodOverviewInterpretation(
        prompt: String,
        normalizedPrompt: String,
        context: MarinaTurnContext,
        failureDiagnostic: MarinaFoundationModelsFailureDiagnostic?
    ) -> MarinaCanonicalReadInterpretation? {
        guard isBudgetLimitPrompt(normalizedPrompt) == false else { return nil }
        guard asksForPeriodOverview(normalizedPrompt) else { return nil }
        let dateMention = explicitMonthMention(in: normalizedPrompt, now: context.now)
            ?? explicitDateRange(in: prompt, context: context)
        if let dateRange = dateMention?.range,
           let budgetContract = registry.contract(for: .budgetSummary) {
            let matches = budgetMatches(
                prompt: normalizedPrompt,
                dateRange: dateRange,
                provider: context.provider
            )
            if matches.count == 1, let match = matches.first {
                return budgetSummaryInterpretation(
                    contract: budgetContract,
                    budget: match.budget,
                    dateRange: budgetRange(match.budget),
                    prompt: prompt,
                    repairSummary: repairSummary(contract: budgetContract, failureDiagnostic: failureDiagnostic)
                )
            }
            if matches.count > 1 {
                return budgetClarificationInterpretation(
                    contract: budgetContract,
                    matches: matches,
                    prompt: prompt,
                    message: "I found more than one budget that could match that period. Choose the summary you want Marina to run.",
                    failureDiagnostic: failureDiagnostic
                )
            }
        }
        return periodOverviewInterpretation(
            prompt: prompt,
            dateRange: dateMention?.range ?? context.routerContext.ambientDateRange,
            rawDateText: dateMention?.rawText,
            context: context,
            failureDiagnostic: failureDiagnostic
        )
    }

    private func periodOverviewInterpretation(
        prompt: String,
        dateRange: HomeQueryDateRange?,
        rawDateText: String?,
        context: MarinaTurnContext,
        failureDiagnostic: MarinaFoundationModelsFailureDiagnostic?
    ) -> MarinaCanonicalReadInterpretation? {
        guard let contract = registry.contract(for: .periodOverview) else { return nil }
        let routeIntent = routeIntent(for: contract, targetTypes: [])
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: prompt,
            operation: contract.operation,
            measure: contract.measure,
            entityMentions: [],
            timeScopes: dateRange.map {
                [
                    MarinaUnresolvedTimeScope(
                        role: .primary,
                        rawText: rawDateText,
                        resolvedRangeHint: $0,
                        periodUnitHint: .month
                    )
                ]
            } ?? [],
            responseShapeHint: contract.responseShape,
            confidence: .high,
            routeIntent: routeIntent
        )
        return canonicalInterpretation(
            candidate: candidate,
            repairSummary: repairSummary(contract: contract, failureDiagnostic: failureDiagnostic)
        )
    }

    private func budgetSummaryInterpretation(
        contract: MarinaSemanticInterpretationContract,
        budget: Budget,
        dateRange: HomeQueryDateRange,
        prompt: String,
        repairSummary: String
    ) -> MarinaCanonicalReadInterpretation {
        let routeIntent = routeIntent(for: contract, targetTypes: [.budget])
        let mention = MarinaUnresolvedEntityMention(
            role: .primaryTarget,
            rawText: budget.name,
            typeHint: .budget,
            allowedTypeHints: [.budget],
            confidence: .high
        )
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: prompt,
            operation: contract.operation,
            measure: contract.measure,
            entityMentions: [mention],
            timeScopes: [
                MarinaUnresolvedTimeScope(
                    role: .primary,
                    rawText: budget.name,
                    resolvedRangeHint: dateRange,
                    periodUnitHint: .month
                )
            ],
            responseShapeHint: contract.responseShape,
            confidence: .high,
            routeIntent: routeIntent
        )
        return canonicalInterpretation(candidate: candidate, repairSummary: repairSummary)
    }

    private func budgetClarificationInterpretation(
        contract: MarinaSemanticInterpretationContract,
        matches: [BudgetMatch],
        prompt: String,
        message: String,
        failureDiagnostic: MarinaFoundationModelsFailureDiagnostic?
    ) -> MarinaCanonicalReadInterpretation {
        let baseCandidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: prompt,
            operation: contract.operation,
            measure: contract.measure,
            responseShapeHint: .clarification,
            confidence: .high,
            routeIntent: routeIntent(for: contract, targetTypes: [.budget])
        )
        let choices = matches.prefix(6).map { match in
            let dateRange = HomeQueryDateRange(startDate: match.budget.startDate, endDate: match.budget.endDate)
            let interpretation = budgetSummaryInterpretation(
                contract: contract,
                budget: match.budget,
                dateRange: dateRange,
                prompt: prompt,
                repairSummary: repairSummary(contract: contract, failureDiagnostic: failureDiagnostic)
            )
            return MarinaClarificationChoice(
                title: "Show budget summary: \(match.budget.name)",
                subtitle: "Budget • \(rangeLabel(dateRange))",
                entityRole: .primaryTarget,
                entityTypeHint: .budget,
                patchSlot: .target,
                rawValue: match.budget.name,
                sourceID: match.budget.id,
                resumeIntent: resumeIntent(from: interpretation)
            )
        }
        let clarification = MarinaTypedClarification(
            kind: .ambiguousTarget,
            message: message,
            candidate: baseCandidate,
            patchSlot: .target,
            choices: choices
        )
        return MarinaCanonicalReadInterpretation(
            result: .clarification(clarification),
            compatibilityCandidate: baseCandidate,
            repairSummary: repairSummary(contract: contract, failureDiagnostic: failureDiagnostic)
        )
    }

    private func savingsInterpretation(
        prompt: String,
        normalizedPrompt: String,
        context: MarinaTurnContext,
        failureDiagnostic: MarinaFoundationModelsFailureDiagnostic?
    ) -> MarinaCanonicalReadInterpretation? {
        guard normalizedPrompt.contains("savings") || normalizedPrompt.contains("saving") else { return nil }
        let id: MarinaSemanticInterpretationContractID
        if normalizedPrompt.contains("activity")
            || normalizedPrompt.contains("ledger")
            || normalizedPrompt.contains("movement")
            || normalizedPrompt.contains("transactions") {
            id = .savingsActivity
        } else if normalizedPrompt.contains("status")
                    || normalizedPrompt.contains("balance")
                    || normalizedPrompt.contains("doing")
                    || normalizedPrompt.contains("track") {
            id = .savingsStatus
        } else {
            return nil
        }
        guard let contract = registry.contract(for: id) else { return nil }
        let dateMention = explicitMonthMention(in: normalizedPrompt, now: context.now)
            ?? explicitDateRange(in: prompt, context: context)
        let grouping = id == .savingsActivity
            ? MarinaGroupingCandidate(dimension: .savingsLedgerEntry, rawText: "savings activity")
            : nil
        let ranking = id == .savingsActivity
            ? MarinaRankingCandidate(direction: .newest, limit: 10, rawText: "newest")
            : nil
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: prompt,
            operation: contract.operation,
            measure: contract.measure,
            timeScopes: dateMention.map { mention in
                [
                    MarinaUnresolvedTimeScope(
                        role: .primary,
                        rawText: mention.rawText,
                        resolvedRangeHint: mention.range,
                        periodUnitHint: .month
                    )
                ]
            } ?? [],
            grouping: grouping,
            ranking: ranking,
            limit: ranking?.limit,
            responseShapeHint: contract.responseShape,
            confidence: .high,
            routeIntent: routeIntent(for: contract, targetTypes: [])
        )
        return canonicalInterpretation(
            candidate: candidate,
            repairSummary: repairSummary(contract: contract, failureDiagnostic: failureDiagnostic)
        )
    }

    private func categoryRankingInterpretation(
        prompt: String,
        normalizedPrompt: String,
        context: MarinaTurnContext,
        failureDiagnostic: MarinaFoundationModelsFailureDiagnostic?
    ) -> MarinaCanonicalReadInterpretation? {
        guard asksForTopCategorySpend(normalizedPrompt),
              let contract = registry.contract(for: .categorySpendRanking) else {
            return nil
        }
        let dateMention = explicitMonthMention(in: normalizedPrompt, now: context.now)
            ?? explicitDateRange(in: prompt, context: context)
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: prompt,
            operation: contract.operation,
            measure: contract.measure,
            timeScopes: dateMention.map { mention in
                [
                    MarinaUnresolvedTimeScope(
                        role: .primary,
                        rawText: mention.rawText,
                        resolvedRangeHint: mention.range,
                        periodUnitHint: .month
                    )
                ]
            } ?? [],
            grouping: MarinaGroupingCandidate(dimension: .category, rawText: "category"),
            ranking: MarinaRankingCandidate(direction: .top, limit: 1, rawText: "top"),
            limit: 1,
            responseShapeHint: contract.responseShape,
            confidence: .high,
            routeIntent: MarinaRouteIntent(
                kind: contract.routeKind,
                subject: contract.subject,
                operation: contract.operation,
                measure: contract.measure,
                grouping: .category,
                targetTypes: [.category],
                requestedDetail: nil,
                responseShape: contract.responseShape,
                preferredExecutorRoute: contract.preferredExecutorRoute
            )
        )
        return canonicalInterpretation(
            candidate: candidate,
            repairSummary: repairSummary(contract: contract, failureDiagnostic: failureDiagnostic)
        )
    }

    private func bareEntityLookupInterpretation(
        prompt: String,
        normalizedPrompt: String,
        context: MarinaTurnContext,
        failureDiagnostic: MarinaFoundationModelsFailureDiagnostic?
    ) -> MarinaCanonicalReadInterpretation? {
        guard normalizedPrompt.hasPrefix("show ") || normalizedPrompt.hasPrefix("find ") || normalizedPrompt.hasPrefix("list ") else {
            return nil
        }
        let searchText = prompt
            .replacingOccurrences(of: #"^\s*(show|find|list)\s+(my\s+)?"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard searchText.isEmpty == false,
              let contract = registry.contract(for: .entityLookup) else {
            return nil
        }
        if hasActionableEntityMatch(for: searchText, provider: context.provider) {
            return nil
        }
        let request = MarinaDatabaseLookupRequest(
            rawPrompt: prompt,
            searchText: searchText,
            objectTypes: MarinaLookupObjectType.safeDefaultSearchTypes,
            dateRange: nil,
            limit: 5,
            requestedDetail: .general,
            lookupMode: .broadSearch
        ).clamped
        let candidate = MarinaQueryPlanCandidate(
            requestFamily: .databaseLookup,
            source: .foundationModels,
            rawPrompt: prompt,
            operation: .lookupDetails,
            measure: .transactionAmount,
            responseShapeHint: .summaryCard,
            confidence: .medium,
            databaseLookupRequest: request,
            routeIntent: routeIntent(for: contract, targetTypes: [])
        )
        return canonicalInterpretation(
            candidate: candidate,
            repairSummary: repairSummary(contract: contract, failureDiagnostic: failureDiagnostic)
        )
    }

    private func freeTextExpenseRowsInterpretation(
        prompt: String,
        normalizedPrompt: String,
        failureDiagnostic: MarinaFoundationModelsFailureDiagnostic?
    ) -> MarinaCanonicalReadInterpretation? {
        guard normalizedPrompt.hasPrefix("show ")
                || normalizedPrompt.hasPrefix("find ")
                || normalizedPrompt.hasPrefix("list ") else {
            return nil
        }
        guard containsAny(["expense", "expenses", "transaction", "transactions", "purchase", "purchases"], in: normalizedPrompt) else {
            return nil
        }
        guard let searchText = freeTextExpenseSearchText(prompt) else {
            return nil
        }

        let query = MarinaSemanticQuery(
            subject: .variableExpenses,
            operation: .list,
            filters: [
                MarinaFilter(
                    role: .filter,
                    relationship: .merchant,
                    value: searchText,
                    matchMode: .freeText,
                    entityTypeHint: .merchant,
                    allowedEntityTypeHints: [.merchant, .expense, .transaction],
                    sourceID: nil
                )
            ],
            amountField: .amount,
            grouping: MarinaGrouping(dimension: .transaction, rawText: "transaction"),
            ranking: MarinaRanking(direction: .newest, limit: 10, rawText: "newest"),
            limit: 10,
            responseShape: .rankedList,
            routeIntent: MarinaRouteIntent(
                kind: .recentTransactionRows,
                subject: .variableExpenses,
                operation: .listRows,
                measure: .transactionAmount,
                grouping: .transaction,
                targetTypes: [.merchant, .expense, .transaction],
                requestedDetail: nil,
                responseShape: .rankedList,
                preferredExecutorRoute: .list
            )
        )
        let candidate = MarinaSemanticQueryAdapter().compatibilityCandidate(from: query, prompt: prompt)
        return MarinaCanonicalReadInterpretation(
            result: .query(query),
            compatibilityCandidate: candidate,
            repairSummary: [
                "semanticContract=freeTextExpenseRows",
                failureDiagnostic.map { "foundationFailure=\($0.category.rawValue)" }
            ]
            .compactMap { $0 }
            .joined(separator: ",")
        )
    }

    private func freeTextExpenseSearchText(_ prompt: String) -> String? {
        let cleaned = prompt
            .replacingOccurrences(of: #"(?i)^\s*(show|find|list)\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\b(me|all|of|my|the|please)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\b(expense|expenses|transaction|transactions|purchase|purchases|rows?|records?)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ?.\"'"))
        guard cleaned.isEmpty == false,
              isGenericSearchText(cleaned) == false else {
            return nil
        }
        return cleaned
    }

    private func isGenericSearchText(_ value: String) -> Bool {
        let normalized = normalized(value)
        return [
            "expense",
            "expenses",
            "transaction",
            "transactions",
            "purchase",
            "purchases",
            "spending",
            "spend"
        ].contains(normalized)
    }

    private func hasActionableEntityMatch(for searchText: String, provider: MarinaDataProvider) -> Bool {
        let extraction = MarinaEntityCandidateExtractor().extractCandidates(from: searchText, provider: provider)
        let actionTypes: Set<MarinaEntityCandidateTargetType> = [
            .category,
            .card,
            .budget,
            .preset,
            .incomeSource,
            .allocationAccount,
            .savingsAccount
        ]
        return extraction.matchesByType.contains { entityType, matches in
            actionTypes.contains(entityType) && matches.isEmpty == false
        }
    }

    private func canonicalInterpretation(
        candidate: MarinaQueryPlanCandidate,
        repairSummary: String
    ) -> MarinaCanonicalReadInterpretation {
        MarinaCanonicalReadInterpretation(
            result: MarinaSemanticQueryAdapter().interpretationResult(from: candidate),
            compatibilityCandidate: candidate,
            repairSummary: repairSummary
        )
    }

    private func resumeIntent(from interpretation: MarinaCanonicalReadInterpretation) -> MarinaClarificationResumeIntent {
        let semanticQuery: MarinaSemanticQuery?
        if case .query(let query) = interpretation.result {
            semanticQuery = query
        } else {
            semanticQuery = nil
        }
        return MarinaClarificationResumeIntent(
            candidate: interpretation.compatibilityCandidate,
            semanticQuery: semanticQuery
        )
    }

    private func routeIntent(
        for contract: MarinaSemanticInterpretationContract,
        targetTypes: [MarinaCandidateEntityTypeHint]
    ) -> MarinaRouteIntent {
        let requestedDetail: MarinaSemanticRequestedDetail?
        switch contract.id {
        case .periodOverview, .activeBudgetStatus:
            requestedDetail = .status
        case .currentWorkspace:
            requestedDetail = .general
        default:
            requestedDetail = nil
        }
        return MarinaRouteIntent(
            kind: contract.routeKind,
            subject: contract.subject,
            operation: contract.operation,
            measure: contract.measure,
            grouping: nil,
            targetTypes: targetTypes,
            requestedDetail: requestedDetail,
            responseShape: contract.responseShape,
            preferredExecutorRoute: contract.preferredExecutorRoute
        )
    }

    private func repairSummary(
        contract: MarinaSemanticInterpretationContract,
        failureDiagnostic: MarinaFoundationModelsFailureDiagnostic?
    ) -> String {
        [
            "semanticContract=\(contract.id.rawValue)",
            failureDiagnostic.map { "foundationFailure=\($0.category.rawValue)" }
        ]
        .compactMap { $0 }
        .joined(separator: ",")
    }

    private func mentionsBudget(_ prompt: String) -> Bool {
        containsWord("budget", in: prompt) || containsWord("budgets", in: prompt)
    }

    private func asksForBudgetSummary(_ prompt: String) -> Bool {
        guard isBudgetLimitPrompt(prompt) == false else { return false }
        if containsAny(["summary", "overview", "status", "looking", "doing", "how is", "how am i"], in: prompt) {
            return true
        }
        return prompt.hasPrefix("show ") || prompt.hasPrefix("find ")
    }

    private func asksForPeriodOverview(_ prompt: String) -> Bool {
        guard isBudgetLimitPrompt(prompt) == false else { return false }
        if mentionsBudget(prompt),
           asksForBudgetSummary(prompt) {
            return true
        }
        return containsAny(
            [
                "how am i doing",
                "how am i looking",
                "how is my spending",
                "budget overview",
                "budget summary",
                "period overview",
                "doing this month",
                "doing for"
            ],
            in: prompt
        )
    }

    private func isBudgetLimitPrompt(_ prompt: String) -> Bool {
        containsAny(["budget limit", "category limit", "category goal"], in: prompt)
    }

    private func asksForTopCategorySpend(_ prompt: String) -> Bool {
        let mentionsCategory = containsWord("category", in: prompt) || containsWord("categories", in: prompt)
        guard mentionsCategory else { return false }
        if containsAny(["preset", "presets", "assigned"], in: prompt) {
            return false
        }
        let explicitlySpendShaped = containsAny(["spend", "spending", "spent", "expense", "expenses", "money"], in: prompt)
        let onlyCategoryRanking = containsAny(["top category", "top categories", "highest category", "largest category", "biggest category"], in: prompt)
        guard explicitlySpendShaped || onlyCategoryRanking else { return false }
        return containsAny(["top", "highest", "largest", "biggest", "most"], in: prompt)
    }

    private func asksForCurrentWorkspace(_ prompt: String) -> Bool {
        prompt.contains("workspace am i in")
            || prompt.contains("current workspace")
            || prompt.contains("which workspace")
            || prompt == "what workspace"
            || prompt.hasPrefix("what workspace ")
    }

    private func asksForActiveBudget(_ prompt: String) -> Bool {
        prompt.contains("active budget")
            || prompt.contains("current budget")
            || (prompt.contains("active") && prompt.contains("budget"))
    }

    private func budgetMatches(
        prompt: String,
        dateRange: HomeQueryDateRange?,
        provider: MarinaDataProvider
    ) -> [BudgetMatch] {
        let budgets = provider.fetchAllBudgets()
        var matches: [BudgetMatch] = []
        for budget in budgets {
            let normalizedName = normalized(budget.name)
            if prompt.contains(normalizedName), normalizedName.isEmpty == false {
                matches.append(BudgetMatch(budget: budget, score: 100))
                continue
            }
            if let month = monthToken(in: prompt),
               normalizedName.split(separator: " ").contains(where: { $0 == month }) {
                let yearScore = yearToken(in: prompt).map { normalizedName.contains($0) ? 20 : 0 } ?? 0
                matches.append(BudgetMatch(budget: budget, score: 80 + yearScore))
                continue
            }
            if let dateRange,
               range(dateRange, equalsBudget: budget) {
                matches.append(BudgetMatch(budget: budget, score: 70))
                continue
            }
            if let dateRange,
               rangesOverlap(dateRange, HomeQueryDateRange(startDate: budget.startDate, endDate: budget.endDate)) {
                matches.append(BudgetMatch(budget: budget, score: 40))
            }
        }
        let topScore = matches.map(\.score).max()
        return matches
            .filter { topScore == nil || $0.score == topScore }
            .sorted { lhs, rhs in
                if lhs.budget.startDate != rhs.budget.startDate {
                    return lhs.budget.startDate < rhs.budget.startDate
                }
                return lhs.budget.name.localizedCaseInsensitiveCompare(rhs.budget.name) == .orderedAscending
            }
    }

    private struct BudgetMatch {
        let budget: Budget
        let score: Int
    }

    private struct DateMention: Equatable {
        let rawText: String?
        let range: HomeQueryDateRange
    }

    private func budgetRange(_ budget: Budget) -> HomeQueryDateRange {
        HomeQueryDateRange(startDate: budget.startDate, endDate: budget.endDate)
    }

    private func explicitDateRange(
        in prompt: String,
        context: MarinaTurnContext
    ) -> DateMention? {
        let resolver = MarinaDateResolver(calendar: calendar, nowProvider: { context.now })
        guard let resolved = resolver.resolve(
            input: prompt,
            modelStartISO8601: nil,
            modelEndISO8601: nil,
            defaultPeriodUnit: context.defaultPeriodUnit
        ) else {
            return nil
        }
        return DateMention(rawText: nil, range: resolved.queryDateRange)
    }

    private func explicitMonthMention(in prompt: String, now: Date) -> DateMention? {
        let tokens = prompt.split(separator: " ").map(String.init)
        guard let monthIndex = tokens.firstIndex(where: { monthNumber($0) != nil }),
              let month = monthNumber(tokens[monthIndex]) else {
            return nil
        }
        let currentYear = calendar.component(.year, from: now)
        let explicitYear = adjacentYear(tokens: tokens, monthIndex: monthIndex)
        let year = explicitYear ?? currentYear
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        components.hour = 0
        components.minute = 0
        components.second = 0
        components.timeZone = calendar.timeZone
        guard let start = calendar.date(from: components),
              let endBase = calendar.date(byAdding: DateComponents(month: 1), to: start),
              let end = calendar.date(byAdding: .second, value: -1, to: endBase) else {
            return nil
        }
        let raw = explicitYear.map { "\(tokens[monthIndex]) \($0)" } ?? tokens[monthIndex]
        return DateMention(rawText: raw, range: HomeQueryDateRange(startDate: start, endDate: end))
    }

    private func monthToken(in prompt: String) -> String? {
        prompt.split(separator: " ").map(String.init).first { monthNumber($0) != nil }
    }

    private func yearToken(in prompt: String) -> String? {
        prompt.split(separator: " ").map(String.init).first { token in
            Int(token).map { (1900...2200).contains($0) } ?? false
        }
    }

    private func adjacentYear(tokens: [String], monthIndex: Int) -> Int? {
        let candidates = [
            monthIndex + 1 < tokens.count ? tokens[monthIndex + 1] : nil,
            monthIndex > 0 ? tokens[monthIndex - 1] : nil
        ].compactMap { $0 }
        return candidates.compactMap(Int.init).first { (1900...2200).contains($0) }
    }

    private func monthNumber(_ token: String) -> Int? {
        [
            "jan": 1, "january": 1,
            "feb": 2, "february": 2,
            "mar": 3, "march": 3,
            "apr": 4, "april": 4,
            "may": 5,
            "jun": 6, "june": 6,
            "jul": 7, "july": 7,
            "aug": 8, "august": 8,
            "sep": 9, "sept": 9, "september": 9,
            "oct": 10, "october": 10,
            "nov": 11, "november": 11,
            "dec": 12, "december": 12
        ][token]
    }

    private func range(_ range: HomeQueryDateRange, equalsBudget budget: Budget) -> Bool {
        calendar.isDate(range.startDate, inSameDayAs: budget.startDate)
            && calendar.isDate(range.endDate, inSameDayAs: budget.endDate)
    }

    private func rangesOverlap(_ lhs: HomeQueryDateRange, _ rhs: HomeQueryDateRange) -> Bool {
        lhs.startDate <= rhs.endDate && rhs.startDate <= lhs.endDate
    }

    private func rangeLabel(_ range: HomeQueryDateRange) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: range.startDate))-\(formatter.string(from: range.endDate))"
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsAny(_ needles: [String], in haystack: String) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    private func containsWord(_ word: String, in prompt: String) -> Bool {
        prompt.split(separator: " ").contains { $0 == word }
    }
}
