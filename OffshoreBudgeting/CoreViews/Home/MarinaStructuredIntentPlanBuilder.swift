//
//  MarinaStructuredIntentPlanBuilder.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 4/15/26.
//

import Foundation

struct MarinaStructuredIntentPlanBuilder {
    enum QueryValidationFailure: String, Equatable {
        case missingMetric
        case missingDateRange
        case missingCategoryTarget
        case missingCardTarget
        case missingIncomeTarget
        case missingMerchantTarget
    }

    private let calendar: Calendar
    private let dateFormatter: DateFormatter
    private let nowProvider: () -> Date

    init(
        calendar: Calendar = .current,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.calendar = calendar
        self.nowProvider = nowProvider

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        self.dateFormatter = formatter
    }

    func buildRequest(
        from structuredIntent: MarinaStructuredIntent,
        prompt: String,
        defaultPeriodUnit: HomeQueryPeriodUnit,
        now: Date? = nil,
        priorQueryContext: MarinaPriorQueryContext = MarinaPriorQueryContext(
            lastQueryPlan: nil,
            lastMetric: nil,
            lastTargetName: nil,
            lastTargetType: nil,
            lastDateRange: nil,
            lastResultLimit: nil,
            lastPeriodUnit: nil
        )
    ) -> MarinaInterpretedRequest {
        switch structuredIntent {
        case .query(let queryIntent):
            return buildQueryRequest(
                from: queryIntent,
                prompt: prompt,
                defaultPeriodUnit: defaultPeriodUnit,
                now: now ?? nowProvider(),
                priorQueryContext: priorQueryContext
            )
        case .command(let commandIntent):
            return buildCommandRequest(from: commandIntent, prompt: prompt)
        case .clarification(let clarification):
            return .clarification(
                MarinaClarificationRequest(
                    subtitle: clarification.subtitle ?? "I need one more detail before I run this.",
                    reasons: genericClarificationReasons(clarification),
                    shouldRunBestEffort: clarification.shouldRunBestEffort,
                    queryPlan: nil,
                    commandPlan: nil
                ),
                source: .model
            )
        case .unresolved:
            return .unresolved
        }
    }

    private func buildQueryRequest(
        from queryIntent: MarinaStructuredQueryIntent,
        prompt: String,
        defaultPeriodUnit: HomeQueryPeriodUnit,
        now: Date,
        priorQueryContext: MarinaPriorQueryContext
    ) -> MarinaInterpretedRequest {
        let confidenceBand = HomeQueryConfidenceBand(rawValue: queryIntent.confidenceRaw ?? "") ?? .high
        let metric = resolvedMetric(
            from: queryIntent,
            prompt: prompt,
            confidenceBand: confidenceBand,
            priorQueryContext: priorQueryContext
        )

        guard let metric else {
            MarinaDebugLogger.log("query build failed: missing metric for prompt='\(prompt)' prior=\(priorQueryContext)")
            if let clarification = queryIntent.clarification, clarification.isMeaningful {
                return .clarification(
                    MarinaClarificationRequest(
                        subtitle: clarification.subtitle ?? "I need one more detail before I run this.",
                        reasons: queryClarificationReasons(clarification, metric: nil, prompt: prompt),
                        shouldRunBestEffort: clarification.shouldRunBestEffort,
                        queryPlan: nil,
                        commandPlan: nil
                    ),
                    source: .model
                )
            }
            return .unresolved
        }

        let basePlan = HomeQueryPlan(
            metric: metric,
            dateRange: resolveQueryDateRange(
                prompt: prompt,
                modelStart: queryIntent.dateStartISO8601,
                modelEnd: queryIntent.dateEndISO8601,
                defaultPeriodUnit: defaultPeriodUnit,
                now: now
            ),
            comparisonDateRange: resolveModelDateRange(
                start: queryIntent.comparisonDateStartISO8601,
                end: queryIntent.comparisonDateEndISO8601,
                now: now
            ),
            resultLimit: queryIntent.resultLimit,
            confidenceBand: confidenceBand,
            targetName: queryIntent.targetName,
            targetTypeRaw: queryIntent.targetTypeRaw,
            periodUnit: HomeQueryPeriodUnit(rawValue: queryIntent.periodUnitRaw ?? "") ?? defaultPeriodUnit
        )
        let plan = mergePriorContext(
            into: basePlan,
            queryIntent: queryIntent,
            prompt: prompt,
            confidenceBand: confidenceBand,
            priorQueryContext: priorQueryContext
        )
        MarinaDebugLogger.log("query merge result prompt='\(prompt)' plan=\(plan)")

        if let failure = validationFailure(for: plan, prompt: prompt) {
            MarinaDebugLogger.log("query validation failed prompt='\(prompt)' reason=\(failure.rawValue) plan=\(plan)")
            if let clarification = clarificationRequest(for: failure, plan: plan) {
                return .clarification(clarification, source: .model)
            }
            return .unresolved
        }

        if let clarification = queryIntent.clarification, clarification.isMeaningful {
            MarinaDebugLogger.log("ignoring model clarification for executable query prompt='\(prompt)' clarification=\(clarification)")
        }

        return .query(plan, source: .model)
    }

