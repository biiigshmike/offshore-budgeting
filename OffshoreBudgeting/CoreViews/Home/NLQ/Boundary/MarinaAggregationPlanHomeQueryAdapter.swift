import Foundation

extension MarinaTypedUnsupportedResponse: Error {}

struct MarinaExecutableAggregationPlan: Codable, Equatable, Identifiable {
    let id: UUID
    let aggregationPlan: MarinaAggregationPlan
    let homeQueryPlan: HomeQueryPlan

    init(
        id: UUID = UUID(),
        aggregationPlan: MarinaAggregationPlan,
        homeQueryPlan: HomeQueryPlan
    ) {
        self.id = id
        self.aggregationPlan = aggregationPlan
        self.homeQueryPlan = homeQueryPlan
    }
}

struct MarinaAggregationPlanHomeQueryAdapter {
    func executablePlan(from outcome: MarinaPlanValidationOutcome) -> Result<MarinaExecutableAggregationPlan, MarinaTypedUnsupportedResponse> {
        switch outcome {
        case .executable(let plan):
            return executablePlan(from: plan)
        case .clarification(let clarification):
            return .failure(
                MarinaTypedUnsupportedResponse(
                    kind: .unsupportedCombination,
                    message: "Clarification outcomes are not executable.",
                    candidate: clarification.candidate
                )
            )
        case .unsupported(let unsupported):
            return .failure(unsupported)
        }
    }

    func executablePlan(from plan: MarinaAggregationPlan) -> Result<MarinaExecutableAggregationPlan, MarinaTypedUnsupportedResponse> {
        switch homeQueryPlan(from: plan) {
        case .success(let homeQueryPlan):
            return .success(
                MarinaExecutableAggregationPlan(
                    aggregationPlan: plan,
                    homeQueryPlan: homeQueryPlan
                )
            )
        case .failure(let unsupported):
            return .failure(unsupported)
        }
    }

    func homeQueryPlan(from plan: MarinaAggregationPlan) -> Result<HomeQueryPlan, MarinaTypedUnsupportedResponse> {
        guard plan.status == .notExecutableShell || plan.status == .executable else {
            return .failure(unsupported(.unsupportedCombination, "Only validated aggregation plans can be adapted."))
        }

        guard plan.targets.contains(where: { $0.role == .simulationInput || $0.role == .simulationOutput }) == false else {
            return .failure(unsupported(.unsupportedSimulation, "Simulation plans are not executable through the aggregation bridge."))
        }

        let filterTargets = executableFilterTargets(in: plan)
        guard filterTargets.count <= 1 else {
            return .failure(unsupported(.unsupportedCombination, "Multiple executable targets cannot be adapted without dropping filters."))
        }

        let target = filterTargets.first
        guard target.map({ isSupportedTargetType($0.entityType) }) ?? true else {
            return .failure(unsupported(.unsupportedTargetType, "That target type is not executable through HomeQueryEngine."))
        }

        guard let metric = metric(for: plan, target: target) else {
            return .failure(unsupported(.unsupportedOperation, "That aggregation plan cannot be represented faithfully as a HomeQuery."))
        }

        return .success(
            HomeQueryPlan(
                metric: metric,
                dateRange: plan.dateRange,
                comparisonDateRange: plan.comparisonDateRange,
                resultLimit: plan.limit ?? plan.ranking?.limit,
                confidenceBand: .high,
                targetName: target?.displayName,
                targetTypeRaw: target?.entityType.rawValue,
                periodUnit: nil
            )
        )
    }

    private func metric(
        for plan: MarinaAggregationPlan,
        target: MarinaResolvedAggregationTarget?
    ) -> HomeQueryMetric? {
        switch (plan.operation, plan.measure) {
        case (.sum, .spend):
            return spendTotalMetric(target: target)
        case (.average, .spend):
            guard target == nil else { return nil }
            return .spendAveragePerPeriod
        case (.average, .income):
            return .incomeAverageActual
        case (.compare, .spend):
            guard plan.comparisonDateRange != nil else { return nil }
            return spendComparisonMetric(target: target)
        case (.compare, .income):
            guard plan.comparisonDateRange != nil,
                  target?.entityType == .incomeSource else {
                return nil
            }
            return .incomeSourceMonthComparison
        case (.rank, .spend), (.rank, .transactionAmount):
            return spendRankingMetric(plan: plan)
        case (.rank, .transactionFrequency):
            guard plan.grouping?.dimension == .transaction,
                  plan.ranking?.direction == .mostFrequent else {
                return nil
            }
            return .mostFrequentTransactions
        case (.sum, .categoryShare):
            guard target == nil || target?.entityType == .category else { return nil }
            return .categorySpendShare
        default:
            return nil
        }
    }

    private func spendTotalMetric(target: MarinaResolvedAggregationTarget?) -> HomeQueryMetric? {
        guard let target else { return .spendTotal }
        switch target.entityType {
        case .category:
            return .categorySpendTotal
        case .card:
            return .cardSpendTotal
        case .merchant:
            return .merchantSpendTotal
        default:
            return nil
        }
    }

    private func spendComparisonMetric(target: MarinaResolvedAggregationTarget?) -> HomeQueryMetric? {
        guard let target else { return .monthComparison }
        switch target.entityType {
        case .category:
            return .categoryMonthComparison
        case .card:
            return .cardMonthComparison
        case .merchant:
            return .merchantMonthComparison
        default:
            return nil
        }
    }

    private func spendRankingMetric(plan: MarinaAggregationPlan) -> HomeQueryMetric? {
        guard let grouping = plan.grouping,
              let ranking = plan.ranking else {
            return nil
        }

        switch (grouping.dimension, ranking.direction) {
        case (.category, .top), (.category, .largest):
            return .topCategories
        case (.merchant, .top), (.merchant, .largest):
            return .topMerchants
        case (.transaction, .top), (.transaction, .largest):
            return .largestTransactions
        default:
            return nil
        }
    }

    private func executableFilterTargets(in plan: MarinaAggregationPlan) -> [MarinaResolvedAggregationTarget] {
        plan.targets.filter { target in
            switch target.role {
            case .filter, .primaryTarget, .comparisonTarget:
                return true
            case .groupingDimension, .simulationInput, .simulationOutput:
                return false
            }
        }
    }

    private func isSupportedTargetType(_ type: MarinaCandidateEntityTypeHint) -> Bool {
        switch type {
        case .category, .merchant, .card, .incomeSource:
            return true
        case .expense, .budget, .preset, .allocationAccount, .savingsAccount, .transaction, .workspace:
            return false
        }
    }

    private func unsupported(
        _ kind: MarinaUnsupportedResponseKind,
        _ message: String
    ) -> MarinaTypedUnsupportedResponse {
        MarinaTypedUnsupportedResponse(kind: kind, message: message)
    }
}
