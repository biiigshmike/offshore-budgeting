import Foundation

struct MarinaQueryRecoveryPolicy {
    func canonicalized(
        candidate: MarinaQueryPlanCandidate,
        explicitConstraints: MarinaExplicitPromptConstraints,
        now: Date,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> MarinaQueryPlanCandidate {
        guard candidate.source == .foundationModels else { return candidate }

        let prompt = normalized(candidate.rawPrompt)
        var operation = candidate.operation
        var measure = candidate.measure
        var grouping = candidate.grouping
        var ranking = candidate.ranking
        var limit = candidate.limit
        var responseShapeHint = candidate.responseShapeHint
        var timeScopes = candidate.timeScopes
        var insightIntent = candidate.insightIntent
        let repairedShape: Bool

        if insightIntent == nil {
            insightIntent = inferredInsightIntent(from: prompt)
        }

        if isBiggestOffendersPrompt(prompt) {
            operation = .rank
            if grouping?.dimension == .merchant {
                measure = .spend
            } else {
                measure = .transactionAmount
                grouping = MarinaGroupingCandidate(dimension: .transaction, rawText: "biggest offenders")
            }
            ranking = MarinaRankingCandidate(direction: .largest, limit: limit ?? 5, rawText: "biggest offenders")
            limit = limit ?? 5
            responseShapeHint = .rankedList
            insightIntent = insightIntent ?? .multiPartContributors
        }

        if isSoftComparisonPrompt(prompt) {
            operation = .compare
            measure = .spend
            responseShapeHint = .comparison
            insightIntent = insightIntent ?? .changeSummary
            timeScopes = repairedComparisonScopes(
                existingScopes: timeScopes,
                prompt: prompt,
                now: now
            )
        }

        if isPlannedExpenseRowsPrompt(prompt) {
            operation = .listRows
            measure = .presetAmount
            grouping = MarinaGroupingCandidate(dimension: .transaction, rawText: "planned expenses")
            ranking = MarinaRankingCandidate(direction: .newest, limit: limit ?? 10, rawText: "due")
            limit = limit ?? 10
            responseShapeHint = .rankedList
            timeScopes = repairedPrimaryDateScopes(
                existingScopes: timeScopes,
                prompt: prompt,
                now: now,
                defaultPeriodUnit: defaultPeriodUnit
            )
        }

        if isPresetTemplateRowsPrompt(prompt) {
            operation = .listRows
            measure = .presetAmount
            grouping = MarinaGroupingCandidate(dimension: .preset, rawText: "presets")
            ranking = MarinaRankingCandidate(direction: .newest, limit: limit ?? 10, rawText: "presets")
            limit = limit ?? 10
            responseShapeHint = .rankedList
        }

        if isBudgetInventoryPrompt(prompt) {
            operation = .listRows
            measure = .remainingBudget
            responseShapeHint = .rankedList
        }

        if isSavingsActivityPrompt(prompt) {
            operation = .listRows
            measure = .savingsMovement
            grouping = MarinaGroupingCandidate(dimension: .savingsLedgerEntry, rawText: "activity")
            ranking = MarinaRankingCandidate(direction: .newest, limit: limit ?? 10, rawText: "activity")
            limit = limit ?? 10
            responseShapeHint = .rankedList
        }

        repairedShape = operation != candidate.operation
            || measure != candidate.measure
            || grouping != candidate.grouping
            || ranking != candidate.ranking
            || limit != candidate.limit
            || responseShapeHint != candidate.responseShapeHint
            || timeScopes != candidate.timeScopes
            || insightIntent != candidate.insightIntent

        guard repairedShape else { return candidate }
        guard preservesExplicitConstraints(
            explicitConstraints,
            original: candidate,
            operation: operation,
            timeScopes: timeScopes,
            ranking: ranking,
            limit: limit
        ) else {
            return candidate
        }

        return copy(
            candidate,
            operation: operation,
            measure: measure,
            timeScopes: timeScopes,
            grouping: grouping,
            ranking: ranking,
            limit: limit,
            responseShapeHint: responseShapeHint,
            unsupportedHint: nil,
            insightIntent: insightIntent
        )
    }

    func unsupportedTitle(for unsupported: MarinaTypedUnsupportedResponse) -> String {
        switch unsupported.kind {
        case .unsupportedOperation:
            return "I can answer this a different way"
        case .unsupportedTargetType, .unsupportedCombination, .unsupportedSimulation, .unsupportedDateShape:
            return "I need a narrower query"
        }
    }

    private func inferredInsightIntent(from prompt: String) -> MarinaInsightIntent? {
        if isBiggestOffendersPrompt(prompt) {
            return .multiPartContributors
        }

        if prompt.contains("why higher")
            || prompt.contains("why is this higher")
            || prompt.contains("why is it higher")
            || (prompt.contains("why is") && prompt.contains("higher")) {
            return .contributorAnalysis
        }

        if prompt.contains("what changed")
            || containsAnyWholePhrase(["worse", "higher", "lower", "changed"], in: prompt) {
            return .changeSummary
        }

        if containsAnyWholePhrase(["weird", "weirdly", "normal", "unusual", "lately"], in: prompt) {
            return .normalityCheck
        }

        return nil
    }

    private func isSoftComparisonPrompt(_ prompt: String) -> Bool {
        prompt.contains("what changed")
            || containsAnyWholePhrase(["worse", "higher", "lower", "changed"], in: prompt)
    }

    private func isBiggestOffendersPrompt(_ prompt: String) -> Bool {
        prompt.contains("biggest offender")
            || prompt.contains("biggest offenders")
    }

    private func isPlannedExpenseRowsPrompt(_ prompt: String) -> Bool {
        if prompt.contains("planned expense") || prompt.contains("planned expenses") {
            return true
        }
        return (prompt.contains("preset") || prompt.contains("presets"))
            && (prompt.contains("due") || prompt.contains("upcoming") || prompt.contains("next month") || prompt.contains("this month"))
    }

    private func isPresetTemplateRowsPrompt(_ prompt: String) -> Bool {
        guard prompt.contains("preset") || prompt.contains("presets") else { return false }
        guard isPlannedExpenseRowsPrompt(prompt) == false else { return false }
        return prompt.hasPrefix("show ") || prompt.hasPrefix("list ") || prompt.contains("active presets")
    }

    private func isBudgetInventoryPrompt(_ prompt: String) -> Bool {
        guard prompt.contains("budget") || prompt.contains("budgets") else { return false }
        return prompt.contains("upcoming")
            || prompt.contains("future")
            || prompt.contains("what are my budgets")
            || prompt.contains("show budgets")
            || prompt.contains("show my budgets")
            || prompt.contains("list budgets")
    }

    private func isSavingsActivityPrompt(_ prompt: String) -> Bool {
        (prompt.contains("savings") || prompt.contains("saving"))
            && (prompt.contains("activity") || prompt.contains("ledger") || prompt.contains("movements") || prompt.contains("transactions"))
    }

    private func repairedComparisonScopes(
        existingScopes: [MarinaUnresolvedTimeScope],
        prompt: String,
        now: Date
    ) -> [MarinaUnresolvedTimeScope] {
        var scopes = existingScopes
        let primaryRange = scopes.first { $0.role == .primary }?.resolvedRangeHint
            ?? scopes.first { $0.role == .lookbackWindow }?.resolvedRangeHint
            ?? currentMonthRange(containing: now)
        let comparisonRange = scopes.first { $0.role == .comparison }?.resolvedRangeHint
            ?? (containsWholePhrase("last month", in: prompt)
                ? previousMonthRange(before: primaryRange)
                : previousEquivalentRange(to: primaryRange))

        if scopes.contains(where: { $0.role == .primary || $0.role == .lookbackWindow }) == false {
            scopes.append(
                MarinaUnresolvedTimeScope(
                    role: .primary,
                    rawText: containsWholePhrase("this month", in: prompt) ? "this month" : nil,
                    resolvedRangeHint: primaryRange,
                    periodUnitHint: .month
                )
            )
        }

        if scopes.contains(where: { $0.role == .comparison }) == false {
            scopes.append(
                MarinaUnresolvedTimeScope(
                    role: .comparison,
                    rawText: containsWholePhrase("last month", in: prompt) ? "last month" : "previous period",
                    resolvedRangeHint: comparisonRange,
                    periodUnitHint: .month
                )
            )
        }

        return scopes
    }

    private func repairedPrimaryDateScopes(
        existingScopes: [MarinaUnresolvedTimeScope],
        prompt: String,
        now: Date,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> [MarinaUnresolvedTimeScope] {
        guard existingScopes.contains(where: { $0.role == .primary }) == false else {
            return existingScopes
        }
        guard let rawText = primaryDatePhrase(in: prompt),
              let range = MarinaDateResolver(
                calendar: Calendar(identifier: .gregorian),
                nowProvider: { now }
              ).resolve(
                input: rawText,
                modelStartISO8601: nil,
                modelEndISO8601: nil,
                defaultPeriodUnit: defaultPeriodUnit
              )?.queryDateRange else {
            return existingScopes
        }
        var scopes = existingScopes
        scopes.append(
            MarinaUnresolvedTimeScope(
                role: .primary,
                rawText: rawText,
                resolvedRangeHint: range,
                periodUnitHint: defaultPeriodUnit
            )
        )
        return scopes
    }

    private func preservesExplicitConstraints(
        _ constraints: MarinaExplicitPromptConstraints,
        original: MarinaQueryPlanCandidate,
        operation: MarinaCandidateOperation?,
        timeScopes: [MarinaUnresolvedTimeScope],
        ranking: MarinaRankingCandidate?,
        limit: Int?
    ) -> Bool {
        if constraints.hasDateConstraint, timeScopes.isEmpty {
            return false
        }
        if let explicitLimit = constraints.limit,
           limit != explicitLimit,
           original.limit != explicitLimit,
           ranking?.limit != explicitLimit,
           original.ranking?.limit != explicitLimit {
            return false
        }
        if let explicitSort = constraints.sort,
           ranking?.direction != explicitSort,
           original.ranking?.direction != explicitSort {
            return false
        }
        if operation == nil, original.operation != nil {
            return false
        }
        return true
    }

    private func currentMonthRange(containing date: Date) -> HomeQueryDateRange {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? start
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func previousMonthRange(before range: HomeQueryDateRange) -> HomeQueryDateRange {
        let calendar = Calendar(identifier: .gregorian)
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: range.startDate)) ?? range.startDate
        let previousStart = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
        let previousEnd = calendar.date(byAdding: DateComponents(second: -1), to: monthStart) ?? previousStart
        return HomeQueryDateRange(startDate: previousStart, endDate: previousEnd)
    }

    private func previousEquivalentRange(to range: HomeQueryDateRange) -> HomeQueryDateRange {
        if isFullCalendarMonth(range) {
            return previousMonthRange(before: range)
        }
        let duration = max(range.endDate.timeIntervalSince(range.startDate), 0)
        let previousEnd = range.startDate.addingTimeInterval(-1)
        let previousStart = previousEnd.addingTimeInterval(-duration)
        return HomeQueryDateRange(startDate: previousStart, endDate: previousEnd)
    }

    private func isFullCalendarMonth(_ range: HomeQueryDateRange) -> Bool {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: range.startDate)) ?? range.startDate
        let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? start
        return abs(range.startDate.timeIntervalSince(start)) < 1
            && abs(range.endDate.timeIntervalSince(end)) < 1
    }

    private func copy(
        _ candidate: MarinaQueryPlanCandidate,
        operation: MarinaCandidateOperation?,
        measure: MarinaCandidateMeasure?,
        timeScopes: [MarinaUnresolvedTimeScope],
        grouping: MarinaGroupingCandidate?,
        ranking: MarinaRankingCandidate?,
        limit: Int?,
        responseShapeHint: MarinaResponseShapeHint?,
        unsupportedHint: MarinaUnsupportedHint?,
        insightIntent: MarinaInsightIntent?
    ) -> MarinaQueryPlanCandidate {
        MarinaQueryPlanCandidate(
            requestFamily: candidate.requestFamily,
            source: candidate.source,
            rawPrompt: candidate.rawPrompt,
            operation: operation,
            measure: measure,
            entityMentions: candidate.entityMentions,
            timeScopes: timeScopes,
            grouping: grouping,
            ranking: ranking,
            limit: limit,
            responseShapeHint: responseShapeHint,
            confidence: candidate.confidence,
            unsupportedHint: unsupportedHint,
            databaseLookupRequest: candidate.databaseLookupRequest,
            semanticCommand: candidate.semanticCommand,
            requestShape: candidate.requestShape,
            insightIntent: insightIntent,
            softTimeHint: candidate.softTimeHint
        )
    }

    private func containsAnyWholePhrase(_ phrases: [String], in prompt: String) -> Bool {
        phrases.contains { containsWholePhrase($0, in: prompt) }
    }

    private func containsWholePhrase(_ phrase: String, in prompt: String) -> Bool {
        let pattern = "(^|\\s)\(NSRegularExpression.escapedPattern(for: phrase))(\\s|$)"
        return prompt.range(of: pattern, options: .regularExpression) != nil
    }

    private func isRowListPrompt(_ prompt: String) -> Bool {
        if prompt.contains("most recent")
            || prompt.contains("newest")
            || prompt.contains("latest") {
            return true
        }

        let rowObjects = [
            "expense", "expenses", "transaction", "transactions",
            "purchase", "purchases", "planned expenses", "items", "rows"
        ]
        let mentionsRows = rowObjects.contains { prompt.contains($0) }
        guard mentionsRows else { return false }

        if prompt.hasPrefix("list ")
            || prompt.hasPrefix("show ")
            || prompt.contains(" list ")
            || prompt.contains(" show ") {
            return true
        }

        return prompt.range(of: "\\blast\\s+\\d+\\b", options: .regularExpression) != nil
    }

    private func primaryDatePhrase(in prompt: String) -> String? {
        [
            "next month", "this month", "current month", "month to date",
            "last month", "previous month", "this week", "last week",
            "today", "yesterday", "this year", "last year"
        ].first { prompt.contains($0) }
    }

    private func normalized(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
