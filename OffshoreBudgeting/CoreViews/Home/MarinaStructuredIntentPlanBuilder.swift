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
            guard clarification.isActionable else {
                MarinaDebugLogger.log("discarding non-actionable model clarification prompt='\(prompt)' clarification=\(clarification)")
                return .unresolved
            }
            return .clarification(
                MarinaClarificationRequest(
                    subtitle: clarification.subtitle ?? "I need one more detail before I run this.",
                    reasons: genericClarificationReasons(clarification),
                    shouldRunBestEffort: clarification.shouldRunBestEffort,
                    queryPlan: nil,
                    commandPlan: nil,
                    isActionable: clarification.isActionable
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
            if let clarification = queryIntent.clarification, clarification.isActionable {
                return .clarification(
                    MarinaClarificationRequest(
                        subtitle: clarification.subtitle ?? "I need one more detail before I run this.",
                        reasons: queryClarificationReasons(clarification, metric: nil, prompt: prompt),
                        shouldRunBestEffort: clarification.shouldRunBestEffort,
                        queryPlan: nil,
                        commandPlan: nil,
                        isActionable: clarification.isActionable
                    ),
                    source: .model
                )
            }
            return .unresolved
        }

        let promptComparisonRanges = resolvePromptComparisonDateRanges(
            prompt: prompt,
            defaultPeriodUnit: defaultPeriodUnit,
            now: now
        )
        let basePlan = HomeQueryPlan(
            metric: metric,
            dateRange: resolvePrimaryDateRange(
                prompt: prompt,
                queryIntent: queryIntent,
                defaultPeriodUnit: defaultPeriodUnit,
                now: now,
                promptComparisonRanges: promptComparisonRanges
            ),
            comparisonDateRange: resolveComparisonDateRange(
                queryIntent: queryIntent,
                promptComparisonRanges: promptComparisonRanges,
                now: now
            ),
            resultLimit: queryIntent.resultLimit,
            confidenceBand: confidenceBand,
            targetName: queryIntent.targetName,
            targetTypeRaw: queryIntent.targetTypeRaw,
            periodUnit: HomeQueryPeriodUnit(rawValue: queryIntent.periodUnitRaw ?? "") ?? defaultPeriodUnit
        )
        MarinaDebugLogger.log("query raw plan prompt='\(prompt)' plan=\(basePlan)")
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

        if let clarification = queryIntent.clarification, clarification.isActionable {
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
            if let clarification = commandIntent.clarification, clarification.isActionable {
                return .clarification(
                    MarinaClarificationRequest(
                        subtitle: clarification.subtitle ?? "I need one more detail before I run this.",
                        reasons: commandClarificationReasons(clarification),
                        shouldRunBestEffort: clarification.shouldRunBestEffort,
                        queryPlan: nil,
                        commandPlan: nil,
                        isActionable: clarification.isActionable
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

        if let clarification = commandIntent.clarification, clarification.isActionable {
            return .clarification(
                MarinaClarificationRequest(
                    subtitle: clarification.subtitle ?? "I need one more detail before I run this.",
                    reasons: commandClarificationReasons(clarification),
                    shouldRunBestEffort: clarification.shouldRunBestEffort,
                    queryPlan: nil,
                    commandPlan: commandPlan,
                    isActionable: clarification.isActionable
                ),
                source: .model
            )
        }

        return .command(commandPlan, source: .model)
    }

    private func resolvePrimaryDateRange(
        prompt: String,
        queryIntent: MarinaStructuredQueryIntent,
        defaultPeriodUnit: HomeQueryPeriodUnit,
        now: Date,
        promptComparisonRanges: (primary: HomeQueryDateRange, comparison: HomeQueryDateRange)?
    ) -> HomeQueryDateRange? {
        if let modelRange = resolveModelDateRange(
            start: queryIntent.dateStartISO8601,
            end: queryIntent.dateEndISO8601,
            now: now
        ) {
            return modelRange
        }

        if let promptComparisonRanges {
            return promptComparisonRanges.primary
        }

        let resolver = MarinaDateResolver(
            calendar: calendar,
            nowProvider: { now }
        )
        return resolver.resolveTextRange(
            prompt,
            defaultPeriodUnit: defaultPeriodUnit
        )?.queryDateRange
    }

    private func resolveComparisonDateRange(
        queryIntent: MarinaStructuredQueryIntent,
        promptComparisonRanges: (primary: HomeQueryDateRange, comparison: HomeQueryDateRange)?,
        now: Date
    ) -> HomeQueryDateRange? {
        if let modelRange = resolveModelDateRange(
            start: queryIntent.comparisonDateStartISO8601,
            end: queryIntent.comparisonDateEndISO8601,
            now: now
        ) {
            return modelRange
        }

        return promptComparisonRanges?.comparison
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

    private func resolvePromptComparisonDateRanges(
        prompt: String,
        defaultPeriodUnit: HomeQueryPeriodUnit,
        now: Date
    ) -> (primary: HomeQueryDateRange, comparison: HomeQueryDateRange)? {
        let normalized = normalizedPrompt(prompt)
        let candidatePairs: [(String, String)] = [
            capturedComparisonSnippets(
                normalizedPrompt: normalized,
                pattern: "\\bfrom\\s+(.+?)\\s+to\\s+(.+)$"
            ),
            capturedComparisonSnippets(
                normalizedPrompt: normalized,
                pattern: "\\bbetween\\s+(.+?)\\s+and\\s+(.+)$"
            ),
            capturedComparisonSnippets(
                normalizedPrompt: normalized,
                pattern: "\\bcompare\\s+(.+?)\\s+(?:vs|versus)\\s+(.+)$"
            ),
            comparisonSnippetsSeparatedByTo(normalizedPrompt: normalized)
        ].compactMap { $0 }

        let resolver = MarinaDateResolver(
            calendar: calendar,
            nowProvider: { now }
        )

        for (firstSnippet, secondSnippet) in candidatePairs {
            if let specialCase = resolveRelativeComparisonPair(
                firstSnippet: firstSnippet,
                secondSnippet: secondSnippet,
                now: now
            ) {
                MarinaDebugLogger.log(
                    "query prompt comparison ranges special-case prompt='\(prompt)' primary=\(specialCase.primary) comparison=\(specialCase.comparison)"
                )
                return specialCase
            }

            guard let firstRange = resolver.resolveTextRange(firstSnippet, defaultPeriodUnit: defaultPeriodUnit)?.queryDateRange,
                  let secondRange = resolver.resolveTextRange(secondSnippet, defaultPeriodUnit: defaultPeriodUnit)?.queryDateRange,
                  firstRange != secondRange else {
                continue
            }
            MarinaDebugLogger.log(
                "query prompt comparison ranges prompt='\(prompt)' primary=\(firstRange) comparison=\(secondRange)"
            )
            return (firstRange, secondRange)
        }

        return nil
    }

    private func resolveRelativeComparisonPair(
        firstSnippet: String,
        secondSnippet: String,
        now: Date
    ) -> (primary: HomeQueryDateRange, comparison: HomeQueryDateRange)? {
        let first = normalizedPrompt(firstSnippet)
        let second = normalizedPrompt(secondSnippet)

        if first.contains("last week"), second.contains("previous week"),
           let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now) {
            let lastWeekAnchor = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeek.start) ?? currentWeek.start
            let previousWeekAnchor = calendar.date(byAdding: .weekOfYear, value: -2, to: currentWeek.start) ?? currentWeek.start
            return (
                fullWeekRange(containing: lastWeekAnchor),
                fullWeekRange(containing: previousWeekAnchor)
            )
        }

        return nil
    }

    private func fullWeekRange(containing date: Date) -> HomeQueryDateRange {
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: date)
        let start = weekInterval?.start ?? calendar.startOfDay(for: date)
        let endBase = weekInterval?.end ?? start
        let end = calendar.date(byAdding: .second, value: -1, to: endBase) ?? endBase
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func capturedComparisonSnippets(
        normalizedPrompt: String,
        pattern: String
    ) -> (String, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let fullRange = NSRange(normalizedPrompt.startIndex..., in: normalizedPrompt)
        guard let match = regex.firstMatch(in: normalizedPrompt, options: [], range: fullRange),
              match.numberOfRanges == 3,
              let firstRange = Range(match.range(at: 1), in: normalizedPrompt),
              let secondRange = Range(match.range(at: 2), in: normalizedPrompt) else {
            return nil
        }

        return (
            String(normalizedPrompt[firstRange]),
            String(normalizedPrompt[secondRange])
        )
    }

    private func comparisonSnippetsSeparatedByTo(
        normalizedPrompt: String
    ) -> (String, String)? {
        guard normalizedPrompt.contains("compare"),
              let separatorRange = normalizedPrompt.range(of: " to ") else {
            return nil
        }

        let leadingSegment = String(normalizedPrompt[..<separatorRange.lowerBound])
        let trailingSegment = String(normalizedPrompt[separatorRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trailingSegment.isEmpty == false else { return nil }

        let prefixes = [
            "compare spending in ",
            "compare spending ",
            "compare spend in ",
            "compare spend ",
            "compare income in ",
            "compare income ",
            "compare expenses in ",
            "compare expenses ",
            "compare my ",
            "compare ",
            "what did i spend on ",
            "what did i spend "
        ]

        guard let matchedPrefix = prefixes.first(where: { leadingSegment.hasPrefix($0) }) else {
            return nil
        }

        let firstSnippet = String(leadingSegment.dropFirst(matchedPrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard firstSnippet.isEmpty == false else { return nil }

        return (firstSnippet, trailingSegment)
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
        MarinaDebugLogger.log(
            "query merge start prompt='\(prompt)' explicitDate=\(promptHasExplicitDate) referential=\(promptIsReferential) priorDate=\(String(describing: priorPlan.dateRange)) priorComparison=\(String(describing: priorPlan.comparisonDateRange)) basePlan=\(plan)"
        )

        if queryIntent.targetName == nil,
           promptIsReferential {
            mergedPlan = mergedPlan.updating(targetName: .some(priorPlan.targetName))
        }

        if plan.dateRange == nil,
           promptHasExplicitDate == false,
           shouldInheritDateRange(from: prompt, priorQueryContext: priorQueryContext) {
            mergedPlan = mergedPlan.updating(dateRange: .some(priorPlan.dateRange))
            MarinaDebugLogger.log("query merge inherited dateRange prompt='\(prompt)' inherited=\(String(describing: priorPlan.dateRange))")
        }

        if plan.comparisonDateRange == nil,
           promptHasExplicitDate == false,
           promptIsReferential {
            mergedPlan = mergedPlan.updating(comparisonDateRange: .some(priorPlan.comparisonDateRange))
            MarinaDebugLogger.log("query merge inherited comparisonDateRange prompt='\(prompt)' inherited=\(String(describing: priorPlan.comparisonDateRange))")
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
            commandPlan: nil,
            isActionable: reasons.contains(where: \.requiresUserResolution)
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

        let explicitPhrases = [
            "today", "yesterday", "this week", "current week", "last week", "previous week",
            "this month", "current month", "month to date", "last month", "previous month",
            "this year", "current year", "year to date", "last year", "previous year",
            "from ", "between "
        ]
        if explicitPhrases.contains(where: normalized.contains) {
            return true
        }

        let datePattern = "\\b(week|month|year|quarter|january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sep|sept|october|oct|november|nov|december|dec|q[1-4]|\\d{4}-\\d{1,2}-\\d{1,2}|\\d{4})\\b"
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