    func validationFailure(
        for plan: HomeQueryPlan,
        prompt: String
    ) -> QueryValidationFailure? {
        if requiresDateRange(plan.metric), plan.dateRange == nil, isPromptMissingDate(prompt) {
            return .missingDateRange
        }

        if requiresCategoryTarget(plan.metric), plan.targetName == nil {
            return .missingCategoryTarget
        }

        if requiresCardTarget(plan.metric), plan.targetName == nil {
            return .missingCardTarget
        }

        if requiresIncomeTarget(plan.metric), plan.targetName == nil {
            return .missingIncomeTarget
        }

        if requiresMerchantTarget(plan.metric), plan.targetName == nil {
            return .missingMerchantTarget
        }

        return nil
    }

    private func buildCommandRequest(
        from commandIntent: MarinaStructuredCommandIntent,
        prompt: String
    ) -> MarinaInterpretedRequest {
        guard let intentRaw = commandIntent.intentRaw,
              let intent = HomeAssistantCommandIntent(rawValue: intentRaw) else {
            if let clarification = commandIntent.clarification, clarification.isMeaningful {
                return .clarification(
                    MarinaClarificationRequest(
                        subtitle: clarification.subtitle ?? "I need one more detail before I run this.",
                        reasons: commandClarificationReasons(clarification),
                        shouldRunBestEffort: clarification.shouldRunBestEffort,
                        queryPlan: nil,
                        commandPlan: nil
                    ),
                    source: .model
                )
            }
            return .unresolved
        }

        let commandPlan = HomeAssistantCommandPlan(
            intent: intent,
            confidenceBand: HomeAssistantCommandConfidenceBand(rawValue: commandIntent.confidenceRaw ?? "") ?? .high,
            rawPrompt: prompt,
            amount: commandIntent.amount,
            originalAmount: commandIntent.originalAmount,
            date: makeDate(commandIntent.dateISO8601),
            dateRange: makeDateRange(start: commandIntent.dateRangeStartISO8601, end: commandIntent.dateRangeEndISO8601),
            notes: commandIntent.notes,
            source: commandIntent.source,
            cardName: commandIntent.cardName,
            categoryName: commandIntent.categoryName,
            entityName: commandIntent.entityName,
            updatedEntityName: commandIntent.updatedEntityName,
            isPlannedIncome: commandIntent.isPlannedIncome,
            categoryColorHex: commandIntent.categoryColorHex,
            categoryColorName: commandIntent.categoryColorName,
            cardThemeRaw: commandIntent.cardThemeRaw,
            cardEffectRaw: commandIntent.cardEffectRaw,
            recurrenceFrequencyRaw: commandIntent.recurrenceFrequencyRaw,
            recurrenceInterval: commandIntent.recurrenceInterval,
            weeklyWeekday: commandIntent.weeklyWeekday,
            monthlyDayOfMonth: commandIntent.monthlyDayOfMonth,
            monthlyIsLastDay: commandIntent.monthlyIsLastDay,
            yearlyMonth: commandIntent.yearlyMonth,
            yearlyDayOfMonth: commandIntent.yearlyDayOfMonth,
            recurrenceEndDate: makeDate(commandIntent.recurrenceEndDateISO8601),
            plannedExpenseAmountTarget: HomeAssistantPlannedExpenseAmountTarget(rawValue: commandIntent.plannedExpenseAmountTargetRaw ?? ""),
            attachAllCards: commandIntent.attachAllCards,
            attachAllPresets: commandIntent.attachAllPresets,
            selectedCardNames: commandIntent.selectedCardNames,
            selectedPresetTitles: commandIntent.selectedPresetTitles
        )

        if let clarification = commandIntent.clarification, clarification.isMeaningful {
            return .clarification(
                MarinaClarificationRequest(
                    subtitle: clarification.subtitle ?? "I need one more detail before I run this.",
                    reasons: commandClarificationReasons(clarification),
                    shouldRunBestEffort: clarification.shouldRunBestEffort,
                    queryPlan: nil,
                    commandPlan: commandPlan
                ),
                source: .model
            )
        }

        return .command(commandPlan, source: .model)
    }

