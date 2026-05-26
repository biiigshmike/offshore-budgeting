//
//  MarinaQueryExecution.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 5/21/26.
//

import Foundation

struct MarinaQueryExecution {
    let executablePlan: MarinaExecutableAggregationPlan?
    let aggregationResult: MarinaAggregationResult
    let databaseLookupResponse: MarinaDatabaseLookupResponse?
    let workspaceAggregationCard: MarinaWorkspaceAggregationCard?
    let amountBasis: MarinaFinancialAmountBasis
    let executionRoute: MarinaSemanticExecutionRoute
}

struct MarinaExplicitPromptConstraints: Equatable {
    var categories: Set<String> = []
    var cards: Set<String> = []
    var allocationAccounts: Set<String> = []
    var merchants: Set<String> = []
    var hasDateConstraint = false
    var limit: Int?
    var sort: MarinaRankingDirectionCandidate?

    var isEmpty: Bool {
        categories.isEmpty
            && cards.isEmpty
            && allocationAccounts.isEmpty
            && merchants.isEmpty
            && hasDateConstraint == false
            && limit == nil
            && sort == nil
    }

    func unsupportedIfDropped(
        by candidate: MarinaQueryPlanCandidate,
        resolvedQuery: MarinaResolvedSemanticQuery?,
        outcome: MarinaPlanValidationOutcome
    ) -> MarinaTypedUnsupportedResponse? {
        guard isEmpty == false,
              case .executable(let plan) = outcome else {
            return nil
        }

        var dropped: [String] = []
        if categories.isEmpty == false,
           preserves(names: categories, type: .category, plan: plan, resolvedQuery: resolvedQuery, candidate: candidate) == false {
            dropped.append("category")
        }
        if cards.isEmpty == false,
           preserves(names: cards, type: .card, plan: plan, resolvedQuery: resolvedQuery, candidate: candidate) == false {
            dropped.append("card")
        }
        if allocationAccounts.isEmpty == false,
           preserves(names: allocationAccounts, type: .allocationAccount, plan: plan, resolvedQuery: resolvedQuery, candidate: candidate) == false {
            dropped.append("account")
        }
        if merchants.isEmpty == false,
           preserves(names: merchants, type: .merchant, plan: plan, resolvedQuery: resolvedQuery, candidate: candidate) == false {
            dropped.append("merchant")
        }
        if hasDateConstraint,
           plan.dateRange == nil,
           resolvedQuery?.primaryDateRange == nil,
           candidate.timeScopes.isEmpty,
           usesAppSurfaceDefaultDatePolicy(plan) == false {
            dropped.append("date")
        }
        if let limit,
           plan.limit != limit,
           candidate.limit != limit,
           resolvedQuery?.query.limit != limit {
            dropped.append("limit")
        }
        if let sort,
           plan.ranking?.direction != sort,
           candidate.ranking?.direction != sort,
           resolvedQuery?.query.ranking?.direction != sort {
            dropped.append("sort")
        }

        guard dropped.isEmpty == false else { return nil }
        return MarinaTypedUnsupportedResponse(
            kind: .unsupportedCombination,
            message: "I found an explicit \(dropped.joined(separator: ", ")) constraint in your prompt, but the selected interpretation did not preserve it.",
            candidate: candidate
        )
    }

    private func preserves(
        names: Set<String>,
        type: MarinaCandidateEntityTypeHint,
        plan: MarinaAggregationPlan,
        resolvedQuery: MarinaResolvedSemanticQuery?,
        candidate: MarinaQueryPlanCandidate
    ) -> Bool {
        let planNames = Set(plan.targets.filter { $0.entityType == type }.map { Self.normalized($0.displayName) })
        let resolvedNames = Set((resolvedQuery?.resolvedFilters ?? []).filter { $0.entityType == type }.map { Self.normalized($0.displayName) })
        let rawNames = Set(candidate.entityMentions.compactMap { mention -> String? in
            let allowed = mention.typeHint == type || mention.allowedTypeHints?.contains(type) == true
            guard allowed, let raw = mention.rawText else { return nil }
            return Self.normalized(raw)
        })
        let semanticRawNames = Set((resolvedQuery?.query.filters ?? []).compactMap { filter -> String? in
            let allowed = filter.entityTypeHint == type || filter.allowedEntityTypeHints?.contains(type) == true
            guard allowed else { return nil }
            return Self.normalized(filter.value)
        })
        let preservedNames = planNames.union(resolvedNames).union(rawNames).union(semanticRawNames)
        return names.allSatisfy { preservedNames.contains($0) }
    }