    private func resolveQueryDateRange(
        prompt: String,
        modelStart: String?,
        modelEnd: String?,
        defaultPeriodUnit: HomeQueryPeriodUnit,
        now: Date
    ) -> HomeQueryDateRange? {
        let resolver = MarinaDateResolver(
            calendar: calendar,
            nowProvider: { now }
        )
        return resolver.resolve(
            input: prompt,
            modelStartISO8601: modelStart,
            modelEndISO8601: modelEnd,
            defaultPeriodUnit: defaultPeriodUnit
        )?.queryDateRange
    }

    private func resolveModelDateRange(
        start: String?,
        end: String?,
        now: Date
    ) -> HomeQueryDateRange? {
        let resolver = MarinaDateResolver(
            calendar: calendar,
            nowProvider: { now }
        )
        return resolver.resolveExplicitRange(start: start, end: end)?.queryDateRange
    }

    private func makeDateRange(start: String?, end: String?) -> HomeQueryDateRange? {
        guard let startDate = makeDate(start), let endDate = makeDate(end) else { return nil }
        return HomeQueryDateRange(startDate: startDate, endDate: endDate)
    }

    private func makeDate(_ rawValue: String?) -> Date? {
        guard let rawValue, rawValue.isEmpty == false else { return nil }
        return dateFormatter.date(from: rawValue)
    }

    private func resolvedMetric(
        from queryIntent: MarinaStructuredQueryIntent,
        prompt: String,
        confidenceBand: HomeQueryConfidenceBand,
        priorQueryContext: MarinaPriorQueryContext
    ) -> HomeQueryMetric? {
        let metricRaw = queryIntent.metricRaw?.trimmingCharacters(in: .whitespacesAndNewlines)
        MarinaDebugLogger.log("metric normalization raw='\(metricRaw ?? "nil")'")

        if let metric = normalizedMetric(from: metricRaw) {
            MarinaDebugLogger.log("metric normalization resolved='\(metric.rawValue)'")
            return metric
        }

        MarinaDebugLogger.log("metric normalization resolved='nil'")

        guard confidenceBand != .low,
              shouldInheritMetric(from: prompt, priorQueryContext: priorQueryContext) else {
            return nil
        }

        let inheritedMetric = priorQueryContext.lastQueryPlan?.metric ?? priorQueryContext.lastMetric
        MarinaDebugLogger.log("metric inherited from prior='\(inheritedMetric?.rawValue ?? "nil")'")
        return inheritedMetric
    }

    private func normalizedMetric(from rawValue: String?) -> HomeQueryMetric? {
        guard let rawValue, rawValue.isEmpty == false else { return nil }

        if let metric = HomeQueryMetric(rawValue: rawValue) {
            return metric
        }

        let normalized = rawValue
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))

        if let metric = HomeQueryMetric(rawValue: normalized) {
            return metric
        }

        switch normalized {
        case "total_spent", "spend_total", "spending", "spent":
            return .spendTotal
        default:
            return nil
        }
    }

    private func mergePriorContext(
        into plan: HomeQueryPlan,
        queryIntent: MarinaStructuredQueryIntent,
        prompt: String,
        confidenceBand: HomeQueryConfidenceBand,
        priorQueryContext: MarinaPriorQueryContext
    ) -> HomeQueryPlan {
        guard confidenceBand != .low,
              let priorPlan = priorQueryContext.lastQueryPlan ?? priorQueryContext.fallbackPlan else {
            return plan
        }

        var mergedPlan = plan
        let promptHasExplicitDate = promptContainsDateLanguage(prompt)
        let promptIsReferential = promptUsesReferentialCarryover(prompt)

        if queryIntent.targetName == nil,
           promptIsReferential {
            mergedPlan = mergedPlan.updating(targetName: .some(priorPlan.targetName))
        }

        if plan.dateRange == nil,
           promptHasExplicitDate == false,
           shouldInheritDateRange(from: prompt, priorQueryContext: priorQueryContext) {
            mergedPlan = mergedPlan.updating(dateRange: .some(priorPlan.dateRange))
        }

        if plan.comparisonDateRange == nil,
           promptHasExplicitDate == false,
           promptIsReferential {
            mergedPlan = mergedPlan.updating(comparisonDateRange: .some(priorPlan.comparisonDateRange))
        }

        if queryIntent.resultLimit == nil,
           promptIsReferential {
            mergedPlan = mergedPlan.updating(resultLimit: .some(priorPlan.resultLimit))
        }

        if queryIntent.periodUnitRaw == nil,
           shouldInheritPeriodUnit(from: prompt, priorQueryContext: priorQueryContext) {
            mergedPlan = mergedPlan.updating(periodUnit: .some(priorPlan.periodUnit))
        }

        if queryIntent.targetName == nil,
           mergedPlan.targetName == nil,
           priorQueryContext.lastTargetName != nil,
           promptUsesTargetCarryover(prompt) {
            mergedPlan = mergedPlan.updating(targetName: .some(priorQueryContext.lastTargetName))
        }

        return mergedPlan
    }

    private func clarificationRequest(
        for failure: QueryValidationFailure,
        plan: HomeQueryPlan
    ) -> MarinaClarificationRequest? {
        let reasons: [HomeAssistantClarificationReason]
        let subtitle: String

        switch failure {
        case .missingMetric:
            return nil
        case .missingDateRange:
            reasons = [.missingDate]
            subtitle = "Choose a date window so I can scope the query."
        case .missingCategoryTarget:
            reasons = [.missingCategoryTarget]
            subtitle = "Pick a category so I can run that query."
        case .missingCardTarget:
            reasons = [.missingCardTarget]
            subtitle = "Pick a card so I can run that query."
        case .missingIncomeTarget:
            reasons = [.missingIncomeSourceTarget]
            subtitle = "Pick an income source so I can run that query."
        case .missingMerchantTarget:
            reasons = [.missingMerchantTarget]
            subtitle = "Pick a merchant so I can run that query."
        }

        return MarinaClarificationRequest(
            subtitle: subtitle,
            reasons: reasons,
            shouldRunBestEffort: false,
            queryPlan: plan,
            commandPlan: nil
        )
    }

    private func queryClarificationReasons(
        _ clarification: MarinaStructuredClarification,
        metric: HomeQueryMetric?,
        prompt: String
    ) -> [HomeAssistantClarificationReason] {
        var resolved: [HomeAssistantClarificationReason] = clarification.missingFields.compactMap { field in
            switch field {
            case .date, .dateRange:
                return .missingDate
            case .comparisonDateRange:
                return .missingComparisonDate
            case .targetName:
                guard let metric else { return .lowConfidenceLanguage }
                if requiresCategoryTarget(metric) { return .missingCategoryTarget }
                if requiresCardTarget(metric) { return .missingCardTarget }
                if requiresIncomeTarget(metric) { return .missingIncomeSourceTarget }
                if requiresMerchantTarget(metric) { return .missingMerchantTarget }
                return .lowConfidenceLanguage
            default:
                return .lowConfidenceLanguage
            }
        }

        if clarification.ambiguities.isEmpty == false && resolved.isEmpty {
            resolved.append(.lowConfidenceLanguage)
        }

        if resolved.isEmpty, clarification.subtitle?.isEmpty == false {
            resolved.append(.lowConfidenceLanguage)
        }

        if let metric, resolved.contains(.missingDate) == false,
           requiresDateRange(metric),
           isPromptMissingDate(prompt) {
            resolved.append(.missingDate)
        }

        return uniqueReasons(resolved)
    }

    private func commandClarificationReasons(
        _ clarification: MarinaStructuredClarification
    ) -> [HomeAssistantClarificationReason] {
        var resolved: [HomeAssistantClarificationReason] = []

        if clarification.missingFields.contains(.cardName) {
            resolved.append(.missingCardTarget)
        }
        if clarification.missingFields.contains(.categoryName) {
            resolved.append(.missingCategoryTarget)
        }
        if clarification.missingFields.contains(.source) {
            resolved.append(.missingIncomeSourceTarget)
        }

        if resolved.isEmpty, clarification.isMeaningful {
            resolved.append(.lowConfidenceLanguage)
        }

        return uniqueReasons(resolved)
    }

    private func genericClarificationReasons(
        _ clarification: MarinaStructuredClarification
    ) -> [HomeAssistantClarificationReason] {
        if clarification.missingFields.contains(.date) || clarification.missingFields.contains(.dateRange) {
            return [.missingDate]
        }
        if clarification.missingFields.contains(.comparisonDateRange) {
            return [.missingComparisonDate]
        }
        return [.lowConfidenceLanguage]
    }

    private func inferredQueryClarification(
        for plan: HomeQueryPlan,
        prompt: String
    ) -> MarinaStructuredClarification? {
        guard requiresDateRange(plan.metric), plan.dateRange == nil, isPromptMissingDate(prompt) else {
            return nil
        }

        return MarinaStructuredClarification(
            subtitle: "Choose a date window so I can scope the query.",
            missingFields: [.dateRange],
            ambiguities: [],
            shouldRunBestEffort: false
        )
    }

    private func requiresDateRange(_ metric: HomeQueryMetric) -> Bool {
        switch metric {
        case .presetHighestCost, .presetTopCategory, .presetCategorySpend:
            return false
        case .savingsAverageRecentPeriods, .incomeSourceShareTrend, .categorySpendShareTrend:
            return false
        case .overview, .spendTotal, .categorySpendTotal, .spendAveragePerPeriod, .topCategories, .monthComparison, .categoryMonthComparison, .cardMonthComparison, .incomeSourceMonthComparison, .merchantMonthComparison, .largestTransactions, .cardSpendTotal, .cardVariableSpendingHabits, .incomeAverageActual, .savingsStatus, .incomeSourceShare, .categorySpendShare, .presetDueSoon, .categoryPotentialSavings, .categoryReallocationGuidance, .safeSpendToday, .forecastSavings, .nextPlannedExpense, .spendTrendsSummary, .cardSnapshotSummary, .merchantSpendTotal, .merchantSpendSummary, .topMerchants, .topCategoryChanges, .topCardChanges:
            return true
        }
    }

    private func isPromptMissingDate(_ prompt: String) -> Bool {
        promptContainsDateLanguage(prompt) == false
    }

    private func promptContainsDateLanguage(_ prompt: String) -> Bool {
        let normalized = prompt
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let datePattern = "\\b(today|yesterday|week|month|year|quarter|january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sep|sept|october|oct|november|nov|december|dec|q[1-4]|\\d{4}-\\d{1,2}-\\d{1,2}|\\d{4})\\b"
        return normalized.range(of: datePattern, options: .regularExpression) != nil
    }

    private func shouldInheritMetric(
        from prompt: String,
        priorQueryContext: MarinaPriorQueryContext
    ) -> Bool {
        guard priorQueryContext.hasContext else { return false }
        let normalized = normalizedPrompt(prompt)
        if normalized.isEmpty {
            return false
        }

        let continuationPhrases = [
            "how about", "what about", "and", "same", "again", "instead", "for that", "for this"
        ]
        let tokenCount = normalized.split(separator: " ").count
        return continuationPhrases.contains(where: normalized.contains) || tokenCount <= 4
    }

    private func shouldInheritDateRange(
        from prompt: String,
        priorQueryContext: MarinaPriorQueryContext
    ) -> Bool {
        guard priorQueryContext.lastDateRange != nil else { return false }
        return promptUsesReferentialCarryover(prompt) || normalizedPrompt(prompt).split(separator: " ").count <= 3
    }

    private func shouldInheritPeriodUnit(
        from prompt: String,
        priorQueryContext: MarinaPriorQueryContext
    ) -> Bool {
        guard priorQueryContext.lastPeriodUnit != nil || priorQueryContext.lastQueryPlan?.periodUnit != nil else {
            return false
        }
        return promptUsesReferentialCarryover(prompt) || normalizedPrompt(prompt).split(separator: " ").count <= 4
    }

    private func promptUsesTargetCarryover(_ prompt: String) -> Bool {
        let normalized = normalizedPrompt(prompt)
        let phrases = ["same", "that", "this", "what about", "how about", "again"]
        return phrases.contains(where: normalized.contains)
    }

    private func promptUsesReferentialCarryover(_ prompt: String) -> Bool {
        let normalized = normalizedPrompt(prompt)
        let phrases = ["same", "that", "this", "what about", "how about", "again", "instead"]
        return phrases.contains(where: normalized.contains)
    }

    private func normalizedPrompt(_ prompt: String) -> String {
        prompt
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func uniqueReasons(
        _ reasons: [HomeAssistantClarificationReason]
    ) -> [HomeAssistantClarificationReason] {
        var seen: Set<HomeAssistantClarificationReason> = []
        return reasons.filter { seen.insert($0).inserted }
    }

    private func requiresCategoryTarget(_ metric: HomeQueryMetric) -> Bool {
        metric == .categorySpendTotal
            || metric == .categorySpendShare
            || metric == .categorySpendShareTrend
            || metric == .categoryPotentialSavings
            || metric == .categoryReallocationGuidance
            || metric == .categoryMonthComparison
            || metric == .presetCategorySpend
    }

    private func requiresCardTarget(_ metric: HomeQueryMetric) -> Bool {
        metric == .cardSpendTotal
            || metric == .cardVariableSpendingHabits
            || metric == .cardMonthComparison
            || metric == .cardSnapshotSummary
            || metric == .topCardChanges
    }

    private func requiresIncomeTarget(_ metric: HomeQueryMetric) -> Bool {
        metric == .incomeAverageActual
            || metric == .incomeSourceShare
            || metric == .incomeSourceShareTrend
            || metric == .incomeSourceMonthComparison
    }

    private func requiresMerchantTarget(_ metric: HomeQueryMetric) -> Bool {
        metric == .merchantSpendTotal
            || metric == .merchantSpendSummary
            || metric == .merchantMonthComparison
    }
}

private extension MarinaPriorQueryContext {
    var fallbackPlan: HomeQueryPlan? {
        guard let metric = lastMetric ?? lastQueryPlan?.metric else { return nil }
        return HomeQueryPlan(
            metric: metric,
            dateRange: lastDateRange ?? lastQueryPlan?.dateRange,
            comparisonDateRange: lastQueryPlan?.comparisonDateRange,
            resultLimit: lastResultLimit ?? lastQueryPlan?.resultLimit,
            confidenceBand: .high,
            targetName: lastTargetName ?? lastQueryPlan?.targetName,
            targetTypeRaw: lastQueryPlan?.targetTypeRaw,
            periodUnit: lastPeriodUnit ?? lastQueryPlan?.periodUnit
        )
    }
}

private extension MarinaStructuredClarification {
    var isMeaningful: Bool {
        subtitle?.isEmpty == false || missingFields.isEmpty == false || ambiguities.isEmpty == false
    }
}