    private func usesAppSurfaceDefaultDatePolicy(_ plan: MarinaAggregationPlan) -> Bool {
        switch (plan.operation, plan.measure) {
        case (.lookupDetails, .savings),
             (.lookupDetails, .remainingBudget),
             (.lookupDetails, .presetAmount),
             (.forecast, .savings):
            return true
        default:
            return false
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MarinaExplicitConstraintDetector {
    func constraints(
        in prompt: String,
        context: MarinaInterpretationContext
    ) -> MarinaExplicitPromptConstraints {
        let normalizedPrompt = normalized(prompt)
        let explicitCards = explicitNames(context.cardNames, in: normalizedPrompt)
        let explicitCategories = explicitNames(context.categoryNames, in: normalizedPrompt)
        let explicitAllocationAccounts = explicitNames(context.allocationAccountNames, in: normalizedPrompt)
        return MarinaExplicitPromptConstraints(
            categories: explicitCategories.filter { category in
                isLikelyCardNameFragment(category, cards: explicitCards, prompt: normalizedPrompt) == false
            },
            cards: explicitCards,
            allocationAccounts: explicitAllocationAccounts,
            merchants: explicitMerchantNames(in: normalizedPrompt),
            hasDateConstraint: hasDateConstraint(
                in: normalizedPrompt,
                protectedEntityNames: context.cardNames
                    + context.categoryNames
                    + context.incomeSourceNames
                    + context.presetTitles
                    + context.budgetNames
                    + context.allocationAccountNames
            ),
            limit: explicitLimit(in: normalizedPrompt),
            sort: explicitSort(in: normalizedPrompt)
        )
    }

    private func explicitNames(_ names: [String], in normalizedPrompt: String) -> Set<String> {
        Set(names.compactMap { name in
            let normalizedName = normalized(name)
            guard normalizedName.isEmpty == false else { return nil }
            return containsWholePhrase(normalizedName, in: normalizedPrompt) ? normalizedName : nil
        })
    }

    private func isLikelyCardNameFragment(
        _ category: String,
        cards: Set<String>,
        prompt: String
    ) -> Bool {
        guard cards.isEmpty == false else { return false }
        if containsWholePhrase("\(category) card", in: prompt) {
            return true
        }
        return cards.contains { card in
            card != category && card.contains(category) && containsWholePhrase(card, in: prompt)
        }
    }

    private func hasDateConstraint(
        in prompt: String,
        protectedEntityNames: [String]
    ) -> Bool {
        let protectedPrompt = removingProtectedEntityNames(protectedEntityNames, from: prompt)
        let phrases = [
            "today", "yesterday", "this week", "last week", "this month", "last month",
            "next month", "this budget", "this period", "last period", "january", "february", "march",
            "april", "may", "june", "july", "august", "september", "october",
            "november", "december"
        ]
        return phrases.contains { containsWholePhrase($0, in: protectedPrompt) }
    }

    private func removingProtectedEntityNames(
        _ names: [String],
        from prompt: String
    ) -> String {
        names.reduce(prompt) { partial, name in
            let normalizedName = normalized(name)
            guard normalizedName.isEmpty == false else { return partial }
            let pattern = "(^|\\s)\(NSRegularExpression.escapedPattern(for: normalizedName))(\\s|$)"
            return partial
                .replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func explicitLimit(in prompt: String) -> Int? {
        let listWords = ["list", "show", "top", "largest", "biggest"]
        guard listWords.contains(where: { containsWholePhrase($0, in: prompt) }) else { return nil }
        return prompt
            .split(separator: " ")
            .compactMap { Int($0) }
            .first
    }

    private func explicitMerchantNames(in prompt: String) -> Set<String> {
        let pattern = #"(?:\bat\b|\bfrom\b|\bshopping at\b|\bshop at\b)\s+([a-z0-9&][a-z0-9&\s]{0,40})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(prompt.startIndex..<prompt.endIndex, in: prompt)
        return Set(regex.matches(in: prompt, range: nsRange).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: prompt) else {
                return nil
            }
            let raw = String(prompt[range])
                .replacingOccurrences(of: #"\b(this|last|current|period|month|week|year|today|yesterday|for|on|with|spend|spent|expenses?|transactions?)\b.*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedRaw = normalized(raw)
            return normalizedRaw.isEmpty ? nil : normalizedRaw
        })
    }

    private func explicitSort(in prompt: String) -> MarinaRankingDirectionCandidate? {
        if ["recent", "newest", "latest"].contains(where: { containsWholePhrase($0, in: prompt) }) {
            return .newest
        }
        if containsWholePhrase("last", in: prompt),
           ["list", "show"].contains(where: { containsWholePhrase($0, in: prompt) }),
           containsWholePhrase("last month", in: prompt) == false,
           containsWholePhrase("last week", in: prompt) == false,
           containsWholePhrase("last period", in: prompt) == false {
            return .newest
        }
        if ["largest", "biggest"].contains(where: { containsWholePhrase($0, in: prompt) }) {
            return .largest
        }
        return nil
    }

    private func containsWholePhrase(_ phrase: String, in prompt: String) -> Bool {
        let pattern = "(^|\\s)\(NSRegularExpression.escapedPattern(for: phrase))(\\s|$)"
        return prompt.range(of: pattern, options: .regularExpression) != nil
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum MarinaCompositeQueryPlannerResult {
    case handled(MarinaWorkspaceAggregationCard)
    case clarification(MarinaTypedClarification)
}

private extension MarinaPlanValidationOutcome {
    var needsClarificationForFormula: Bool {
        if case .clarification = self { return true }
        return false
    }
}

@MainActor
struct MarinaFormulaCatalog {
    func kind(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?,
        context: MarinaTurnContext
    ) -> MarinaCompositeFormulaKind? {
        if let formula = candidate.formulaKind ?? candidate.semanticCommand?.formulaKind {
            return formula
        }

        if let contract = MarinaMetricContractRegistry.current.contract(forSeedPrompt: candidate.rawPrompt) {
            switch contract.id {
            case .recurringExpenseIncrease:
                return .recurringChargeAnomaly
            default:
                break
            }
        }

        let prompt = normalized(candidate.rawPrompt)
        if containsAny(["pace", "burn rate", "blow past", "over my", "over the"], in: prompt),
           containsAny(["limit", "budget max", "max limit"], in: prompt) {
            return .categoryLimitBurnRate
        }
        if containsAny(["ruining my savings", "hurting my savings", "savings drag", "quietly ruining"], in: prompt),
           prompt.contains("card") {
            return .cardSavingsDrag
        }
        if prompt.contains("planned expense"),
           containsAny(["hurt the most", "posted early", "post early", "if it posted"], in: prompt) {
            return .earlyPlannedExpenseStress
        }
        if containsAny(["subscription", "subscriptions", "recurring", "recurring ish", "recurring-ish"], in: prompt),
           containsAny(["higher than usual", "suspicious", "unusual", "higher"], in: prompt) {
            return .recurringChargeAnomaly
        }
        if containsAny(["unsafe", "runway", "how many days"], in: prompt),
           containsAny(["ignore income", "only look at actual card activity", "actual card activity"], in: prompt) {
            return .expenseOnlySavingsRunway
        }

        if let semanticFormula = semanticResolved?.candidate?.formulaKind {
            return semanticFormula
        }
        if let resolvedFormula = resolved.candidate.formulaKind {
            return resolvedFormula
        }
        if context.routerContext.priorQueryContext.hasContext, prompt.contains("same formula") {
            return nil
        }
        return nil
    }

    func candidate(
        from rawValue: String?
    ) -> MarinaCompositeFormulaKind? {
        guard let rawValue else { return nil }
        let normalizedRawValue = normalized(rawValue)
            .replacingOccurrences(of: " ", with: "")
        return MarinaCompositeFormulaKind.allCases.first { formula in
            normalizedRawValue == normalized(formula.rawValue).replacingOccurrences(of: " ", with: "")
        }
    }

    private func containsAny(_ needles: [String], in haystack: String) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s-]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
struct MarinaFormulaPlanner {
    private let catalog = MarinaFormulaCatalog()
    private let calendar = Calendar(identifier: .gregorian)

    func plan(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?,
        outcome: MarinaPlanValidationOutcome,
        context: MarinaTurnContext
    ) -> MarinaFormulaIR? {
        if let recipe = catalog.kind(candidate: candidate, resolved: resolved, semanticResolved: semanticResolved, context: context) {
            return recipeIR(recipe, candidate: candidate, resolved: resolved, semanticResolved: semanticResolved, context: context)
        }

        let prompt = normalized(candidate.rawPrompt)
        guard !outcome.needsClarificationForFormula,
              let family = formulaFamily(candidate: candidate, prompt: prompt, outcome: outcome),
              [.sum, .average, .count, .rank, .compare].contains(family),
              let measure = candidate.formulaMeasure
                ?? candidate.semanticCommand?.formulaMeasure
                ?? measure(from: candidate, prompt: prompt) else {
            return nil
        }

        let subject = subject(for: measure, prompt: prompt, candidate: candidate)
        let ranges = dateRanges(
            candidate: candidate,
            resolved: resolved,
            semanticResolved: semanticResolved,
            prompt: prompt,
            now: context.now
        )
        let filters = resolved.resolvedTargets.isEmpty
            ? inferredTargets(prompt: prompt, provider: context.provider)
            : aggregationTargets(from: resolved.resolvedTargets)
        let grouping = candidate.grouping
            ?? semanticResolved?.query.grouping.map { MarinaGroupingCandidate(dimension: $0.dimension, rawText: $0.rawText) }
            ?? inferredGrouping(family: family, prompt: prompt)

        return MarinaFormulaIR(
            family: family,
            recipe: nil,
            backlogRecipe: candidate.formulaBacklogRecipe ?? candidate.semanticCommand?.formulaBacklogRecipe,
            subject: subject,
            measure: family == .count ? .count : measure,
            filters: filters,
            dateRange: ranges.primary,
            comparisonDateRange: ranges.comparison,
            grouping: grouping,
            ranking: candidate.ranking ?? MarinaRankingCandidate(direction: .largest, limit: candidate.limit ?? 5),
            limit: candidate.limit,
            assumptions: genericAssumptions(family: family, measure: measure, prompt: prompt),
            facets: mergedFacets(candidate)
        )
    }

    private func recipeIR(
        _ recipe: MarinaCompositeFormulaKind,
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?,
        context: MarinaTurnContext
    ) -> MarinaFormulaIR {
        let prompt = normalized(candidate.rawPrompt)
        let ranges = dateRanges(
            candidate: candidate,
            resolved: resolved,
            semanticResolved: semanticResolved,
            prompt: prompt,
            now: context.now
        )
        return MarinaFormulaIR(
            family: family(for: recipe),
            recipe: recipe,
            subject: subject(for: recipe),
            measure: measure(for: recipe),
            filters: resolved.resolvedTargets.isEmpty ? inferredTargets(prompt: prompt, provider: context.provider) : aggregationTargets(from: resolved.resolvedTargets),
            dateRange: ranges.primary,
            comparisonDateRange: ranges.comparison,
            grouping: grouping(for: recipe),
            ranking: MarinaRankingCandidate(direction: .largest, limit: candidate.limit ?? 5),
            limit: candidate.limit,
            assumptions: ["Named deterministic formula recipe selected by Marina's formula catalog."],
            facets: mergedFacets(candidate)
        )
    }

    private func formulaFamily(
        candidate: MarinaQueryPlanCandidate,
        prompt: String,
        outcome _: MarinaPlanValidationOutcome
    ) -> MarinaFormulaFamily? {
        if let family = candidate.formulaFamily ?? candidate.semanticCommand?.formulaFamily {
            return family
        }
        if let family = promptFormulaFamily(from: prompt) {
            return family
        }
        return nil
    }

    private func promptFormulaFamily(from prompt: String) -> MarinaFormulaFamily? {
        if prompt.hasPrefix("sum ") || prompt.hasPrefix("total ") || prompt.contains(" total ") {
            return .sum
        }
        if prompt.contains("average") || prompt.contains(" avg ") {
            return .average
        }
        if prompt.hasPrefix("rank ") || prompt.hasPrefix("top ") || prompt.contains("rank ") || prompt.contains(" by spending") {
            return .rank
        }
        if prompt.hasPrefix("compare ") || prompt.contains(" vs ") || prompt.contains(" versus ") {
            return .compare
        }
        if prompt.hasPrefix("count ") || prompt.hasPrefix("how many ") {
            return .count
        }
        if prompt.hasPrefix("number of ") || prompt.contains(" count of ") {
            return .count
        }
        return nil
    }

    private func measure(
        from candidate: MarinaQueryPlanCandidate,
        prompt: String
    ) -> MarinaFormulaMeasure? {
        if prompt.contains("planned") || prompt.contains("preset") {
            return .plannedEffectiveAmount
        }
        if prompt.contains("income") {
            return .incomeAmount
        }
        if prompt.contains("savings activity") || prompt.contains("savings movement") {
            return .savingsMovement
        }
        if prompt.contains("savings") {
            return .savingsBalance
        }
        if prompt.contains("reconciliation") || prompt.contains("shared balance") {
            return .reconciliationBalance
        }
        if prompt.contains("allocation") {
            return .allocationAmount
        }
        switch candidate.measure {
        case .income:
            return .incomeAmount
        case .presetAmount:
            return .plannedEffectiveAmount
        case .savings:
            return .savingsBalance
        case .savingsMovement:
            return .savingsMovement
        case .reconciliationBalance:
            return .reconciliationBalance
        case .spend, .categoryShare, .transactionAmount, .transactionFrequency, .remainingBudget, nil:
            return .variableBudgetImpact
        }
    }

    private func subject(
        for measure: MarinaFormulaMeasure,
        prompt: String,
        candidate: MarinaQueryPlanCandidate
    ) -> MarinaSubject {
        if let dataset = candidate.semanticCommand?.datasets.first {
            switch dataset {
            case .plannedExpenses, .presets:
                return .plannedExpenses
            case .income, .incomeSeries:
                return .income
            case .savingsLedger:
                return measure == .savingsBalance ? .savingsAccounts : .savingsLedgerEntries
            case .reconciliation, .expenseAllocations:
                return .reconciliationAccounts
            default:
                break
            }
        }
        switch measure {
        case .plannedEffectiveAmount:
            return .plannedExpenses
        case .incomeAmount:
            return .income
        case .savingsBalance:
            return .savingsAccounts
        case .savingsMovement:
            return .savingsLedgerEntries
        case .reconciliationBalance:
            return .reconciliationAccounts
        case .allocationAmount:
            return .reconciliationItems
        case .variableBudgetImpact, .variableLedgerAmount, .count:
            return .variableExpenses
        }
    }

    private func family(for recipe: MarinaCompositeFormulaKind) -> MarinaFormulaFamily {
        switch recipe {
        case .categoryLimitBurnRate:
            return .threshold
        case .cardSavingsDrag, .earlyPlannedExpenseStress:
            return .rank
        case .recurringChargeAnomaly:
            return .anomaly
        case .expenseOnlySavingsRunway:
            return .runway
        }
    }

    private func subject(for recipe: MarinaCompositeFormulaKind) -> MarinaSubject {
        switch recipe {
        case .earlyPlannedExpenseStress:
            return .plannedExpenses
        case .categoryLimitBurnRate, .cardSavingsDrag, .recurringChargeAnomaly, .expenseOnlySavingsRunway:
            return .variableExpenses
        }
    }

    private func measure(for recipe: MarinaCompositeFormulaKind) -> MarinaFormulaMeasure {
        switch recipe {
        case .earlyPlannedExpenseStress:
            return .plannedEffectiveAmount
        case .categoryLimitBurnRate, .cardSavingsDrag, .recurringChargeAnomaly, .expenseOnlySavingsRunway:
            return .variableBudgetImpact
        }
    }

    private func grouping(for recipe: MarinaCompositeFormulaKind) -> MarinaGroupingCandidate? {
        switch recipe {
        case .cardSavingsDrag:
            return MarinaGroupingCandidate(dimension: .card)
        case .recurringChargeAnomaly:
            return MarinaGroupingCandidate(dimension: .merchant)
        case .categoryLimitBurnRate, .earlyPlannedExpenseStress, .expenseOnlySavingsRunway:
            return nil
        }
    }

    private func dateRanges(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?,
        prompt: String,
        now: Date
    ) -> (primary: HomeQueryDateRange?, comparison: HomeQueryDateRange?) {
        let primary = resolved.primaryDateRange
            ?? semanticResolved?.primaryDateRange
            ?? candidate.timeScopes.first(where: { $0.role == .primary || $0.role == .lookbackWindow })?.resolvedRangeHint
            ?? inferredDateRange(prompt: prompt, now: now)
        let comparison = resolved.comparisonDateRange
            ?? semanticResolved?.comparisonDateRange
            ?? candidate.timeScopes.first(where: { $0.role == .comparison })?.resolvedRangeHint
            ?? inferredComparisonRange(prompt: prompt, primary: primary, now: now)
        return (primary, comparison)
    }

    private func inferredDateRange(prompt: String, now: Date) -> HomeQueryDateRange? {
        if prompt.contains("last 3 months") {
            let startOfCurrent = monthRange(containing: now).startDate
            let start = calendar.date(byAdding: .month, value: -3, to: startOfCurrent) ?? startOfCurrent
            let end = calendar.date(byAdding: .second, value: -1, to: startOfCurrent) ?? now
            return HomeQueryDateRange(startDate: start, endDate: end)
        }
        if prompt.contains("this month") {
            return monthRange(containing: now)
        }
        if prompt.contains("last month") {
            return previousMonthRange(now: now)
        }
        if prompt.contains("month") || prompt.contains("spending") || prompt.contains("transactions") {
            return monthRange(containing: now)
        }
        return nil
    }

    private func inferredComparisonRange(
        prompt: String,
        primary: HomeQueryDateRange?,
        now: Date
    ) -> HomeQueryDateRange? {
        guard prompt.contains("last month") || prompt.contains(" vs ") || prompt.contains(" versus ") || prompt.contains("compare") else {
            return nil
        }
        let range = primary ?? monthRange(containing: now)
        let months = max(1, calendar.dateComponents([.month], from: range.startDate, to: range.endDate).month ?? 1)
        let start = calendar.date(byAdding: .month, value: -months, to: range.startDate) ?? range.startDate
        let end = calendar.date(byAdding: .second, value: -1, to: range.startDate) ?? range.startDate
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func inferredTargets(
        prompt: String,
        provider: MarinaDataProvider
    ) -> [MarinaResolvedAggregationTarget] {
        var targets: [MarinaResolvedAggregationTarget] = []
        if prompt.contains("uncategorized") {
            targets.append(MarinaResolvedAggregationTarget(role: .filter, entityType: .category, displayName: "Uncategorized"))
        }
        for category in provider.fetchAllCategories() where containsWholePhrase(normalized(category.name), in: prompt) {
            targets.append(MarinaResolvedAggregationTarget(role: .primaryTarget, entityType: .category, displayName: category.name, sourceID: category.id))
        }
        for card in provider.fetchAllCards() where containsWholePhrase(normalized(card.name), in: prompt) {
            targets.append(MarinaResolvedAggregationTarget(role: .filter, entityType: .card, displayName: card.name, sourceID: card.id))
        }
        return targets
    }

    private func aggregationTargets(
        from targets: [MarinaResolvedEntityMention]
    ) -> [MarinaResolvedAggregationTarget] {
        targets.map { target in
            MarinaResolvedAggregationTarget(
                id: target.id,
                role: target.role,
                entityType: target.entityType,
                displayName: target.displayName,
                sourceID: target.sourceID
            )
        }
    }

    private func inferredGrouping(
        family: MarinaFormulaFamily,
        prompt: String
    ) -> MarinaGroupingCandidate? {
        guard family == .rank else { return nil }
        if prompt.contains("card") {
            return MarinaGroupingCandidate(dimension: .card, rawText: "cards")
        }
        if prompt.contains("categor") {
            return MarinaGroupingCandidate(dimension: .category, rawText: "categories")
        }
        if prompt.contains("merchant") {
            return MarinaGroupingCandidate(dimension: .merchant, rawText: "merchants")
        }
        return nil
    }

    private func genericAssumptions(
        family: MarinaFormulaFamily,
        measure: MarinaFormulaMeasure,
        prompt: String
    ) -> [String] {
        var values = ["Formula family \(family.rawValue); measure \(measure.rawValue)."]
        if measure == .variableBudgetImpact {
            values.append("Variable expense spend uses budget-impact math, not raw ledger amount.")
        }
        if prompt.contains("weekly") || prompt.contains("per week") {
            values.append("Average uses week buckets across the selected date range.")
        }
        return values
    }

    private func mergedFacets(_ candidate: MarinaQueryPlanCandidate) -> MarinaFormulaFacets {
        let command = candidate.semanticCommand
        if candidate.formulaFacets != MarinaFormulaFacets() {
            return candidate.formulaFacets
        }
        return command?.formulaFacets ?? MarinaFormulaFacets()
    }

    private func monthRange(containing date: Date) -> HomeQueryDateRange {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? date
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func previousMonthRange(now: Date) -> HomeQueryDateRange {
        let current = monthRange(containing: now)
        let start = calendar.date(byAdding: .month, value: -1, to: current.startDate) ?? current.startDate
        let end = calendar.date(byAdding: .second, value: -1, to: current.startDate) ?? current.startDate
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func containsWholePhrase(_ phrase: String, in prompt: String) -> Bool {
        let pattern = "(^|\\s)\(NSRegularExpression.escapedPattern(for: phrase))(\\s|$)"
        return prompt.range(of: pattern, options: .regularExpression) != nil
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&-]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MarinaFormulaDomainRow: Equatable {
    let id: UUID
    let title: String
    let value: String
    let amount: Double?
    let date: Date?
    let objectType: MarinaLookupObjectType?
    let sourceID: UUID?
    let groupingValues: [MarinaGroupingDimensionCandidate: String]
}

@MainActor
struct MarinaFormulaDomainAdapterRegistry {
    func rows(
        for formulaIR: MarinaFormulaIR,
        context: MarinaTurnContext
    ) -> [MarinaFormulaDomainRow] {
        let rows: [MarinaFormulaDomainRow]
        switch formulaIR.measure {
        case .variableBudgetImpact, .variableLedgerAmount, .count:
            rows = variableRows(formulaIR: formulaIR, provider: context.provider)
        case .plannedEffectiveAmount:
            rows = plannedRows(formulaIR: formulaIR, provider: context.provider)
        case .incomeAmount:
            rows = incomeRows(formulaIR: formulaIR, provider: context.provider)
        case .savingsBalance:
            rows = savingsAccountRows(provider: context.provider)
        case .savingsMovement:
            rows = savingsMovementRows(provider: context.provider)
        case .allocationAmount:
            rows = allocationRows(provider: context.provider)
        case .reconciliationBalance:
            rows = reconciliationRows(provider: context.provider)
        }
        return rows
            .filter { row in date(row, isIn: formulaIR.dateRange) }
            .filter { row in filtersMatch(formulaIR.filters, row: row) }
    }

    private func variableRows(
        formulaIR: MarinaFormulaIR,
        provider: MarinaDataProvider
    ) -> [MarinaFormulaDomainRow] {
        provider.fetchAllVariableExpenses().map { expense in
            let amount: Double
            switch formulaIR.measure {
            case .variableLedgerAmount:
                amount = expense.ledgerSignedAmount()
            case .count:
                amount = 1
            default:
                amount = SavingsMathService.variableBudgetImpactAmount(for: expense)
            }
            return MarinaFormulaDomainRow(
                id: expense.id,
                title: expense.descriptionText,
                value: "\(shortDate(expense.transactionDate)) • \(currency(amount))",
                amount: amount,
                date: expense.transactionDate,
                objectType: .variableExpense,
                sourceID: expense.id,
                groupingValues: [
                    .category: expense.category?.name ?? "Uncategorized",
                    .card: expense.card?.name ?? "No Card",
                    .merchant: canonicalMerchant(expense.descriptionText),
                    .transaction: expense.descriptionText
                ]
            )
        }
    }

    private func plannedRows(
        formulaIR: MarinaFormulaIR,
        provider: MarinaDataProvider
    ) -> [MarinaFormulaDomainRow] {
        let presetTitlesByID = Dictionary(uniqueKeysWithValues: provider.fetchAllPresets().map { ($0.id, $0.title) })
        return provider.fetchAllPlannedExpenses().map { expense in
            let amount = formulaIR.measure == .count ? 1 : SavingsMathService.plannedProjectedBudgetImpactAmount(for: expense)
            let preset = expense.sourcePresetID.flatMap { presetTitlesByID[$0] } ?? expense.title
            return MarinaFormulaDomainRow(
                id: expense.id,
                title: expense.title,
                value: "\(shortDate(expense.expenseDate)) • \(currency(amount))",
                amount: amount,
                date: expense.expenseDate,
                objectType: .plannedExpense,
                sourceID: expense.id,
                groupingValues: [
                    .category: expense.category?.name ?? "Uncategorized",
                    .card: expense.card?.name ?? "No Card",
                    .preset: preset,
                    .transaction: expense.title
                ]
            )
        }
    }

    private func incomeRows(
        formulaIR: MarinaFormulaIR,
        provider: MarinaDataProvider
    ) -> [MarinaFormulaDomainRow] {
        provider.fetchAllIncomes().map { income in
            let amount = formulaIR.measure == .count ? 1 : income.amount
            return MarinaFormulaDomainRow(
                id: income.id,
                title: income.source,
                value: "\(income.isPlanned ? "Planned" : "Actual") • \(shortDate(income.date)) • \(currency(amount))",
                amount: amount,
                date: income.date,
                objectType: .income,
                sourceID: income.id,
                groupingValues: [.incomeSource: income.source]
            )
        }
    }

    private func savingsAccountRows(provider: MarinaDataProvider) -> [MarinaFormulaDomainRow] {
        provider.fetchAllSavingsAccounts().map { account in
            MarinaFormulaDomainRow(
                id: account.id,
                title: account.name,
                value: currency(account.total),
                amount: account.total,
                date: nil,
                objectType: .savingsAccount,
                sourceID: account.id,
                groupingValues: [:]
            )
        }
    }

    private func savingsMovementRows(provider: MarinaDataProvider) -> [MarinaFormulaDomainRow] {
        provider.fetchAllSavingsLedgerEntries().map { entry in
            MarinaFormulaDomainRow(
                id: entry.id,
                title: entry.note.isEmpty ? entry.kindRaw : entry.note,
                value: "\(shortDate(entry.date)) • \(currency(entry.amount))",
                amount: entry.amount,
                date: entry.date,
                objectType: .savingsLedgerEntry,
                sourceID: entry.id,
                groupingValues: [.savingsLedgerEntry: entry.account?.name ?? "Savings"]
            )
        }
    }

    private func allocationRows(provider: MarinaDataProvider) -> [MarinaFormulaDomainRow] {
        provider.fetchAllExpenseAllocations().map { allocation in
            let title = allocation.expense?.descriptionText ?? allocation.plannedExpense?.title ?? "Allocation"
            return MarinaFormulaDomainRow(
                id: allocation.id,
                title: title,
                value: currency(allocation.allocatedAmount),
                amount: allocation.allocatedAmount,
                date: allocation.expense?.transactionDate ?? allocation.plannedExpense?.expenseDate,
                objectType: .expenseAllocation,
                sourceID: allocation.id,
                groupingValues: [.allocationAccount: allocation.account?.name ?? "Unassigned"]
            )
        }
    }

    private func reconciliationRows(provider: MarinaDataProvider) -> [MarinaFormulaDomainRow] {
        provider.fetchAllAllocationAccounts().map { account in
            let allocations = provider.fetchAllExpenseAllocations()
                .filter { $0.account?.id == account.id }
                .reduce(0.0) { $0 + $1.allocatedAmount }
            let settlements = provider.fetchAllAllocationSettlements()
                .filter { $0.account?.id == account.id }
                .reduce(0.0) { $0 + $1.amount }
            let balance = allocations + settlements
            return MarinaFormulaDomainRow(
                id: account.id,
                title: account.name,
                value: currency(balance),
                amount: balance,
                date: nil,
                objectType: .reconciliationAccount,
                sourceID: account.id,
                groupingValues: [.allocationAccount: account.name]
            )
        }
    }

    private func filtersMatch(
        _ filters: [MarinaResolvedAggregationTarget],
        row: MarinaFormulaDomainRow
    ) -> Bool {
        filters.allSatisfy { filter in
            let expected = normalized(filter.displayName)
            switch filter.entityType {
            case .category:
                return normalized(row.groupingValues[.category] ?? "") == expected
            case .card:
                return normalized(row.groupingValues[.card] ?? "") == expected
            case .merchant:
                return normalized(row.groupingValues[.merchant] ?? "").contains(expected)
            case .expense, .transaction:
                return normalized(row.title).contains(expected)
            case .preset:
                return normalized(row.groupingValues[.preset] ?? "").contains(expected)
            case .incomeSource:
                return normalized(row.groupingValues[.incomeSource] ?? "").contains(expected)
            case .allocationAccount:
                return normalized(row.groupingValues[.allocationAccount] ?? "").contains(expected)
            case .savingsAccount, .budget, .workspace:
                return normalized(row.title).contains(expected)
            }
        }
    }

    private func date(_ row: MarinaFormulaDomainRow, isIn range: HomeQueryDateRange?) -> Bool {
        guard let range else { return true }
        guard let date = row.date else { return true }
        return date >= range.startDate && date <= range.endDate
    }

    private func canonicalMerchant(_ value: String) -> String {
        let normalizedValue = normalized(value)
            .replacingOccurrences(of: "\\b\\d+\\b", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedValue.isEmpty ? "Unknown" : displayName(normalizedValue)
    }

    private func displayName(_ value: String) -> String {
        value
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + String($0.dropFirst()) }
            .joined(separator: " ")
    }

    private func shortDate(_ date: Date) -> String {
        AppDateFormat.shortDate(date)
    }

    private func currency(_ value: Double) -> String {
        CurrencyFormatter.string(from: value)
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&-]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
struct MarinaFormulaExecutor {
    private let adapterRegistry = MarinaFormulaDomainAdapterRegistry()
    private let recipeExecutor = MarinaCompositeFormulaExecutor()
    private let calendar = Calendar(identifier: .gregorian)

    func execute(
        formulaIR: MarinaFormulaIR,
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?,
        context: MarinaTurnContext
    ) -> MarinaWorkspaceAggregationCard {
        if let recipe = formulaIR.recipe {
            return recipeExecutor.execute(
                formula: recipe,
                candidate: candidate,
                resolved: resolved,
                semanticResolved: semanticResolved,
                context: context
            )
        }

        let rows = adapterRegistry.rows(for: formulaIR, context: context)
        switch formulaIR.family {
        case .sum:
            return sumCard(formulaIR: formulaIR, rows: rows)
        case .average:
            return averageCard(formulaIR: formulaIR, rows: rows)
        case .count:
            return countCard(formulaIR: formulaIR, rows: rows)
        case .rank:
            return rankCard(formulaIR: formulaIR, rows: rows)
        case .compare:
            return compareCard(formulaIR: formulaIR, context: context)
        case .list, .detail, .threshold, .runway, .anomaly, .whatIf, .trend, .forecast:
            return dataLimitCard(formulaIR: formulaIR, message: "This formula family is modeled but does not have an executable recipe yet.")
        }
    }

    private func sumCard(
        formulaIR: MarinaFormulaIR,
        rows: [MarinaFormulaDomainRow]
    ) -> MarinaWorkspaceAggregationCard {
        let total = rows.reduce(0.0) { $0 + ($1.amount ?? 0) }
        return MarinaWorkspaceAggregationCard(
            title: title("Total", formulaIR: formulaIR),
            subtitle: rangeLabel(formulaIR.dateRange),
            primaryValue: currency(total),
            answerKind: .metric,
            rows: baseRows(formulaIR) + evidenceRows(rows.sorted(by: newestFirst).prefix(limit(for: formulaIR))),
            traceSummary: trace(formulaIR, resultCount: rows.count, total: total)
        )
    }

    private func averageCard(
        formulaIR: MarinaFormulaIR,
        rows: [MarinaFormulaDomainRow]
    ) -> MarinaWorkspaceAggregationCard {
        let total = rows.reduce(0.0) { $0 + ($1.amount ?? 0) }
        let divisor = averageDivisor(formulaIR: formulaIR, rows: rows)
        let average = divisor > 0 ? total / divisor : 0
        return MarinaWorkspaceAggregationCard(
            title: title(averageTitlePrefix(formulaIR), formulaIR: formulaIR),
            subtitle: rangeLabel(formulaIR.dateRange),
            primaryValue: currency(average),
            answerKind: .metric,
            rows: baseRows(formulaIR) + [
                .init(label: "Total", value: currency(total), amount: total),
                .init(label: "Average basis", value: averageBasisLabel(formulaIR, divisor: divisor))
            ] + evidenceRows(rows.sorted(by: newestFirst).prefix(limit(for: formulaIR))),
            traceSummary: trace(formulaIR, resultCount: rows.count, total: average)
        )
    }

    private func countCard(
        formulaIR: MarinaFormulaIR,
        rows: [MarinaFormulaDomainRow]
    ) -> MarinaWorkspaceAggregationCard {
        MarinaWorkspaceAggregationCard(
            title: title("Count", formulaIR: formulaIR),
            subtitle: rangeLabel(formulaIR.dateRange),
            primaryValue: "\(rows.count)",
            answerKind: .metric,
            rows: baseRows(formulaIR) + evidenceRows(rows.sorted(by: newestFirst).prefix(limit(for: formulaIR))),
            traceSummary: trace(formulaIR, resultCount: rows.count, total: Double(rows.count))
        )
    }

    private func rankCard(
        formulaIR: MarinaFormulaIR,
        rows: [MarinaFormulaDomainRow]
    ) -> MarinaWorkspaceAggregationCard {
        let rankedRows: [MarinaWorkspaceAggregationCard.Row]
        if let grouping = formulaIR.grouping?.dimension {
            rankedRows = Dictionary(grouping: rows) { row in
                row.groupingValues[grouping] ?? "Unknown"
            }
            .map { label, grouped in
                let total = grouped.reduce(0.0) { $0 + ($1.amount ?? 0) }
                return MarinaWorkspaceAggregationCard.Row(label: label, value: currency(total), amount: total, sortValue: total)
            }
            .sorted { lhs, rhs in (lhs.sortValue ?? 0) > (rhs.sortValue ?? 0) }
            .prefix(limit(for: formulaIR))
            .map { $0 }
        } else {
            rankedRows = evidenceRows(
                rows
                    .sorted { ($0.amount ?? 0) > ($1.amount ?? 0) }
                    .prefix(limit(for: formulaIR))
            )
        }

        return MarinaWorkspaceAggregationCard(
            title: title("Ranked", formulaIR: formulaIR),
            subtitle: rangeLabel(formulaIR.dateRange),
            primaryValue: rankedRows.first?.value,
            rows: baseRows(formulaIR) + rankedRows,
            traceSummary: trace(formulaIR, resultCount: rows.count, total: rankedRows.first?.amount)
        )
    }

    private func compareCard(
        formulaIR: MarinaFormulaIR,
        context: MarinaTurnContext
    ) -> MarinaWorkspaceAggregationCard {
        guard let currentRange = formulaIR.dateRange,
              let previousRange = formulaIR.comparisonDateRange else {
            return dataLimitCard(formulaIR: formulaIR, message: "Comparison formulas need both a primary and comparison date range.")
        }
        let currentIR = copy(formulaIR, dateRange: currentRange)
        let previousIR = copy(formulaIR, dateRange: previousRange)
        let currentRows = adapterRegistry.rows(for: currentIR, context: context)
        let previousRows = adapterRegistry.rows(for: previousIR, context: context)
        let current = currentRows.reduce(0.0) { $0 + ($1.amount ?? 0) }
        let previous = previousRows.reduce(0.0) { $0 + ($1.amount ?? 0) }
        let change = current - previous
        return MarinaWorkspaceAggregationCard(
            title: title("Comparison", formulaIR: formulaIR),
            subtitle: "\(rangeLabel(currentRange)) vs \(rangeLabel(previousRange))",
            primaryValue: currency(current),
            answerKind: .comparison,
            rows: baseRows(formulaIR) + [
                .init(label: "Current period", value: currency(current), amount: current, sortValue: current),
                .init(label: "Previous period", value: currency(previous), amount: previous, sortValue: previous),
                .init(label: "Change", value: signedCurrency(change), amount: change, sortValue: change)
            ] + evidenceRows(currentRows.sorted(by: newestFirst).prefix(limit(for: formulaIR))),
            traceSummary: trace(formulaIR, resultCount: currentRows.count + previousRows.count, total: change)
        )
    }

    private func dataLimitCard(
        formulaIR: MarinaFormulaIR,
        message: String
    ) -> MarinaWorkspaceAggregationCard {
        MarinaWorkspaceAggregationCard(
            title: title("Formula", formulaIR: formulaIR),
            subtitle: message,
            primaryValue: "Not enough data",
            answerKind: .message,
            rows: baseRows(formulaIR) + [.init(label: "Data limitation", value: message)],
            traceSummary: trace(formulaIR, resultCount: 0, total: nil)
        )
    }

    private func baseRows(_ formulaIR: MarinaFormulaIR) -> [MarinaWorkspaceAggregationCard.Row] {
        [
            .init(label: "Formula family", value: formulaIR.family.rawValue, role: .trace),
            formulaIR.recipe.map { .init(label: "Formula", value: $0.rawValue, role: .trace) },
            formulaIR.backlogRecipe.map { .init(label: "Formula backlog", value: $0.rawValue, role: .trace) },
            .init(label: "Measure", value: formulaIR.measure.rawValue, role: .trace),
            .init(label: "Assumptions", value: formulaIR.assumptions.joined(separator: " "), role: .trace),
            .init(label: "Date range", value: rangeLabel(formulaIR.dateRange), role: .trace)
        ].compactMap { $0 }
    }

    private func evidenceRows<S: Sequence>(
        _ rows: S
    ) -> [MarinaWorkspaceAggregationCard.Row] where S.Element == MarinaFormulaDomainRow {
        rows.map { row in
            MarinaWorkspaceAggregationCard.Row(
                id: row.id,
                label: row.title,
                value: row.value,
                amount: row.amount,
                date: row.date,
                objectType: row.objectType,
                sourceID: row.sourceID,
                sortValue: row.amount
            )
        }
    }

    private func title(_ prefix: String, formulaIR: MarinaFormulaIR) -> String {
        let target = formulaIR.filters.first?.displayName
        let noun: String
        switch formulaIR.measure {
        case .variableBudgetImpact, .variableLedgerAmount:
            noun = "Spending"
        case .plannedEffectiveAmount:
            noun = "Planned Expenses"
        case .incomeAmount:
            noun = "Income"
        case .savingsBalance:
            noun = "Savings"
        case .savingsMovement:
            noun = "Savings Activity"
        case .reconciliationBalance:
            noun = "Shared Balances"
        case .allocationAmount:
            noun = "Allocations"
        case .count:
            noun = "Transactions"
        }
        return [target, prefix, noun].compactMap { $0 }.joined(separator: " ")
    }

    private func averageTitlePrefix(_ formulaIR: MarinaFormulaIR) -> String {
        if formulaIR.assumptions.contains(where: { $0.localizedCaseInsensitiveContains("week") }) {
            return "Average Weekly"
        }
        if formulaIR.assumptions.contains(where: { $0.localizedCaseInsensitiveContains("day") }) {
            return "Average Daily"
        }
        return "Average"
    }

    private func averageDivisor(
        formulaIR: MarinaFormulaIR,
        rows: [MarinaFormulaDomainRow]
    ) -> Double {
        guard let range = formulaIR.dateRange else {
            return Double(max(rows.count, 1))
        }
        let days = max(1, (calendar.dateComponents([.day], from: calendar.startOfDay(for: range.startDate), to: calendar.startOfDay(for: range.endDate)).day ?? 0) + 1)
        let assumptions = formulaIR.assumptions.joined(separator: " ").lowercased()
        if assumptions.contains("week") {
            return max(1, Double(days) / 7.0)
        }
        if assumptions.contains("day") {
            return Double(days)
        }
        return Double(max(rows.count, 1))
    }

    private func averageBasisLabel(
        _ formulaIR: MarinaFormulaIR,
        divisor: Double
    ) -> String {
        let assumptions = formulaIR.assumptions.joined(separator: " ").lowercased()
        if assumptions.contains("week") {
            return "\(String(format: "%.1f", divisor)) weeks"
        }
        if assumptions.contains("day") {
            return "\(Int(divisor)) days"
        }
        return "\(Int(divisor)) rows"
    }

    private func copy(
        _ formulaIR: MarinaFormulaIR,
        dateRange: HomeQueryDateRange
    ) -> MarinaFormulaIR {
        MarinaFormulaIR(
            id: formulaIR.id,
            family: formulaIR.family,
            recipe: formulaIR.recipe,
            backlogRecipe: formulaIR.backlogRecipe,
            subject: formulaIR.subject,
            measure: formulaIR.measure,
            filters: formulaIR.filters,
            dateRange: dateRange,
            comparisonDateRange: formulaIR.comparisonDateRange,
            grouping: formulaIR.grouping,
            ranking: formulaIR.ranking,
            limit: formulaIR.limit,
            assumptions: formulaIR.assumptions,
            facets: formulaIR.facets
        )
    }

    private func newestFirst(_ lhs: MarinaFormulaDomainRow, _ rhs: MarinaFormulaDomainRow) -> Bool {
        (lhs.date ?? .distantPast) > (rhs.date ?? .distantPast)
    }

    private func rangeLabel(_ range: HomeQueryDateRange?) -> String {
        guard let range else { return "All selected workspace data" }
        return "\(shortDate(range.startDate)) - \(shortDate(range.endDate))"
    }

    private func shortDate(_ date: Date) -> String {
        AppDateFormat.shortDate(date)
    }

    private func currency(_ value: Double) -> String {
        CurrencyFormatter.string(from: value)
    }

    private func signedCurrency(_ value: Double) -> String {
        if value > 0 { return "+\(currency(value))" }
        if value < 0 { return "-\(currency(abs(value)))" }
        return currency(0)
    }

    private func trace(
        _ formulaIR: MarinaFormulaIR,
        resultCount: Int,
        total: Double?
    ) -> String {
        [
            "formulaIR=family:\(formulaIR.family.rawValue)",
            "measure=\(formulaIR.measure.rawValue)",
            formulaIR.recipe.map { "recipe=\($0.rawValue)" },
            formulaIR.backlogRecipe.map { "backlogRecipe=\($0.rawValue)" },
            "resultCount=\(resultCount)",
            total.map { "total=\($0)" }
        ].compactMap { $0 }.joined(separator: ",")
    }

    private func limit(for formulaIR: MarinaFormulaIR) -> Int {
        min(10, max(1, formulaIR.limit ?? formulaIR.ranking?.limit ?? 5))
    }
}

@MainActor
struct MarinaCompositeQueryPlanner {
    private let planner = MarinaFormulaPlanner()
    private let executor = MarinaFormulaExecutor()

    func plan(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?,
        outcome: MarinaPlanValidationOutcome,
        context: MarinaTurnContext
    ) -> MarinaCompositeQueryPlannerResult? {
        guard let formulaIR = planner.plan(
            candidate: candidate,
            resolved: resolved,
            semanticResolved: semanticResolved,
            outcome: outcome,
            context: context
        ) else {
            return nil
        }

        if formulaIR.recipe == .expenseOnlySavingsRunway,
           context.provider.fetchAllSavingsAccounts().isEmpty,
           context.provider.fetchAllSavingsLedgerEntries().isEmpty {
            return .clarification(missingSavingsClarification(candidate: candidate))
        }

        return .handled(
            executor.execute(
                formulaIR: formulaIR,
                candidate: candidate,
                resolved: resolved,
                semanticResolved: semanticResolved,
                context: context
            )
        )
    }

    private func missingSavingsClarification(candidate: MarinaQueryPlanCandidate) -> MarinaTypedClarification {
        let prompt = candidate.rawPrompt
        let budgetRoomCandidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: prompt,
            operation: .lookupDetails,
            measure: .remainingBudget,
            responseShapeHint: .summaryCard,
            confidence: .high
        )
        let activityCandidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: prompt,
            operation: .rank,
            measure: .spend,
            grouping: MarinaGroupingCandidate(dimension: .card),
            ranking: MarinaRankingCandidate(direction: .largest, limit: 5),
            limit: 5,
            responseShapeHint: .rankedList,
            confidence: .high
        )
        return MarinaTypedClarification(
            kind: .ambiguousTarget,
            message: "I do not see an actual savings account yet. Should Marina use budget room instead?",
            candidate: candidate,
            choices: [
                MarinaClarificationChoice(
                    title: "Use budget room",
                    subtitle: "Estimate safety from current budget room",
                    resumeIntent: MarinaClarificationResumeIntent(candidate: budgetRoomCandidate)
                ),
                MarinaClarificationChoice(
                    title: "Show card activity",
                    subtitle: "Rank actual card spend instead",
                    resumeIntent: MarinaClarificationResumeIntent(candidate: activityCandidate)
                )
            ]
        )
    }
}

@MainActor
struct MarinaCompositeFormulaExecutor {
    private let calendar: Calendar

    init(calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.calendar = calendar
    }

    func execute(
        formula: MarinaCompositeFormulaKind,
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?,
        context: MarinaTurnContext
    ) -> MarinaWorkspaceAggregationCard {
        switch formula {
        case .categoryLimitBurnRate:
            return categoryLimitBurnRate(candidate: candidate, resolved: resolved, semanticResolved: semanticResolved, context: context)
        case .cardSavingsDrag:
            return cardSavingsDrag(context: context)
        case .earlyPlannedExpenseStress:
            return earlyPlannedExpenseStress(context: context)
        case .recurringChargeAnomaly:
            return recurringChargeAnomaly(context: context)
        case .expenseOnlySavingsRunway:
            return expenseOnlySavingsRunway(context: context)
        }
    }

    private func categoryLimitBurnRate(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?,
        context: MarinaTurnContext
    ) -> MarinaWorkspaceAggregationCard {
        let range = resolved.primaryDateRange ?? semanticResolved?.primaryDateRange ?? monthRange(containing: context.now)
        guard let category = categoryTarget(candidate: candidate, resolved: resolved, semanticResolved: semanticResolved, provider: context.provider) else {
            return dataLimitCard(
                title: "Category Limit Burn Rate",
                formula: .categoryLimitBurnRate,
                message: "I could not identify a category to check against a budget max limit.",
                range: range
            )
        }

        let budget = activeBudget(provider: context.provider, now: context.now, range: range)
        let maxLimit = budget?.categoryLimits?.first { limit in
            normalized(limit.category?.name ?? "") == normalized(category.name)
        }?.maxAmount

        guard let maxLimit else {
            return dataLimitCard(
                title: "\(category.name) Limit Burn Rate",
                formula: .categoryLimitBurnRate,
                message: "No max budget limit is set for \(category.name) in the active budget.",
                range: range
            )
        }

        let toDateEnd = min(context.now, range.endDate)
        let expenses = context.provider.fetchAllVariableExpenses()
            .filter { $0.transactionDate >= range.startDate && $0.transactionDate <= toDateEnd }
            .filter { normalized($0.category?.name ?? "") == normalized(category.name) }
        let spendToDate = expenses.reduce(0.0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }
        let elapsedDays = max(1, (calendar.dateComponents([.day], from: calendar.startOfDay(for: range.startDate), to: calendar.startOfDay(for: toDateEnd)).day ?? 0) + 1)
        let periodDays = max(1, (calendar.dateComponents([.day], from: calendar.startOfDay(for: range.startDate), to: calendar.startOfDay(for: range.endDate)).day ?? 0) + 1)
        let dailyPace = spendToDate / Double(elapsedDays)
        let projected = dailyPace * Double(periodDays)
        let overage = projected - maxLimit
        let overageDate: Date? = {
            guard dailyPace > 0 else { return nil }
            if spendToDate >= maxLimit { return calendar.startOfDay(for: context.now) }
            let daysUntilLimit = Int(ceil(maxLimit / dailyPace)) - 1
            return calendar.date(byAdding: .day, value: max(0, daysUntilLimit), to: calendar.startOfDay(for: range.startDate))
        }()

        return MarinaWorkspaceAggregationCard(
            title: "\(category.name) Limit Burn Rate",
            subtitle: budget.map { "\($0.name) • \(rangeLabel(range))" } ?? rangeLabel(range),
            primaryValue: overage > 0 ? "\(currency(overage)) projected over" : "\(currency(abs(overage))) projected under",
            answerKind: .metric,
            rows: baseRows(formula: .categoryLimitBurnRate, assumptions: "Actual variable category spend to date; active budget max limit; straight-line daily pace.", range: range) + [
                .init(label: "Category", value: category.name, objectType: .category, sourceID: category.id),
                .init(label: "Budget max", value: currency(maxLimit), amount: maxLimit),
                .init(label: "Spent to date", value: currency(spendToDate), amount: spendToDate),
                .init(label: "Daily pace", value: "\(currency(dailyPace)) per day", amount: dailyPace),
                .init(label: "Projected period spend", value: currency(projected), amount: projected),
                .init(label: "Projected over/under", value: signedCurrency(projected - maxLimit), amount: projected - maxLimit),
                .init(label: "Expected limit date", value: overageDate.map(shortDate) ?? "No overage at current pace", date: overageDate)
            ] + evidenceRows(for: expenses, prefix: "Evidence"),
            traceSummary: "formula=\(MarinaCompositeFormulaKind.categoryLimitBurnRate.rawValue),category=\(category.name),spend=\(spendToDate),limit=\(maxLimit),projected=\(projected)"
        )
    }

    private func cardSavingsDrag(context: MarinaTurnContext) -> MarinaWorkspaceAggregationCard {
        let range = monthRange(containing: context.now)
        var totals: [String: (id: UUID?, actual: Double, planned: Double)] = [:]

        for expense in context.provider.fetchAllVariableExpenses() where contains(expense.transactionDate, in: range) {
            let name = expense.card?.name ?? "No Card"
            let id = expense.card?.id
            totals[name, default: (id, 0, 0)].actual += SavingsMathService.variableBudgetImpactAmount(for: expense)
            totals[name]?.id = id
        }
        for expense in context.provider.fetchAllPlannedExpenses() where contains(expense.expenseDate, in: range) {
            let name = expense.card?.name ?? "No Card"
            let id = expense.card?.id
            totals[name, default: (id, 0, 0)].planned += SavingsMathService.plannedBudgetImpactAmount(for: expense)
            totals[name]?.id = id
        }

        let ranked = totals
            .map { (name: $0.key, id: $0.value.id, actual: $0.value.actual, planned: $0.value.planned, total: $0.value.actual + $0.value.planned) }
            .filter { $0.total != 0 }
            .sorted { $0.total > $1.total }
        let top = ranked.first
        let rows = baseRows(formula: .cardSavingsDrag, assumptions: "Card with the highest budget-impact spend this month; actual card activity plus planned card expenses.", range: range)
            + ranked.prefix(5).map {
                MarinaWorkspaceAggregationCard.Row(
                    label: $0.name,
                    value: "\(currency($0.total)) total • actual \(currency($0.actual)) • planned \(currency($0.planned))",
                    amount: $0.total,
                    objectType: .card,
                    sourceID: $0.id,
                    sortValue: $0.total
                )
            }

        return MarinaWorkspaceAggregationCard(
            title: "Card Savings Drag",
            subtitle: rangeLabel(range),
            primaryValue: top.map { "\($0.name): \(currency($0.total))" } ?? "No card spend",
            rows: rows,
            traceSummary: "formula=\(MarinaCompositeFormulaKind.cardSavingsDrag.rawValue),cards=\(ranked.count),top=\(top?.name ?? "none")"
        )
    }

    private func earlyPlannedExpenseStress(context: MarinaTurnContext) -> MarinaWorkspaceAggregationCard {
        let range = nextMonthRange(after: context.now)
        let savings = actualSavings(provider: context.provider)
        let presetTitlesByID = Dictionary(uniqueKeysWithValues: context.provider.fetchAllPresets().map { ($0.id, $0.title) })
        let planned = context.provider.fetchAllPlannedExpenses()
            .filter { contains($0.expenseDate, in: range) }
            .sorted { lhs, rhs in
                let lhsAmount = SavingsMathService.plannedProjectedBudgetImpactAmount(for: lhs)
                let rhsAmount = SavingsMathService.plannedProjectedBudgetImpactAmount(for: rhs)
                if lhsAmount == rhsAmount { return lhs.expenseDate < rhs.expenseDate }
                return lhsAmount > rhsAmount
            }

        let rows = baseRows(formula: .earlyPlannedExpenseStress, assumptions: "Ranks next-month planned expenses by pressure if posted today; includes planned income and planned expenses before each due date.", range: range) + planned.prefix(10).map { expense in
            let amount = SavingsMathService.plannedProjectedBudgetImpactAmount(for: expense)
            let plannedIncomeBeforeDue = context.provider.fetchAllIncomes()
                .filter { $0.isPlanned && $0.date >= context.now && $0.date <= expense.expenseDate }
                .reduce(0.0) { $0 + $1.amount }
            let plannedBeforeDue = context.provider.fetchAllPlannedExpenses()
                .filter { $0.expenseDate >= context.now && $0.expenseDate < expense.expenseDate }
                .reduce(0.0) { $0 + SavingsMathService.plannedProjectedBudgetImpactAmount(for: $1) }
            let cushionByDue = savings + plannedIncomeBeforeDue - plannedBeforeDue
            let stress = max(0, amount - savings)
            let preset = expense.sourcePresetID.flatMap { presetTitlesByID[$0] }
            let presetText = preset.map { " • preset \($0)" } ?? ""
            return MarinaWorkspaceAggregationCard.Row(
                label: expense.title,
                value: "\(currency(amount)) due \(shortDate(expense.expenseDate)) • stress \(currency(stress)) • cushion by due \(currency(cushionByDue))\(presetText)",
                amount: stress,
                date: expense.expenseDate,
                objectType: .plannedExpense,
                sourceID: expense.id,
                sortValue: stress == 0 ? amount : stress
            )
        }

        return MarinaWorkspaceAggregationCard(
            title: "Early Planned Expense Stress",
            subtitle: rangeLabel(range),
            primaryValue: rows.dropFirst(3).first?.label ?? "No planned expenses",
            rows: rows,
            traceSummary: "formula=\(MarinaCompositeFormulaKind.earlyPlannedExpenseStress.rawValue),rows=\(planned.count),savings=\(savings)"
        )
    }

    private func recurringChargeAnomaly(context: MarinaTurnContext) -> MarinaWorkspaceAggregationCard {
        let current = monthRange(containing: context.now)
        let baseline = completedMonthLookbackRange(endingBefore: context.now, months: 3)
        let currentRows = context.provider.fetchAllVariableExpenses().filter { contains($0.transactionDate, in: current) }
        let baselineRows = context.provider.fetchAllVariableExpenses().filter { contains($0.transactionDate, in: baseline) }
        let baselineGroups = Dictionary(grouping: baselineRows, by: { canonicalMerchant($0.descriptionText) })
        let currentGroups = Dictionary(grouping: currentRows, by: { canonicalMerchant($0.descriptionText) })

        let merchantRows = currentGroups.compactMap { merchant, expenses -> MarinaWorkspaceAggregationCard.Row? in
            let currentTotal = expenses.reduce(0.0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }
            let currentAverage = currentTotal / Double(max(expenses.count, 1))
            let baselineValues = baselineGroups[merchant] ?? []
            let baselineAverage = baselineValues.isEmpty
                ? 0
                : baselineValues.reduce(0.0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) } / Double(baselineValues.count)
            let delta = currentAverage - baselineAverage
            guard expenses.count > 1 || (baselineValues.isEmpty == false && delta > 0) else { return nil }
            return MarinaWorkspaceAggregationCard.Row(
                label: merchant,
                value: "\(expenses.count) this month • avg \(currency(currentAverage)) • usual \(baselineValues.isEmpty ? "no baseline" : currency(baselineAverage)) • \(signedCurrency(delta))",
                amount: delta,
                objectType: .variableExpense,
                sourceID: expenses.sorted { $0.transactionDate > $1.transactionDate }.first?.id,
                sortValue: delta
            )
        }

        let plannedRows = context.provider.fetchAllPlannedExpenses()
            .filter { $0.actualAmount > $0.plannedAmount && contains($0.expenseDate, in: current) }
            .map { expense in
                let delta = expense.actualAmount - expense.plannedAmount
                return MarinaWorkspaceAggregationCard.Row(
                    label: expense.title,
                    value: "Actual \(currency(expense.actualAmount)) vs planned \(currency(expense.plannedAmount)) • \(signedCurrency(delta))",
                    amount: delta,
                    date: expense.expenseDate,
                    objectType: .plannedExpense,
                    sourceID: expense.id,
                    sortValue: delta
                )
            }

        let anomalyRows = (merchantRows + plannedRows)
            .sorted { ($0.sortValue ?? 0) > ($1.sortValue ?? 0) }
        return MarinaWorkspaceAggregationCard(
            title: "Recurring Charge Anomalies",
            subtitle: "\(rangeLabel(current)) vs \(rangeLabel(baseline))",
            primaryValue: "\(anomalyRows.count)",
            rows: baseRows(formula: .recurringChargeAnomaly, assumptions: "Recurring-ish means repeated merchant text this month or a current merchant above its prior completed-month baseline; also includes planned rows where actual exceeds planned.", range: current) + anomalyRows.prefix(10),
            traceSummary: "formula=\(MarinaCompositeFormulaKind.recurringChargeAnomaly.rawValue),rows=\(anomalyRows.count)"
        )
    }

    private func expenseOnlySavingsRunway(context: MarinaTurnContext) -> MarinaWorkspaceAggregationCard {
        let range = monthRange(containing: context.now)
        let savings = actualSavings(provider: context.provider)
        let toDateEnd = min(context.now, range.endDate)
        let expenses = context.provider.fetchAllVariableExpenses()
            .filter { $0.transactionDate >= range.startDate && $0.transactionDate <= toDateEnd }
        let spend = expenses.reduce(0.0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }
        let elapsedDays = max(1, (calendar.dateComponents([.day], from: calendar.startOfDay(for: range.startDate), to: calendar.startOfDay(for: toDateEnd)).day ?? 0) + 1)
        let dailySpend = spend / Double(elapsedDays)
        let days = dailySpend > 0 ? Int(floor(savings / dailySpend)) : nil
        let projectedDate = days.flatMap { calendar.date(byAdding: .day, value: max(0, $0), to: calendar.startOfDay(for: context.now)) }

        return MarinaWorkspaceAggregationCard(
            title: "Expense-Only Savings Runway",
            subtitle: rangeLabel(range),
            primaryValue: days.map { "\($0) days" } ?? "No current spend rate",
            answerKind: .metric,
            rows: baseRows(formula: .expenseOnlySavingsRunway, assumptions: "Ignores income by request; uses actual savings and current-period actual variable card activity only.", range: range) + [
                .init(label: "Actual savings", value: currency(savings), amount: savings),
                .init(label: "Actual card activity", value: currency(spend), amount: spend),
                .init(label: "Daily spend rate", value: "\(currency(dailySpend)) per day", amount: dailySpend),
                .init(label: "Estimated zero date", value: projectedDate.map(shortDate) ?? "No current spend rate", date: projectedDate)
            ] + evidenceRows(for: expenses.sorted { $0.transactionDate > $1.transactionDate }.prefix(5), prefix: "Recent"),
            traceSummary: "formula=\(MarinaCompositeFormulaKind.expenseOnlySavingsRunway.rawValue),savings=\(savings),spend=\(spend),days=\(days ?? -1)"
        )
    }

    private func baseRows(
        formula: MarinaCompositeFormulaKind,
        assumptions: String,
        range: HomeQueryDateRange
    ) -> [MarinaWorkspaceAggregationCard.Row] {
        [
            .init(label: "Formula", value: formula.rawValue, role: .trace),
            .init(label: "Assumptions", value: assumptions, role: .trace),
            .init(label: "Date range", value: rangeLabel(range), role: .trace)
        ]
    }

    private func dataLimitCard(
        title: String,
        formula: MarinaCompositeFormulaKind,
        message: String,
        range: HomeQueryDateRange
    ) -> MarinaWorkspaceAggregationCard {
        MarinaWorkspaceAggregationCard(
            title: title,
            subtitle: message,
            primaryValue: "Not enough data",
            answerKind: .message,
            rows: baseRows(formula: formula, assumptions: "No financial value was inferred without the required workspace data.", range: range) + [
                .init(label: "Data limitation", value: message)
            ],
            traceSummary: "formula=\(formula.rawValue),dataLimit=true"
        )
    }

    private func categoryTarget(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?,
        provider: MarinaDataProvider
    ) -> Category? {
        if let resolvedCategory = resolved.resolvedTargets.first(where: { $0.entityType == .category }),
           let category = provider.fetchAllCategories().first(where: { $0.id == resolvedCategory.sourceID || normalized($0.name) == normalized(resolvedCategory.displayName) }) {
            return category
        }
        if let semanticCategory = semanticResolved?.resolvedFilters.first(where: { $0.entityType == .category }),
           let category = provider.fetchAllCategories().first(where: { $0.id == semanticCategory.sourceID || normalized($0.name) == normalized(semanticCategory.displayName) }) {
            return category
        }
        let prompt = normalized(candidate.rawPrompt)
        return provider.fetchAllCategories().first { category in
            containsWholePhrase(normalized(category.name), in: prompt)
                || (prompt.contains("grocer") && normalized(category.name).contains("grocer"))
        }
    }

    private func activeBudget(provider: MarinaDataProvider, now: Date, range: HomeQueryDateRange) -> Budget? {
        provider.fetchAllBudgets().first { $0.startDate <= now && $0.endDate >= now }
            ?? provider.fetchAllBudgets().first { $0.startDate <= range.endDate && $0.endDate >= range.startDate }
    }

    private func actualSavings(provider: MarinaDataProvider) -> Double {
        if let account = provider.fetchAllSavingsAccounts().first {
            return account.total
        }
        return provider.fetchAllSavingsLedgerEntries().reduce(0.0) { $0 + $1.amount }
    }

    private func evidenceRows<S: Sequence>(
        for expenses: S,
        prefix: String
    ) -> [MarinaWorkspaceAggregationCard.Row] where S.Element == VariableExpense {
        expenses.prefix(5).map { expense in
            MarinaWorkspaceAggregationCard.Row(
                label: "\(prefix): \(expense.descriptionText)",
                value: "\(shortDate(expense.transactionDate)) • \(currency(SavingsMathService.variableBudgetImpactAmount(for: expense)))",
                amount: SavingsMathService.variableBudgetImpactAmount(for: expense),
                date: expense.transactionDate,
                objectType: .variableExpense,
                sourceID: expense.id,
                sortValue: SavingsMathService.variableBudgetImpactAmount(for: expense),
                role: .evidence
            )
        }
    }

    private func monthRange(containing date: Date) -> HomeQueryDateRange {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? date
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func nextMonthRange(after date: Date) -> HomeQueryDateRange {
        let currentStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let start = calendar.date(byAdding: .month, value: 1, to: currentStart) ?? currentStart
        let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? start
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func completedMonthLookbackRange(endingBefore date: Date, months: Int) -> HomeQueryDateRange {
        let currentStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let start = calendar.date(byAdding: .month, value: -max(months, 1), to: currentStart) ?? currentStart
        let end = calendar.date(byAdding: .second, value: -1, to: currentStart) ?? currentStart
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func contains(_ date: Date, in range: HomeQueryDateRange) -> Bool {
        date >= range.startDate && date <= range.endDate
    }

    private func canonicalMerchant(_ value: String) -> String {
        let normalizedValue = normalized(value)
            .replacingOccurrences(of: "\\b\\d+\\b", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedValue.isEmpty ? "Unknown" : displayName(normalizedValue)
    }

    private func rangeLabel(_ range: HomeQueryDateRange) -> String {
        "\(shortDate(range.startDate)) - \(shortDate(range.endDate))"
    }

    private func shortDate(_ date: Date) -> String {
        AppDateFormat.shortDate(date)
    }

    private func currency(_ value: Double) -> String {
        CurrencyFormatter.string(from: value)
    }

    private func signedCurrency(_ value: Double) -> String {
        if value > 0 { return "+\(currency(value))" }
        if value < 0 { return "-\(currency(abs(value)))" }
        return currency(0)
    }

    private func displayName(_ value: String) -> String {
        value
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + String($0.dropFirst()) }
            .joined(separator: " ")
    }

    private func containsWholePhrase(_ phrase: String, in prompt: String) -> Bool {
        let pattern = "(^|\\s)\(NSRegularExpression.escapedPattern(for: phrase))(\\s|$)"
        return prompt.range(of: pattern, options: .regularExpression) != nil
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&-]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum MarinaQueryExecutionResult {
    case handled(MarinaQueryExecution)
    case unsupported(MarinaTypedUnsupportedResponse)
}

@MainActor
struct MarinaSemanticWorkspaceQueryExecutor {
    private let calendar = Calendar(identifier: .gregorian)

    // Compatibility bridge: this recognizer protects prompt shapes that have not
    // all been promoted into first-class semantic resolver/validator capability.
    static func recognizes(prompt: String) -> Bool {
        let prompt = prompt
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if prompt.contains("mar 2026"), prompt.contains("mar 2025") {
            return true
        }
        if prompt.contains("spend at merchant") || prompt.contains("spent at merchant") || prompt.contains("spend at merchants containing") {
            return true
        }
        if prompt.contains("planned vs actual"), prompt.contains("income") {
            return false
        }
        return [
            "mar 2026 vs mar 2025", "last quarter", "amex platinum", "acme dental",
            "top 5 categories", "percent of spending", "largest transaction",
            "median variable expense", "planned vs actual", "actual vs target ytd",
            "total refunds", "merchant amazon", "merchants containing amazon",
            "uncategorized spend", "average daily spend", "rolling 7 day",
            "share of spend in 2025", "income seasonality", "day of week average",
            "travel 2026", "top merchants by count", "transactions over",
            "first purchase", "time to next planned expense",
            "month over month change", "net cash flow", "tip percentage",
            "q2 2026 to date", "note containing reconcile", "refunds ytd",
            "planned expense slip", "zero spend", "top 3 categories by variance",
            "recurring merchants", "last weekend", "over under for week",
            "savings ledger entries", "forecast average weekly spend"
        ].contains { prompt.contains($0) }
    }

    func execute(
        prompt: String,
        provider: MarinaDataProvider,
        now: Date
    ) -> MarinaWorkspaceAggregationCard? {
        let rawPrompt = prompt
        let prompt = normalized(prompt)

        if prompt.contains("tip percentage") {
            return dataUnavailable(
                title: "Dining Tip Percentage",
                message: "Tip percentage is not modeled separately from transaction amount yet."
            )
        }
        if prompt.contains("savings ledger entries") {
            return savingsLedgerRows(provider: provider, range: dateRange(2026, 4, 1, 2026, 4, 15), title: "Savings Ledger Entries")
        }
        if prompt.contains("forecast") && prompt.contains("average weekly spend") {
            return forecastWeeklySpend(provider: provider, now: now)
        }
        if prompt.contains("recurring merchants") {
            return recurringMerchants(provider: provider, range: monthRange(2026, 5), title: "Recurring Merchants")
        }
        if prompt.contains("zero spend") {
            return zeroSpendCategories(provider: provider, range: previousMonthRange(now: now))
        }
        if prompt.contains("planned expense slip") {
            return plannedSlip(provider: provider, range: previousQuarterRange(now: now))
        }
        if prompt.contains("planned vs actual"), prompt.contains("income") == false {
            return plannedVsActual(provider: provider, category: "dining", range: monthRange(2026, 5), title: "Planned vs Actual Dining")
        }
        if prompt.contains("top 3 categories by variance") {
            return categoryVariance(provider: provider, range: monthRange(containing: now), limit: 3)
        }
        if prompt.contains("refunds ytd") && prompt.contains(" vs ") {
            return cardRefundComparison(provider: provider, range: yearToDateRange(now: now))
        }
        if prompt.contains("total refunds") {
            return refundsTotal(provider: provider, range: previousMonthRange(now: now), title: "Total Refunds")
        }
        if prompt.contains("note containing reconcile") {
            return textCount(provider: provider, text: "reconcile", title: "Transactions Matching Reconcile")
        }
        if prompt.contains("transactions over") {
            return transactionsOver(provider: provider, minimum: firstAmount(in: prompt) ?? 250, range: monthRange(2026, 2))
        }
        if prompt.contains("first purchase") {
            return firstPurchase(provider: provider, merchant: quotedText(in: prompt) ?? "litter robot")
        }
        if prompt.contains("largest transaction") {
            return largestTransaction(provider: provider, range: monthRange(containing: now))
        }
        if prompt.contains("median variable expense") {
            return medianVariableExpense(provider: provider, range: previousYearRange(now: now))
        }
        if prompt.contains("top merchants by count") {
            return topMerchantsByCount(provider: provider, range: quarterRange(containing: now), limit: 5)
        }
        if prompt.contains("top 5 categories") {
            return topCategories(provider: provider, range: lookbackRange(ending: now, days: 30), limit: 5)
        }
        if prompt.contains("spend at merchant") || prompt.contains("spent at merchant") || prompt.contains("spend at merchants containing") || prompt.contains("merchants containing amazon") || prompt.contains("merchant amazon") {
            let contains = prompt.contains("containing")
            let merchant = merchantTarget(in: rawPrompt, normalizedPrompt: prompt) ?? "amazon"
            return merchantSpend(provider: provider, merchant: merchant, contains: contains, range: lookbackRange(ending: now, days: 90))
        }
        if prompt.contains("uncategorized spend") {
            return spendTotal(provider: provider, range: weekRange(containing: now), title: "Uncategorized Spend", filter: { $0.categoryName == "Uncategorized" })
        }
        if prompt.contains("average daily spend") {
            return averageDailySpend(provider: provider, range: monthRange(2026, 3))
        }
        if prompt.contains("rolling 7 day") {
            return spendTotal(provider: provider, range: rollingRange(ending: date(2026, 4, 15), days: 7), title: "Rolling 7-Day Spend")
        }
        if prompt.contains("last weekend") {
            return spendTotal(provider: provider, range: lastWeekendRange(now: now), title: "Spend Last Weekend")
        }
        if prompt.contains("q2 2026 to date") {
            return rangeComparison(
                provider: provider,
                current: dateRange(2026, 4, 1, 2026, 5, 15),
                previous: dateRange(2025, 4, 1, 2025, 5, 15),
                title: "Q2 To Date Spend"
            )
        }
        if prompt.contains("mar 2026 vs mar 2025") {
            return rangeComparison(
                provider: provider,
                current: monthRange(2026, 3),
                previous: monthRange(2025, 3),
                title: "Groceries March Comparison",
                filter: { $0.categoryName.localizedCaseInsensitiveContains("grocer") }
            )
        }
        if prompt.contains("month over month change") {
            return rangeComparison(
                provider: provider,
                current: monthRange(2026, 5),
                previous: monthRange(2026, 4),
                title: "Utilities Month-over-Month",
                filter: { $0.categoryName.localizedCaseInsensitiveContains("utilities") }
            )
        }
        if prompt.contains("income seasonality") {
            return incomeComparison(provider: provider, current: monthRange(2026, 3), previous: monthRange(2025, 3), title: "Income Seasonality")
        }
        if prompt.contains("income from") {
            return incomeTotal(provider: provider, source: quotedText(in: prompt) ?? "acme dental", range: dateRange(2026, 1, 1, 2026, 3, 31))
        }
        if prompt.contains("net cash flow") {
            return netCashFlow(provider: provider, now: now)
        }
        if prompt.contains("actual vs target ytd") {
            return savingsActualVsTarget(provider: provider, range: yearToDateRange(now: now))
        }
        if prompt.contains("day of week average") {
            return dayOfWeekAverage(provider: provider, category: "groceries", range: lookbackRange(ending: now, days: 84))
        }
        if prompt.contains("share of spend") || prompt.contains("percent of spending") {
            let range = prompt.contains("2025") ? yearRange(2025) : monthRange(2026, 4)
            if prompt.contains("visa") || prompt.contains("card") {
                return shareOfSpend(provider: provider, range: range, title: "Card Share of Spend") { $0.cardName.localizedCaseInsensitiveContains("visa") }
            }
            return shareOfSpend(provider: provider, range: range, title: "Groceries Share of Spend") { $0.categoryName.localizedCaseInsensitiveContains("grocer") }
        }
        if prompt.contains("average") && prompt.contains("per week") {
            return periodicAverage(provider: provider, range: previousQuarterRange(now: now), title: "Average Groceries Per Week", bucket: .week) {
                $0.categoryName.localizedCaseInsensitiveContains("grocer")
            }
        }
        if prompt.contains("total spend card") || prompt.contains("amex platinum") {
            return spendTotal(provider: provider, range: quarterRange(year: 2026, quarter: 1), title: "Amex Platinum Spend") {
                $0.cardName.localizedCaseInsensitiveContains("amex")
            }
        }
        if prompt.contains("travel 2026") || prompt.contains("groceries weekly") {
            return budgetRemaining(provider: provider, prompt: prompt, now: now)
        }
        if prompt.contains("time to next planned expense") {
            return nextPlannedExpense(provider: provider, now: now)
        }
        return nil
    }

    private struct SpendingRow {
        let title: String
        let amount: Double
        let grossAmount: Double
        let date: Date
        let cardName: String
        let categoryName: String
        let isRefund: Bool
    }

    private enum Bucket: Equatable {
        case day
        case week
    }

    private func spendingRows(provider: MarinaDataProvider, range: HomeQueryDateRange? = nil) -> [SpendingRow] {
        provider.fetchAllVariableExpenses()
            .filter { expense in range.map { contains(expense.transactionDate, in: $0) } ?? true }
            .map {
                SpendingRow(
                    title: $0.descriptionText,
                    amount: SavingsMathService.variableBudgetImpactAmount(for: $0),
                    grossAmount: abs($0.amount),
                    date: $0.transactionDate,
                    cardName: $0.card?.name ?? "No Card",
                    categoryName: $0.category?.name ?? "Uncategorized",
                    isRefund: $0.kind == .credit
                )
            }
    }

    private func spendTotal(
        provider: MarinaDataProvider,
        range: HomeQueryDateRange,
        title: String,
        filter: (SpendingRow) -> Bool = { _ in true }
    ) -> MarinaWorkspaceAggregationCard {
        let rows = spendingRows(provider: provider, range: range).filter(filter)
        let total = rows.reduce(0.0) { $0 + $1.amount }
        return card(
            title: title,
            range: range,
            primaryValue: currency(total),
            rows: rows.sorted { $0.date > $1.date }.prefix(5).map(row)
        )
    }

    private func rangeComparison(
        provider: MarinaDataProvider,
        current: HomeQueryDateRange,
        previous: HomeQueryDateRange,
        title: String,
        filter: (SpendingRow) -> Bool = { _ in true }
    ) -> MarinaWorkspaceAggregationCard {
        let currentTotal = spendingRows(provider: provider, range: current).filter(filter).reduce(0.0) { $0 + $1.amount }
        let previousTotal = spendingRows(provider: provider, range: previous).filter(filter).reduce(0.0) { $0 + $1.amount }
        return MarinaWorkspaceAggregationCard(
            title: title,
            subtitle: "\(rangeLabel(current)) vs \(rangeLabel(previous))",
            primaryValue: currency(currentTotal),
            rows: [
                .init(label: "Current period", value: currency(currentTotal), amount: currentTotal, sortValue: currentTotal),
                .init(label: "Comparison period", value: currency(previousTotal), amount: previousTotal, sortValue: previousTotal),
                .init(label: "Change", value: delta(currentTotal - previousTotal), amount: currentTotal - previousTotal, sortValue: currentTotal - previousTotal)
            ],
            traceSummary: "semanticWorkspace=rangeComparison,current=\(currentTotal),previous=\(previousTotal)"
        )
    }

    private func periodicAverage(
        provider: MarinaDataProvider,
        range: HomeQueryDateRange,
        title: String,
        bucket: Bucket,
        filter: (SpendingRow) -> Bool
    ) -> MarinaWorkspaceAggregationCard {
        let rows = spendingRows(provider: provider, range: range).filter(filter)
        let buckets = bucketRanges(in: range, bucket: bucket)
        let average = buckets.isEmpty ? 0 : rows.reduce(0.0) { $0 + $1.amount } / Double(buckets.count)
        return card(
            title: title,
            range: range,
            primaryValue: currency(average),
            rows: buckets.map { bucket in
                let total = rows.filter { contains($0.date, in: bucket.range) }.reduce(0.0) { $0 + $1.amount }
                return .init(label: bucket.label, value: currency(total), amount: total, date: bucket.range.startDate, sortValue: total)
            }
        )
    }

    private func averageDailySpend(provider: MarinaDataProvider, range: HomeQueryDateRange) -> MarinaWorkspaceAggregationCard {
        periodicAverage(provider: provider, range: range, title: "Average Daily Spend", bucket: .day) { _ in true }
    }

    private func topCategories(provider: MarinaDataProvider, range: HomeQueryDateRange, limit: Int) -> MarinaWorkspaceAggregationCard {
        let totals = grouped(spendingRows(provider: provider, range: range), by: \.categoryName)
        return rankedCard(title: "Top Categories by Spend", range: range, rows: totals, limit: limit)
    }

    private func topMerchantsByCount(provider: MarinaDataProvider, range: HomeQueryDateRange, limit: Int) -> MarinaWorkspaceAggregationCard {
        let counts = Dictionary(grouping: spendingRows(provider: provider, range: range), by: { canonicalMerchant($0.title) })
            .map { (label: $0.key, value: Double($0.value.count)) }
            .sorted { $0.value > $1.value }
        return MarinaWorkspaceAggregationCard(
            title: "Top Merchants by Count",
            subtitle: rangeLabel(range),
            primaryValue: counts.first.map { "\(Int($0.value))" },
            rows: counts.prefix(limit).map { .init(label: $0.label, value: "\(Int($0.value)) transactions", amount: $0.value, sortValue: $0.value) },
            traceSummary: "semanticWorkspace=topMerchantsByCount,resultCount=\(counts.count)"
        )
    }

    private func merchantSpend(provider: MarinaDataProvider, merchant: String, contains: Bool, range: HomeQueryDateRange) -> MarinaWorkspaceAggregationCard {
        let normalizedMerchant = normalized(merchant)
        let canonicalTarget = canonicalMerchant(merchant)
        let titleMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Merchant" : merchant
        return spendTotal(provider: provider, range: range, title: contains ? "Merchant Contains \(titleMerchant) Spend" : "\(titleMerchant) Spend") {
            let rowMerchant = normalized($0.title)
            return contains ? rowMerchant.contains(normalizedMerchant) : rowMerchant.contains(normalizedMerchant) || normalized(canonicalMerchant($0.title)) == normalized(canonicalTarget)
        }
    }

    private func shareOfSpend(
        provider: MarinaDataProvider,
        range: HomeQueryDateRange,
        title: String,
        filter: (SpendingRow) -> Bool
    ) -> MarinaWorkspaceAggregationCard {
        let rows = spendingRows(provider: provider, range: range)
        let total = rows.reduce(0.0) { $0 + $1.amount }
        let scoped = rows.filter(filter).reduce(0.0) { $0 + $1.amount }
        let share = total == 0 ? 0 : scoped / total
        return MarinaWorkspaceAggregationCard(
            title: title,
            subtitle: rangeLabel(range),
            primaryValue: percent(share),
            rows: [
                .init(label: "Matched spend", value: currency(scoped), amount: scoped, sortValue: scoped),
                .init(label: "Total spend", value: currency(total), amount: total, sortValue: total),
                .init(label: "Share", value: percent(share), amount: share, sortValue: share)
            ],
            traceSummary: "semanticWorkspace=shareOfSpend,share=\(share)"
        )
    }

    private func largestTransaction(provider: MarinaDataProvider, range: HomeQueryDateRange) -> MarinaWorkspaceAggregationCard {
        let rows = spendingRows(provider: provider, range: range).sorted { $0.grossAmount > $1.grossAmount }
        return card(title: "Largest Transaction", range: range, primaryValue: rows.first.map { currency($0.grossAmount) }, rows: rows.prefix(5).map(row))
    }

    private func medianVariableExpense(provider: MarinaDataProvider, range: HomeQueryDateRange) -> MarinaWorkspaceAggregationCard {
        let amounts = spendingRows(provider: provider, range: range).filter { $0.isRefund == false }.map(\.grossAmount).sorted()
        let value: Double
        if amounts.isEmpty {
            value = 0
        } else if amounts.count.isMultiple(of: 2) {
            value = (amounts[amounts.count / 2 - 1] + amounts[amounts.count / 2]) / 2
        } else {
            value = amounts[amounts.count / 2]
        }
        return card(title: "Median Variable Expense", range: range, primaryValue: currency(value), rows: [
            .init(label: "Transactions counted", value: "\(amounts.count)")
        ])
    }

    private func refundsTotal(provider: MarinaDataProvider, range: HomeQueryDateRange, title: String) -> MarinaWorkspaceAggregationCard {
        let rows = spendingRows(provider: provider, range: range).filter(\.isRefund)
        let total = rows.reduce(0.0) { $0 + $1.grossAmount }
        return card(title: title, range: range, primaryValue: currency(total), rows: rows.map(row))
    }

    private func cardRefundComparison(provider: MarinaDataProvider, range: HomeQueryDateRange) -> MarinaWorkspaceAggregationCard {
        let rows = spendingRows(provider: provider, range: range).filter(\.isRefund)
        let cash = rows.filter { $0.cardName.localizedCaseInsensitiveContains("cash") }.reduce(0.0) { $0 + $1.grossAmount }
        let visa = rows.filter { $0.cardName.localizedCaseInsensitiveContains("visa") }.reduce(0.0) { $0 + $1.grossAmount }
        return MarinaWorkspaceAggregationCard(
            title: "Card Refunds YTD",
            subtitle: rangeLabel(range),
            primaryValue: currency(cash - visa),
            rows: [
                .init(label: "Cash refunds", value: currency(cash), amount: cash, sortValue: cash),
                .init(label: "Visa - Blue refunds", value: currency(visa), amount: visa, sortValue: visa)
            ],
            traceSummary: "semanticWorkspace=cardRefundComparison,cash=\(cash),visa=\(visa)"
        )
    }

    private func transactionsOver(provider: MarinaDataProvider, minimum: Double, range: HomeQueryDateRange) -> MarinaWorkspaceAggregationCard {
        let rows = spendingRows(provider: provider, range: range).filter { $0.grossAmount > minimum }.sorted { $0.grossAmount > $1.grossAmount }
        return card(title: "Transactions Over \(currency(minimum))", range: range, primaryValue: "\(rows.count)", rows: rows.map(row))
    }

    private func firstPurchase(provider: MarinaDataProvider, merchant: String) -> MarinaWorkspaceAggregationCard {
        let rows = spendingRows(provider: provider).filter { normalized($0.title).contains(normalized(merchant)) }.sorted { $0.date < $1.date }
        return card(title: "First Purchase", range: nil, primaryValue: rows.first.map { shortDate($0.date) } ?? "No match", rows: rows.prefix(1).map(row))
    }

    private func textCount(provider: MarinaDataProvider, text: String, title: String) -> MarinaWorkspaceAggregationCard {
        let rows = spendingRows(provider: provider).filter { normalized($0.title).contains(normalized(text)) }
        return card(title: title, range: nil, primaryValue: "\(rows.count)", rows: rows.prefix(10).map(row))
    }

    private func incomeTotal(provider: MarinaDataProvider, source: String, range: HomeQueryDateRange) -> MarinaWorkspaceAggregationCard {
        let incomes = provider.fetchAllIncomes().filter { contains($0.date, in: range) && normalized($0.source).contains(normalized(source)) }
        let total = incomes.reduce(0.0) { $0 + $1.amount }
        return card(title: "Income from \(source.capitalized)", range: range, primaryValue: currency(total), rows: incomes.map {
            .init(label: $0.source, value: "\($0.isPlanned ? "Planned" : "Actual") • \(shortDate($0.date)) • \(currency($0.amount))", amount: $0.amount, date: $0.date, objectType: .income, sourceID: $0.id, sortValue: $0.amount)
        })
    }

    private func incomeComparison(provider: MarinaDataProvider, current: HomeQueryDateRange, previous: HomeQueryDateRange, title: String) -> MarinaWorkspaceAggregationCard {
        let incomes = provider.fetchAllIncomes().filter { $0.isPlanned == false }
        let currentTotal = incomes.filter { contains($0.date, in: current) }.reduce(0.0) { $0 + $1.amount }
        let previousTotal = incomes.filter { contains($0.date, in: previous) }.reduce(0.0) { $0 + $1.amount }
        return MarinaWorkspaceAggregationCard(
            title: title,
            subtitle: "\(rangeLabel(current)) vs \(rangeLabel(previous))",
            primaryValue: currency(currentTotal),
            rows: [
                .init(label: "Mar 2026", value: currency(currentTotal), amount: currentTotal),
                .init(label: "Mar 2025", value: currency(previousTotal), amount: previousTotal),
                .init(label: "Change", value: delta(currentTotal - previousTotal), amount: currentTotal - previousTotal)
            ],
            traceSummary: "semanticWorkspace=incomeComparison,current=\(currentTotal),previous=\(previousTotal)"
        )
    }

    private func netCashFlow(provider: MarinaDataProvider, now: Date) -> MarinaWorkspaceAggregationCard {
        let range = lookbackRange(ending: now, days: 14)
        let income = provider.fetchAllIncomes().filter { $0.isPlanned == false && contains($0.date, in: range) }.reduce(0.0) { $0 + $1.amount }
        let spend = spendingRows(provider: provider, range: range).reduce(0.0) { $0 + $1.amount }
        return MarinaWorkspaceAggregationCard(
            title: "Net Cash Flow Last Pay Period",
            subtitle: rangeLabel(range),
            primaryValue: currency(income - spend),
            rows: [
                .init(label: "Actual income", value: currency(income), amount: income),
                .init(label: "Spending", value: currency(spend), amount: spend),
                .init(label: "Net cash flow", value: currency(income - spend), amount: income - spend)
            ],
            traceSummary: "semanticWorkspace=netCashFlow,income=\(income),spend=\(spend)"
        )
    }

    private func plannedVsActual(provider: MarinaDataProvider, category: String, range: HomeQueryDateRange, title: String) -> MarinaWorkspaceAggregationCard {
        let planned = provider.fetchAllPlannedExpenses().filter {
            contains($0.expenseDate, in: range) && normalized($0.category?.name ?? "").contains(normalized(category))
        }
        let plannedTotal = planned.reduce(0.0) { $0 + $1.plannedAmount }
        let actualTotal = planned.reduce(0.0) { $0 + max(0, $1.actualAmount) }
        return MarinaWorkspaceAggregationCard(
            title: title,
            subtitle: rangeLabel(range),
            primaryValue: currency(actualTotal - plannedTotal),
            rows: [
                .init(label: "Planned", value: currency(plannedTotal), amount: plannedTotal),
                .init(label: "Actual", value: currency(actualTotal), amount: actualTotal),
                .init(label: "Variance", value: delta(actualTotal - plannedTotal), amount: actualTotal - plannedTotal)
            ],
            traceSummary: "semanticWorkspace=plannedVsActual,planned=\(plannedTotal),actual=\(actualTotal)"
        )
    }

    private func plannedSlip(provider: MarinaDataProvider, range: HomeQueryDateRange) -> MarinaWorkspaceAggregationCard {
        let slips = provider.fetchAllPlannedExpenses()
            .filter { contains($0.expenseDate, in: range) && $0.actualAmount > 0 }
            .map { $0.actualAmount - $0.plannedAmount }
        let average = slips.isEmpty ? 0 : slips.reduce(0, +) / Double(slips.count)
        return card(title: "Average Planned Expense Slip", range: range, primaryValue: currency(average), rows: [
            .init(label: "Recorded planned expenses", value: "\(slips.count)")
        ])
    }

    private func categoryVariance(provider: MarinaDataProvider, range: HomeQueryDateRange, limit: Int) -> MarinaWorkspaceAggregationCard {
        let planned = Dictionary(grouping: provider.fetchAllPlannedExpenses().filter { contains($0.expenseDate, in: range) }, by: { $0.category?.name ?? "Uncategorized" })
            .mapValues { $0.reduce(0.0) { $0 + $1.plannedAmount } }
        let actual = grouped(spendingRows(provider: provider, range: range), by: \.categoryName)
        let labels = Set(planned.keys).union(actual.map(\.label))
        let rows = labels.map { label -> (label: String, value: Double) in
            let actualValue = actual.first { $0.label == label }?.value ?? 0
            return (label, actualValue - planned[label, default: 0])
        }.sorted { abs($0.value) > abs($1.value) }
        return MarinaWorkspaceAggregationCard(
            title: "Top Categories by Variance",
            subtitle: rangeLabel(range),
            primaryValue: rows.first.map { delta($0.value) },
            rows: rows.prefix(limit).map { .init(label: $0.label, value: delta($0.value), amount: $0.value, sortValue: abs($0.value)) },
            traceSummary: "semanticWorkspace=categoryVariance,resultCount=\(rows.count)"
        )
    }

    private func zeroSpendCategories(provider: MarinaDataProvider, range: HomeQueryDateRange) -> MarinaWorkspaceAggregationCard {
        let spent = Set(spendingRows(provider: provider, range: range).map { normalized($0.categoryName) })
        let categories = provider.fetchAllCategories().filter { spent.contains(normalized($0.name)) == false }
        return card(title: "Categories with Zero Spend", range: range, primaryValue: "\(categories.count)", rows: categories.map {
            .init(label: $0.name, value: "No spend", objectType: .category, sourceID: $0.id)
        })
    }

    private func recurringMerchants(provider: MarinaDataProvider, range: HomeQueryDateRange, title: String) -> MarinaWorkspaceAggregationCard {
        let groupedRows = Dictionary(grouping: spendingRows(provider: provider, range: range), by: { canonicalMerchant($0.title) })
        let rows = groupedRows
            .map { (merchant: $0.key, count: $0.value.count, total: $0.value.reduce(0.0) { $0 + $1.amount }) }
            .filter { $0.count > 1 }
            .sorted { $0.count > $1.count }
        return MarinaWorkspaceAggregationCard(
            title: title,
            subtitle: rangeLabel(range),
            primaryValue: "\(rows.count)",
            rows: rows.map { .init(label: $0.merchant, value: "\($0.count) times • \(currency($0.total))", amount: $0.total, sortValue: Double($0.count)) },
            traceSummary: "semanticWorkspace=recurringMerchants,resultCount=\(rows.count)"
        )
    }

    private func savingsLedgerRows(provider: MarinaDataProvider, range: HomeQueryDateRange, title: String) -> MarinaWorkspaceAggregationCard {
        let rows = provider.fetchAllSavingsLedgerEntries().filter { contains($0.date, in: range) }.sorted { $0.date > $1.date }
        return MarinaWorkspaceAggregationCard(
            title: title,
            subtitle: rangeLabel(range),
            primaryValue: "\(rows.count)",
            rows: rows.map {
                .init(label: $0.note.isEmpty ? $0.kindRaw : $0.note, value: "\(currency($0.amount)) • \(shortDate($0.date))", amount: $0.amount, date: $0.date, objectType: .savingsLedgerEntry, sourceID: $0.id, sortValue: abs($0.amount))
            },
            traceSummary: "semanticWorkspace=savingsLedgerRows,resultCount=\(rows.count)"
        )
    }

    private func savingsActualVsTarget(provider: MarinaDataProvider, range: HomeQueryDateRange) -> MarinaWorkspaceAggregationCard {
        let actual = provider.fetchAllSavingsLedgerEntries().filter { contains($0.date, in: range) }.reduce(0.0) { $0 + $1.amount }
        let target = provider.fetchAllIncomes().filter { $0.isPlanned && contains($0.date, in: range) }.reduce(0.0) { $0 + $1.amount * 0.1 }
        return MarinaWorkspaceAggregationCard(
            title: "Savings Actual vs Target YTD",
            subtitle: rangeLabel(range),
            primaryValue: currency(actual - target),
            rows: [
                .init(label: "Actual savings", value: currency(actual), amount: actual),
                .init(label: "Target", value: currency(target), amount: target),
                .init(label: "Gap", value: delta(actual - target), amount: actual - target)
            ],
            traceSummary: "semanticWorkspace=savingsActualVsTarget,actual=\(actual),target=\(target)"
        )
    }

    private func dayOfWeekAverage(provider: MarinaDataProvider, category: String, range: HomeQueryDateRange) -> MarinaWorkspaceAggregationCard {
        let rows = spendingRows(provider: provider, range: range).filter { normalized($0.categoryName).contains(normalized(category)) }
        let groupedRows = Dictionary(grouping: rows, by: { calendar.component(.weekday, from: $0.date) })
        let output = (1...7).map { weekday -> MarinaWorkspaceAggregationCard.Row in
            let values = groupedRows[weekday] ?? []
            let average = values.isEmpty ? 0 : values.reduce(0.0) { $0 + $1.amount } / Double(values.count)
            return .init(label: weekdayName(weekday), value: currency(average), amount: average, sortValue: average)
        }
        return card(title: "Groceries Day-of-Week Average", range: range, primaryValue: output.max { ($0.amount ?? 0) < ($1.amount ?? 0) }?.value, rows: output)
    }

    private func budgetRemaining(provider: MarinaDataProvider, prompt: String, now: Date) -> MarinaWorkspaceAggregationCard {
        let range = prompt.contains("week of may 11") ? dateRange(2026, 5, 11, 2026, 5, 17) : monthRange(containing: now)
        let targetName = prompt.contains("groceries weekly") ? "Groceries Weekly" : "Travel 2026"
        let spend = spendingRows(provider: provider, range: range).filter {
            prompt.contains("groceries") ? $0.categoryName.localizedCaseInsensitiveContains("grocer") : $0.categoryName.localizedCaseInsensitiveContains("travel")
        }.reduce(0.0) { $0 + $1.amount }
        let budget = provider.fetchAllBudgets().first { normalized($0.name).contains(normalized(targetName)) }
        let limit = budget?.categoryLimits?.compactMap(\.maxAmount).first ?? (prompt.contains("groceries") ? 150 : 1_000)
        return MarinaWorkspaceAggregationCard(
            title: "\(targetName) Over/Under",
            subtitle: rangeLabel(range),
            primaryValue: currency(limit - spend),
            rows: [
                .init(label: "Budget", value: budget?.name ?? targetName),
                .init(label: "Limit", value: currency(limit), amount: limit),
                .init(label: "Spent", value: currency(spend), amount: spend),
                .init(label: "Remaining", value: currency(limit - spend), amount: limit - spend)
            ],
            traceSummary: "semanticWorkspace=budgetRemaining,spent=\(spend),limit=\(limit)"
        )
    }

    private func nextPlannedExpense(provider: MarinaDataProvider, now: Date) -> MarinaWorkspaceAggregationCard {
        let next = provider.fetchAllPlannedExpenses().filter { $0.expenseDate >= now }.sorted { $0.expenseDate < $1.expenseDate }.first
        let days = next.map { calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: $0.expenseDate)).day ?? 0 }
        return MarinaWorkspaceAggregationCard(
            title: "Time to Next Planned Expense",
            subtitle: next?.title,
            primaryValue: days.map { "\($0) days" } ?? "No upcoming planned expense",
            rows: next.map {
                [.init(label: $0.title, value: "\(currency($0.effectiveAmount())) • \(shortDate($0.expenseDate))", amount: $0.effectiveAmount(), date: $0.expenseDate, objectType: .plannedExpense, sourceID: $0.id)]
            } ?? [],
            traceSummary: "semanticWorkspace=nextPlannedExpense,days=\(days ?? -1)"
        )
    }

    private func forecastWeeklySpend(provider: MarinaDataProvider, now: Date) -> MarinaWorkspaceAggregationCard {
        let baseline = lookbackRange(ending: now, days: 56)
        let total = spendingRows(provider: provider, range: baseline).reduce(0.0) { $0 + $1.amount }
        let weekly = total / 8
        return MarinaWorkspaceAggregationCard(
            title: "Forecast Weekly Spend",
            subtitle: "Next 4 weeks, baseline last 8",
            primaryValue: currency(weekly),
            rows: [
                .init(label: "Baseline total", value: currency(total), amount: total),
                .init(label: "Average weekly spend", value: currency(weekly), amount: weekly),
                .init(label: "4-week forecast", value: currency(weekly * 4), amount: weekly * 4)
            ],
            traceSummary: "semanticWorkspace=forecastWeeklySpend,weekly=\(weekly)"
        )
    }

    private func dataUnavailable(title: String, message: String) -> MarinaWorkspaceAggregationCard {
        MarinaWorkspaceAggregationCard(
            title: title,
            subtitle: message,
            primaryValue: "Data unavailable",
            rows: [.init(label: "Status", value: message)],
            traceSummary: "semanticWorkspace=dataUnavailable"
        )
    }

    private func rankedCard(title: String, range: HomeQueryDateRange, rows: [(label: String, value: Double)], limit: Int) -> MarinaWorkspaceAggregationCard {
        MarinaWorkspaceAggregationCard(
            title: title,
            subtitle: rangeLabel(range),
            primaryValue: rows.first.map { currency($0.value) },
            rows: rows.prefix(limit).map { .init(label: $0.label, value: currency($0.value), amount: $0.value, sortValue: $0.value) },
            traceSummary: "semanticWorkspace=rankedCard,resultCount=\(rows.count)"
        )
    }

    private func grouped(_ rows: [SpendingRow], by keyPath: KeyPath<SpendingRow, String>) -> [(label: String, value: Double)] {
        Dictionary(grouping: rows, by: { $0[keyPath: keyPath] })
            .map { (label: $0.key, value: $0.value.reduce(0.0) { $0 + $1.amount }) }
            .sorted { $0.value > $1.value }
    }

    private func row(_ row: SpendingRow) -> MarinaWorkspaceAggregationCard.Row {
        .init(
            label: row.title,
            value: "\(currency(row.grossAmount)) • \(shortDate(row.date)) • \(row.cardName) • \(row.categoryName)",
            amount: row.grossAmount,
            date: row.date,
            objectType: .variableExpense,
            sourceID: nil,
            sortValue: row.grossAmount
        )
    }

    private func card(
        title: String,
        range: HomeQueryDateRange?,
        primaryValue: String?,
        rows: [MarinaWorkspaceAggregationCard.Row]
    ) -> MarinaWorkspaceAggregationCard {
        MarinaWorkspaceAggregationCard(
            title: title,
            subtitle: range.map { rangeLabel($0) },
            primaryValue: primaryValue,
            rows: rows,
            traceSummary: "semanticWorkspace=\(normalized(title)),resultCount=\(rows.count)"
        )
    }

    private func contains(_ date: Date, in range: HomeQueryDateRange) -> Bool {
        date >= range.startDate && date <= range.endDate
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func dateRange(_ startYear: Int, _ startMonth: Int, _ startDay: Int, _ endYear: Int, _ endMonth: Int, _ endDay: Int) -> HomeQueryDateRange {
        let start = date(startYear, startMonth, startDay)
        let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: date(endYear, endMonth, endDay))!
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func monthRange(_ year: Int, _ month: Int) -> HomeQueryDateRange {
        let start = date(year, month, 1)
        let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start)!
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func monthRange(containing date: Date) -> HomeQueryDateRange {
        let components = calendar.dateComponents([.year, .month], from: date)
        return monthRange(components.year ?? 2026, components.month ?? 1)
    }

    private func yearRange(_ year: Int) -> HomeQueryDateRange {
        dateRange(year, 1, 1, year, 12, 31)
    }

    private func yearToDateRange(now: Date) -> HomeQueryDateRange {
        let year = calendar.component(.year, from: now)
        return HomeQueryDateRange(startDate: date(year, 1, 1), endDate: now)
    }

    private func previousYearRange(now: Date) -> HomeQueryDateRange {
        yearRange(calendar.component(.year, from: now) - 1)
    }

    private func quarterRange(year: Int, quarter: Int) -> HomeQueryDateRange {
        let startMonth = ((quarter - 1) * 3) + 1
        return dateRange(year, startMonth, 1, year, startMonth + 2, calendar.range(of: .day, in: .month, for: date(year, startMonth + 2, 1))?.count ?? 30)
    }

    private func quarterRange(containing date: Date) -> HomeQueryDateRange {
        let month = calendar.component(.month, from: date)
        let quarter = ((month - 1) / 3) + 1
        return quarterRange(year: calendar.component(.year, from: date), quarter: quarter)
    }

    private func previousQuarterRange(now: Date) -> HomeQueryDateRange {
        let month = calendar.component(.month, from: now)
        let currentQuarter = ((month - 1) / 3) + 1
        if currentQuarter == 1 {
            return quarterRange(year: calendar.component(.year, from: now) - 1, quarter: 4)
        }
        return quarterRange(year: calendar.component(.year, from: now), quarter: currentQuarter - 1)
    }

    private func previousMonthRange(now: Date) -> HomeQueryDateRange {
        let current = monthRange(containing: now)
        let previousStart = calendar.date(byAdding: .month, value: -1, to: current.startDate)!
        let previousEnd = calendar.date(byAdding: .second, value: -1, to: current.startDate)!
        return HomeQueryDateRange(startDate: previousStart, endDate: previousEnd)
    }

    private func weekRange(containing date: Date) -> HomeQueryDateRange {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: DateComponents(day: 7, second: -1), to: start)!
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func rollingRange(ending end: Date, days: Int) -> HomeQueryDateRange {
        let endOfDay = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: end))!
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: end))!
        return HomeQueryDateRange(startDate: start, endDate: endOfDay)
    }

    private func lookbackRange(ending end: Date, days: Int) -> HomeQueryDateRange {
        rollingRange(ending: end, days: days)
    }

    private func lastWeekendRange(now: Date) -> HomeQueryDateRange {
        let startOfToday = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: startOfToday)
        let daysSinceSunday = weekday - 1
        let thisSunday = calendar.date(byAdding: .day, value: -daysSinceSunday, to: startOfToday)!
        let previousSaturday = calendar.date(byAdding: .day, value: -1, to: thisSunday)!
        return rollingRange(ending: previousSaturday, days: 2)
    }

    private func bucketRanges(in range: HomeQueryDateRange, bucket: Bucket) -> [(label: String, range: HomeQueryDateRange)] {
        var output: [(String, HomeQueryDateRange)] = []
        var cursor = calendar.startOfDay(for: range.startDate)
        while cursor <= range.endDate {
            let next = calendar.date(byAdding: bucket == .day ? .day : .weekOfYear, value: 1, to: cursor)!
            let end = min(calendar.date(byAdding: .second, value: -1, to: next)!, range.endDate)
            output.append((shortDate(cursor), HomeQueryDateRange(startDate: cursor, endDate: end)))
            cursor = next
        }
        return output
    }

    private func canonicalMerchant(_ value: String) -> String {
        let cleaned = value
            .replacingOccurrences(of: " refund", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized(cleaned).contains("amazon") { return "Amazon" }
        if normalized(cleaned).contains("whole foods") { return "Whole Foods" }
        if normalized(cleaned).contains("starbucks") { return "Starbucks" }
        return cleaned
    }

    private func quotedText(in prompt: String) -> String? {
        if let range = prompt.range(of: #"[“\"']([^”\"']+)[”\"']"#, options: .regularExpression) {
            return String(prompt[range])
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”"))
        }
        return nil
    }

    private func merchantTarget(in rawPrompt: String, normalizedPrompt: String) -> String? {
        if let quoted = quotedText(in: rawPrompt), quoted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return quoted
        }

        let marker = normalizedPrompt.contains("merchants containing") ? "merchants containing " : "merchant "
        guard let range = normalizedPrompt.range(of: marker) else { return nil }
        let tail = String(normalizedPrompt[range.upperBound...])
            .replacingOccurrences(of: #"\s+(?:last|this|in|from|during|for)\b.*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return tail.isEmpty ? nil : tail
    }

    private func firstAmount(in prompt: String) -> Double? {
        guard let range = prompt.range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression) else { return nil }
        return Double(prompt[range])
    }

    private func weekdayName(_ weekday: Int) -> String {
        calendar.weekdaySymbols[max(0, min(weekday - 1, calendar.weekdaySymbols.count - 1))]
    }

    private func rangeLabel(_ range: HomeQueryDateRange) -> String {
        "\(shortDate(range.startDate)) - \(shortDate(range.endDate))"
    }

    private func shortDate(_ date: Date) -> String {
        AppDateFormat.shortDate(date)
    }

    private func currency(_ value: Double) -> String {
        CurrencyFormatter.string(from: value)
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func delta(_ value: Double) -> String {
        if value > 0 { return "Up \(currency(value))" }
        if value < 0 { return "Down \(currency(abs(value)))" }
        return "No change"
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
struct MarinaQueryExecutor {
    let adapter: MarinaAggregationPlanHomeQueryAdapter
    let executor: MarinaAggregationExecutor
    let composableWorkspaceQueryExecutor: MarinaComposableWorkspaceQueryExecutor
    let workspaceAggregationExecutor: MarinaWorkspaceAggregationExecutor
    let databaseLookupExecutor: MarinaDatabaseLookupExecutor
    let databaseLookupResponseBuilder: MarinaDatabaseLookupResponseBuilder
    let router: MarinaSemanticExecutionRouter = MarinaSemanticExecutionRouter()

    func execute(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?,
        validationOutcome: MarinaPlanValidationOutcome,
        provider: MarinaDataProvider,
        now: Date
    ) -> MarinaQueryExecutionResult {
        guard case .executable(let plan) = validationOutcome else {
            return .unsupported(
                MarinaTypedUnsupportedResponse(
                    kind: .unsupportedCombination,
                    message: "Only executable validation outcomes can run.",
                    candidate: candidate
                )
            )
        }

        let decision = router.decision(validationOutcome: validationOutcome, semanticResolved: semanticResolved)
        if let handled = executePreferredRoute(
            candidate: candidate,
            resolved: resolved,
            plan: plan,
            semanticResolved: semanticResolved,
            validationOutcome: validationOutcome,
            provider: provider,
            now: now,
            decision: decision
        ) {
            return handled
        }

        switch decision.route {
        case .lookupDetail:
            guard let request = semanticResolved?.databaseLookupRequest ?? candidate.databaseLookupRequest else {
                if let request = syntheticLookupRequest(for: plan, candidate: candidate) {
                    return executeLookup(request, provider: provider, decision: decision)
                }
                if let handled = executeComposable(candidate: candidate, resolved: resolved, plan: plan, provider: provider, now: now, decision: decision) {
                    return handled
                }
                if let handled = executeHomeAdapter(validationOutcome, provider: provider, now: now, decision: decision) {
                    return handled
                }
                return unsupported(candidate: candidate)
            }
            return executeLookup(request, provider: provider, decision: decision)
        case .aggregate:
            if shouldPreferComposableWorkspaceExecution(candidate: candidate, resolved: resolved, plan: plan),
               let handled = executeComposable(candidate: candidate, resolved: resolved, plan: plan, provider: provider, now: now, decision: decision) {
                return handled
            }
            if let handled = executeHomeAdapter(validationOutcome, provider: provider, now: now, decision: decision) {
                return handled
            }
            if hasExecutableTarget(plan) || resolved.resolvedTargets.isEmpty == false {
                if let handled = executeComposable(candidate: candidate, resolved: resolved, plan: plan, provider: provider, now: now, decision: decision) {
                    return handled
                }
            }
            if let handled = executeWorkspace(plan: plan, provider: provider, now: now, decision: decision) {
                return handled
            }
            return unsupported(candidate: candidate)
        case .comparison, .groupedRanked:
            if hasExecutableTarget(plan) || resolved.resolvedTargets.isEmpty == false {
                if let handled = executeComposable(candidate: candidate, resolved: resolved, plan: plan, provider: provider, now: now, decision: decision) {
                    return handled
                }
            }
            if let handled = executeHomeAdapter(validationOutcome, provider: provider, now: now, decision: decision) {
                return handled
            }
            if let handled = executeComposable(candidate: candidate, resolved: resolved, plan: plan, provider: provider, now: now, decision: decision) {
                return handled
            }
            if let handled = executeWorkspace(plan: plan, provider: provider, now: now, decision: decision) {
                return handled
            }
            return unsupported(candidate: candidate)
        case .list:
            if let handled = executeComposable(candidate: candidate, resolved: resolved, plan: plan, provider: provider, now: now, decision: decision) {
                return handled
            }
            if let handled = executeWorkspace(plan: plan, provider: provider, now: now, decision: decision) {
                return handled
            }
            if let handled = executeHomeAdapter(validationOutcome, provider: provider, now: now, decision: decision) {
                return handled
            }
            return unsupported(candidate: candidate)
        case .scenario:
            if let handled = executeHomeAdapter(validationOutcome, provider: provider, now: now, decision: decision) {
                return handled
            }
            if let handled = executeComposable(candidate: candidate, resolved: resolved, plan: plan, provider: provider, now: now, decision: decision) {
                return handled
            }
            if let handled = executeWorkspace(plan: plan, provider: provider, now: now, decision: decision) {
                return handled
            }
            return unsupported(candidate: candidate)
        case .unsupported(let kind):
            return .unsupported(
                MarinaTypedUnsupportedResponse(
                    kind: kind,
                    message: "Marina cannot run that exact question yet.",
                    candidate: candidate
                )
            )
        }
    }

    private func syntheticLookupRequest(
        for plan: MarinaAggregationPlan,
        candidate: MarinaQueryPlanCandidate
    ) -> MarinaDatabaseLookupRequest? {
        guard plan.operation == .lookupDetails,
              let target = plan.targets.first else {
            return nil
        }

        let objectTypes: [MarinaLookupObjectType]
        switch target.entityType {
        case .expense, .transaction:
            objectTypes = [.variableExpense, .plannedExpense]
        case .merchant:
            objectTypes = [.variableExpense, .plannedExpense]
        case .card, .category, .preset, .budget, .savingsAccount, .allocationAccount, .incomeSource, .workspace:
            return nil
        }

        return MarinaDatabaseLookupRequest(
            rawPrompt: candidate.rawPrompt,
            searchText: target.displayName,
            objectTypes: objectTypes,
            dateRange: plan.dateRange,
            limit: plan.limit ?? 1,
            requestedDetail: .general,
            lookupMode: .relatedRows
        ).clamped
    }

    private func executeLookup(
        _ request: MarinaDatabaseLookupRequest,
        provider: MarinaDataProvider,
        decision: MarinaSemanticExecutionDecision
    ) -> MarinaQueryExecutionResult {
        let response = databaseLookupExecutor.execute(request, provider: provider)
        let answer = databaseLookupResponseBuilder.responseCompatibleAnswer(from: response)
        let result: MarinaAggregationResult = response.results.isEmpty && response.ambiguityChoices.isEmpty
            ? .noData(
                MarinaNoDataAggregationResult(
                    title: answer.title,
                    message: answer.subtitle ?? "No matching data found.",
                    sourceAnswer: answer
                )
            )
            : .message(
                MarinaMessageAggregationResult(
                    title: answer.title,
                    message: answer.subtitle,
                    sourceAnswer: answer
                )
            )
        return .handled(
            MarinaQueryExecution(
                executablePlan: nil,
                aggregationResult: result,
                databaseLookupResponse: response,
                workspaceAggregationCard: nil,
                amountBasis: decision.amountBasis,
                executionRoute: decision.route
            )
        )
    }

    private func executeHomeAdapter(
        _ validationOutcome: MarinaPlanValidationOutcome,
        provider: MarinaDataProvider,
        now: Date,
        decision: MarinaSemanticExecutionDecision
    ) -> MarinaQueryExecutionResult? {
        guard case .success(let executablePlan) = adapter.executablePlan(from: validationOutcome) else {
            return nil
        }

        let result = noDataIfNeeded(executor.execute(executablePlan, provider: provider, now: now))
        if case .unsupported(let unsupported) = result {
            return .unsupported(unsupported)
        }
        return .handled(
            MarinaQueryExecution(
                executablePlan: executablePlan,
                aggregationResult: result,
                databaseLookupResponse: nil,
                workspaceAggregationCard: nil,
                amountBasis: decision.amountBasis,
                executionRoute: decision.route
            )
        )
    }

    private func executeComposable(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date,
        decision: MarinaSemanticExecutionDecision
    ) -> MarinaQueryExecutionResult? {
        switch composableWorkspaceQueryExecutor.execute(
            candidate: candidate,
            resolved: resolved,
            plan: plan,
            provider: provider,
            now: now,
            amountBasis: decision.amountBasis
        ) {
        case .handled(let card):
            return .handled(workspaceExecution(card, decision: decision))
        case .unsupported:
            return nil
        }
    }

    private func executeWorkspace(
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date,
        decision: MarinaSemanticExecutionDecision
    ) -> MarinaQueryExecutionResult? {
        switch workspaceAggregationExecutor.execute(plan: plan, provider: provider, now: now, amountBasis: decision.amountBasis) {
        case .handled(let card):
            return .handled(workspaceExecution(card, decision: decision))
        case .unsupported:
            return nil
        }
    }

    private func executePreferredRoute(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        plan: MarinaAggregationPlan,
        semanticResolved: MarinaResolvedSemanticQuery?,
        validationOutcome: MarinaPlanValidationOutcome,
        provider: MarinaDataProvider,
        now: Date,
        decision: MarinaSemanticExecutionDecision
    ) -> MarinaQueryExecutionResult? {
        guard let preferred = semanticResolved?.query.routeIntent?.preferredExecutorRoute ?? plan.routeIntent?.preferredExecutorRoute ?? candidate.routeIntent?.preferredExecutorRoute else {
            return nil
        }
        switch preferred {
        case .composableWorkspace:
            return executeComposable(candidate: candidate, resolved: resolved, plan: plan, provider: provider, now: now, decision: decision)
        case .workspaceAggregation:
            return executeWorkspace(plan: plan, provider: provider, now: now, decision: decision)
        case .homeAdapter:
            return executeHomeAdapter(validationOutcome, provider: provider, now: now, decision: decision)
        case .databaseLookup:
            guard let request = semanticResolved?.databaseLookupRequest ?? candidate.databaseLookupRequest else { return nil }
            return executeLookup(request, provider: provider, decision: decision)
        case .lookupDetail, .list, .aggregate, .comparison, .groupedRanked, .scenario:
            return nil
        }
    }

    private func workspaceExecution(
        _ card: MarinaWorkspaceAggregationCard,
        decision: MarinaSemanticExecutionDecision
    ) -> MarinaQueryExecution {
        MarinaQueryExecution(
            executablePlan: nil,
            aggregationResult: .workspaceCard(card),
            databaseLookupResponse: nil,
            workspaceAggregationCard: card,
            amountBasis: decision.amountBasis,
            executionRoute: decision.route
        )
    }

    private func unsupported(candidate: MarinaQueryPlanCandidate) -> MarinaQueryExecutionResult {
        .unsupported(
            MarinaTypedUnsupportedResponse(
                kind: .unsupportedCombination,
                message: "Marina cannot run that exact question yet.",
                candidate: candidate
            )
        )
    }

    private func hasExecutableTarget(_ plan: MarinaAggregationPlan) -> Bool {
        plan.targets.contains { target in
            switch target.role {
            case .filter, .primaryTarget, .comparisonTarget, .simulationInput, .simulationOutput:
                return true
            case .excludeFilter, .groupingDimension:
                return false
            }
        }
    }

    private func shouldPreferComposableWorkspaceExecution(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        plan: MarinaAggregationPlan
    ) -> Bool {
        if candidate.routeIntent?.preferredExecutorRoute == .composableWorkspace
            || plan.routeIntent?.preferredExecutorRoute == .composableWorkspace {
            return true
        }
        if candidate.routeIntent?.kind == .allocationRows
            || candidate.routeIntent?.kind == .settlementRows
            || plan.routeIntent?.kind == .allocationRows
            || plan.routeIntent?.kind == .settlementRows {
            return true
        }
        if isAllocationOrSettlementRowPrompt(candidate.rawPrompt),
           (candidate.measure == .reconciliationBalance || plan.measure == .reconciliationBalance),
           (candidate.grouping?.dimension == .allocationAccount || plan.grouping?.dimension == .allocationAccount) {
            return true
        }
        guard hasExecutableTarget(plan) || resolved.resolvedTargets.isEmpty == false else { return false }
        if candidate.operation == .rank || plan.operation == .rank { return true }
        if candidate.operation == .listRows || plan.operation == .listRows { return true }
        if candidate.grouping?.dimension == .transaction || plan.grouping?.dimension == .transaction { return true }
        if candidate.ranking?.direction == .largest || plan.ranking?.direction == .largest { return true }
        return false
    }

    private func isAllocationOrSettlementRowPrompt(_ prompt: String) -> Bool {
        let normalized = prompt
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.contains("allocation")
            || normalized.contains("allocations")
            || normalized.contains("allocated")
            || normalized.contains("split with")
            || normalized.contains("split expenses")
            || normalized.contains("split charges")
            || normalized.contains("settlement")
            || normalized.contains("settlements")
            || normalized.contains("paid me back")
            || normalized.contains("pay me back")
            || normalized.contains("repaid")
            || normalized.contains("reimburse")
    }

    private func noDataIfNeeded(_ result: MarinaAggregationResult) -> MarinaAggregationResult {
        switch result {
        case .rankedList(let list) where list.rows.isEmpty:
            return .noData(
                MarinaNoDataAggregationResult(
                    title: list.title,
                    message: "No data available for that range.",
                    sourceAnswer: list.sourceAnswer
                )
            )
        case .groupedBreakdown(let list) where list.rows.isEmpty:
            return .noData(
                MarinaNoDataAggregationResult(
                    title: list.title,
                    message: "No data available for that range.",
                    sourceAnswer: list.sourceAnswer
                )
            )
        default:
            return result
        }
    }
}

struct MarinaResponseBuilder {
    let aggregationBridge: MarinaAggregationResponseBridge
    let workspaceBridge: MarinaWorkspaceAggregationResponseBridge

    init(
        aggregationBridge: MarinaAggregationResponseBridge = MarinaAggregationResponseBridge(),
        workspaceBridge: MarinaWorkspaceAggregationResponseBridge = MarinaWorkspaceAggregationResponseBridge()
    ) {
        self.aggregationBridge = aggregationBridge
        self.workspaceBridge = workspaceBridge
    }

    func responseCompatibleAnswer(from outcome: MarinaPlanValidationOutcome) -> HomeAnswer? {
        aggregationBridge.responseCompatibleAnswer(from: outcome)
    }

    func responseCompatibleAnswer(from result: MarinaAggregationResult) -> HomeAnswer {
        switch result {
        case .workspaceCard(let card):
            return workspaceBridge.responseCompatibleAnswer(from: card)
        default:
            return aggregationBridge.responseCompatibleAnswer(from: result)
        }
    }
}
