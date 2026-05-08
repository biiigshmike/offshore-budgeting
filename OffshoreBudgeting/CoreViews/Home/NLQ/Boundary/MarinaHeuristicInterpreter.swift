import Foundation

struct MarinaHeuristicInterpreter {
    private let normalize: (String, HomeQueryPeriodUnit) -> NormalizedQueryIntent
    private let now: () -> Date

    init(
        normalize: @escaping (String, HomeQueryPeriodUnit) -> NormalizedQueryIntent = { prompt, defaultPeriodUnit in
            MarinaNLQNormalizer(defaultPeriodUnit: defaultPeriodUnit).normalize(prompt: prompt)
        },
        now: @escaping () -> Date = Date.init
    ) {
        self.normalize = normalize
        self.now = now
    }

    func interpret(
        prompt: String,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> MarinaQueryPlanCandidate {
        let intent = normalize(prompt, defaultPeriodUnit)
        let protectedShape = protectedShape(from: intent)
        let unsupportedHint = protectedShape?.unsupportedHint ?? unsupportedHint(from: intent.unsupportedShapeReason)
        let operation = protectedShape?.operation ?? operation(from: intent)
        let measure = protectedShape?.measure ?? measure(from: intent)

        return MarinaQueryPlanCandidate(
            source: .heuristic,
            rawPrompt: prompt,
            operation: operation,
            measure: measure,
            entityMentions: entityMentions(from: intent, operation: operation, protectedShape: protectedShape),
            timeScopes: timeScopes(from: intent, defaultPeriodUnit: defaultPeriodUnit, protectedShape: protectedShape),
            grouping: protectedShape != nil ? protectedShape?.grouping : grouping(from: intent),
            ranking: protectedShape != nil ? protectedShape?.ranking : ranking(from: intent, operation: operation),
            limit: intent.resultLimit,
            responseShapeHint: protectedShape?.responseShapeHint ?? responseShapeHint(from: intent, operation: operation),
            confidence: confidence(from: intent, protectedShape: protectedShape),
            unsupportedHint: unsupportedHint
        )
    }

    private func operation(from intent: NormalizedQueryIntent) -> MarinaCandidateOperation? {
        if intent.unsupportedShapeReason == .whatIfSimulation {
            return .simulate
        }

        if intent.comparisonDateRange != nil || intent.modifiers.contains("comparison") {
            return .compare
        }

        switch intent.normalizedMetric {
        case .spendAveragePerPeriod, .incomeAverageActual:
            return .average
        case .topCategories, .topMerchants, .largestTransactions, .mostFrequentTransactions:
            return .rank
        case .categorySpendShare:
            return .sum
        case .spendTotal, .categorySpendTotal, .merchantSpendTotal, .categoryMonthComparison, .monthComparison, .presetDueSoon:
            return .sum
        case nil:
            switch intent.queryShape.measure {
            case .spendAverage, .incomeAverage:
                return .average
            case .transactionFrequency:
                return .count
            case .spendTotal:
                return intent.queryShape.ranking == nil ? .sum : .rank
            case .presetStatus, nil:
                return nil
            }
        }
    }

    private func measure(from intent: NormalizedQueryIntent) -> MarinaCandidateMeasure? {
        if intent.unsupportedShapeReason == .whatIfSimulation {
            return .remainingBudget
        }

        switch intent.normalizedMetric {
        case .incomeAverageActual:
            return .income
        case .categorySpendShare:
            return .categoryShare
        case .largestTransactions:
            return .transactionAmount
        case .mostFrequentTransactions:
            return .transactionFrequency
        case .presetDueSoon:
            return .presetAmount
        case .spendTotal, .categorySpendTotal, .merchantSpendTotal, .topCategories, .topMerchants,
            .monthComparison, .categoryMonthComparison, .spendAveragePerPeriod:
            return .spend
        case nil:
            switch intent.queryShape.measure {
            case .incomeAverage:
                return .income
            case .transactionFrequency:
                return .transactionFrequency
            case .presetStatus:
                return .presetAmount
            case .spendTotal, .spendAverage:
                return .spend
            case nil:
                return nil
            }
        }
    }

    private func entityMentions(
        from intent: NormalizedQueryIntent,
        operation: MarinaCandidateOperation?,
        protectedShape: ProtectedShape?
    ) -> [MarinaUnresolvedEntityMention] {
        if let mentions = protectedShape?.entityMentions {
            return mentions
        }

        guard let rawTargetText = intent.rawTargetText?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawTargetText.isEmpty == false else {
            return []
        }

        if shouldSuppressUnscopedRankingTarget(rawTargetText, intent: intent, operation: operation) {
            return []
        }

        let typeHint = entityTypeHint(from: intent)
        let cleanedRawText = cleanEntitySpan(
            rawTargetText,
            operation: operation,
            typeHint: typeHint
        )

        return [
            MarinaUnresolvedEntityMention(
                role: entityMentionRole(from: intent),
                rawText: cleanedRawText,
                typeHint: typeHint,
                confidence: confidence(from: intent, protectedShape: protectedShape)
            )
        ]
    }

    private func shouldSuppressUnscopedRankingTarget(
        _ rawTargetText: String,
        intent: NormalizedQueryIntent,
        operation: MarinaCandidateOperation?
    ) -> Bool {
        guard operation == .rank, grouping(from: intent) != nil else { return false }
        return normalized(rawTargetText) == normalized(intent.rawPrompt)
    }

    private func entityMentionRole(from intent: NormalizedQueryIntent) -> MarinaEntityMentionRole {
        if isCardSpendFilter(intent) {
            return .filter
        }
        return .primaryTarget
    }

    private func entityTypeHint(from intent: NormalizedQueryIntent) -> MarinaCandidateEntityTypeHint? {
        if intent.comparisonDateRange != nil,
           intent.normalizedMetric == .monthComparison,
           intent.queryShape.grouping == .some(.merchant) {
            return nil
        }

        switch intent.queryShape.grouping {
        case .some(.category):
            return .category
        case .some(.merchant):
            return .merchant
        case .some(.preset):
            return .preset
        case .some(.incomeSource):
            return .incomeSource
        case .some(.transaction):
            return .transaction
        case .some(.none):
            if isCardSpendFilter(intent) {
                return .card
            }
            return nil
        case nil:
            break
        }

        switch intent.normalizedMetric {
        case .categorySpendTotal, .categorySpendShare, .categoryMonthComparison:
            return .category
        case .merchantSpendTotal:
            return .merchant
        case .incomeAverageActual:
            return .incomeSource
        case .presetDueSoon:
            return .preset
        case .largestTransactions, .mostFrequentTransactions:
            return .transaction
        case .spendTotal, .topCategories, .topMerchants, .monthComparison, .spendAveragePerPeriod, nil:
            return isCardSpendFilter(intent) ? .card : nil
        }
    }

    private func isCardSpendFilter(_ intent: NormalizedQueryIntent) -> Bool {
        let target = intent.rawTargetText?.lowercased() ?? ""
        guard target.contains("card") else { return false }
        return intent.normalizedMetric == .spendTotal || intent.queryShape.grouping == .some(.none)
    }

    private func timeScopes(
        from intent: NormalizedQueryIntent,
        defaultPeriodUnit: HomeQueryPeriodUnit,
        protectedShape: ProtectedShape? = nil
    ) -> [MarinaUnresolvedTimeScope] {
        if let scopes = protectedShape?.timeScopes {
            return scopes
        }

        return baseTimeScopes(from: intent, defaultPeriodUnit: defaultPeriodUnit)
    }

    private func baseTimeScopes(
        from intent: NormalizedQueryIntent,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> [MarinaUnresolvedTimeScope] {
        var scopes: [MarinaUnresolvedTimeScope] = []

        if let dateRange = intent.dateRange {
            scopes.append(
                MarinaUnresolvedTimeScope(
                    role: isLookbackWindow(intent) ? .lookbackWindow : .primary,
                    rawText: nil,
                    resolvedRangeHint: dateRange,
                    periodUnitHint: defaultPeriodUnit
                )
            )
        }

        if let comparisonDateRange = intent.comparisonDateRange {
            scopes.append(
                MarinaUnresolvedTimeScope(
                    role: .comparison,
                    rawText: nil,
                    resolvedRangeHint: comparisonDateRange,
                    periodUnitHint: defaultPeriodUnit
                )
            )
        }

        if intent.unsupportedShapeReason == .whatIfSimulation, scopes.isEmpty {
            scopes.append(
                MarinaUnresolvedTimeScope(
                    role: .simulationHorizon,
                    rawText: nil,
                    periodUnitHint: defaultPeriodUnit
                )
            )
        }

        return scopes
    }

    private func isLookbackWindow(_ intent: NormalizedQueryIntent) -> Bool {
        intent.normalizedMetric == .spendAveragePerPeriod
            || intent.normalizedMetric == .incomeAverageActual
            || intent.queryShape.measure == .spendAverage
            || intent.queryShape.measure == .incomeAverage
    }

    private func grouping(from intent: NormalizedQueryIntent) -> MarinaGroupingCandidate? {
        switch intent.queryShape.grouping {
        case .some(.category):
            return MarinaGroupingCandidate(dimension: .category)
        case .some(.merchant):
            return MarinaGroupingCandidate(dimension: .merchant)
        case .some(.preset):
            return MarinaGroupingCandidate(dimension: .preset)
        case .some(.incomeSource):
            return MarinaGroupingCandidate(dimension: .incomeSource)
        case .some(.transaction):
            return MarinaGroupingCandidate(dimension: .transaction)
        case .some(.none), nil:
            break
        }

        switch intent.normalizedMetric {
        case .topCategories, .categorySpendShare:
            return MarinaGroupingCandidate(dimension: .category)
        case .topMerchants:
            return MarinaGroupingCandidate(dimension: .merchant)
        default:
            return nil
        }
    }

    private func ranking(
        from intent: NormalizedQueryIntent,
        operation: MarinaCandidateOperation?
    ) -> MarinaRankingCandidate? {
        let direction: MarinaRankingDirectionCandidate?

        switch intent.queryShape.ranking {
        case .top:
            direction = .top
        case .bottom:
            direction = .bottom
        case .largest:
            direction = .largest
        case .smallest:
            direction = .smallest
        case .mostFrequent:
            direction = .mostFrequent
        case .leastFrequent:
            direction = .leastFrequent
        case nil:
            switch intent.normalizedMetric {
            case .topCategories, .topMerchants:
                direction = .top
            case .largestTransactions:
                direction = .largest
            case .mostFrequentTransactions:
                direction = .mostFrequent
            default:
                direction = nil
            }
        }

        guard let direction, operation == .rank else { return nil }
        return MarinaRankingCandidate(direction: direction, limit: intent.resultLimit)
    }

    private func responseShapeHint(
        from intent: NormalizedQueryIntent,
        operation: MarinaCandidateOperation?
    ) -> MarinaResponseShapeHint? {
        if intent.unsupportedShapeReason != nil {
            return .unsupported
        }

        switch operation {
        case .compare:
            return .comparison
        case .rank:
            return .rankedList
        case .sum, .average, .count:
            if intent.normalizedMetric == .categorySpendShare || intent.modifiers.contains("breakdown_by_category") {
                return .groupedBreakdown
            }
            return .scalarCurrency
        case .minimum, .maximum, .trend, .forecast, .simulate, nil:
            return nil
        }
    }

    private func unsupportedHint(from reason: MarinaUnsupportedShapeReason?) -> MarinaUnsupportedHint? {
        switch reason {
        case .whatIfSimulation:
            return .unsupportedSimulation
        case .rankedAverage, .targetedAverage, .unsupportedCombination:
            return .unsupportedCombination
        case nil:
            return nil
        }
    }

    private func confidence(
        from intent: NormalizedQueryIntent,
        protectedShape: ProtectedShape? = nil
    ) -> MarinaCandidateConfidence {
        if protectedShape != nil {
            return .medium
        }

        if intent.confidenceLevel == .low,
           intent.normalizedMetric != nil,
           intent.rawTargetText == nil,
           intent.dateRange != nil,
           intent.unsupportedShapeReason == nil {
            return .medium
        }

        switch intent.confidenceLevel {
        case .high:
            return .high
        case .medium:
            return .medium
        case .low:
            return .low
        }
    }

    private func normalized(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func protectedShape(from intent: NormalizedQueryIntent) -> ProtectedShape? {
        let prompt = normalized(intent.rawPrompt)

        if isProjectionPrompt(prompt) {
            return ProtectedShape(
                operation: .forecast,
                measure: .remainingBudget,
                entityMentions: [],
                responseShapeHint: .unsupported,
                unsupportedHint: .unsupportedProjection
            )
        }

        if isSimulationPrompt(prompt) {
            return ProtectedShape(
                operation: .simulate,
                measure: .remainingBudget,
                entityMentions: simulationMentions(from: prompt),
                responseShapeHint: .unsupported,
                unsupportedHint: .unsupportedSimulation
            )
        }

        if isExclusionPrompt(prompt) {
            return ProtectedShape(
                operation: .sum,
                measure: .spend,
                entityMentions: exclusionMentions(from: prompt),
                responseShapeHint: .unsupported,
                unsupportedHint: .unsupportedExclusionFilter
            )
        }

        if isBudgetLimitPrompt(prompt) {
            return ProtectedShape(
                operation: .compare,
                measure: .remainingBudget,
                entityMentions: categoryMention(from: budgetLimitTarget(in: prompt)),
                timeScopes: comparisonTimeScopes(from: prompt, intent: intent),
                responseShapeHint: .unsupported,
                unsupportedHint: .unsupportedBudgetLimit
            )
        }

        if isTransactionDeltaDriversPrompt(prompt) {
            return ProtectedShape(
                operation: .compare,
                measure: .spend,
                entityMentions: [],
                timeScopes: comparisonTimeScopes(from: prompt, intent: intent),
                grouping: MarinaGroupingCandidate(dimension: .transaction),
                ranking: MarinaRankingCandidate(direction: .largest),
                responseShapeHint: .rankedList,
                unsupportedHint: .unsupportedRankedComparison
            )
        }

        if isCategoryDeltaRankingPrompt(prompt) {
            return ProtectedShape(
                operation: .compare,
                measure: .spend,
                entityMentions: [],
                timeScopes: comparisonTimeScopes(from: prompt, intent: intent),
                grouping: MarinaGroupingCandidate(dimension: .category),
                ranking: MarinaRankingCandidate(direction: .largest),
                responseShapeHint: .rankedList,
                unsupportedHint: .unsupportedRankedComparison
            )
        }

        if isCardRankingPrompt(prompt) {
            return ProtectedShape(
                operation: .rank,
                measure: .spend,
                entityMentions: [],
                grouping: MarinaGroupingCandidate(dimension: .card),
                ranking: MarinaRankingCandidate(direction: .top),
                responseShapeHint: .rankedList,
                unsupportedHint: .unsupportedCardRanking
            )
        }

        if isBreakdownPrompt(prompt) {
            return ProtectedShape(
                operation: .rank,
                measure: .spend,
                entityMentions: [],
                grouping: MarinaGroupingCandidate(dimension: .category),
                ranking: MarinaRankingCandidate(direction: .top),
                responseShapeHint: .groupedBreakdown
            )
        }

        if isSharePrompt(prompt),
           let target = shareTarget(in: prompt) {
            return ProtectedShape(
                operation: .sum,
                measure: .categoryShare,
                entityMentions: categoryMention(from: target),
                grouping: MarinaGroupingCandidate(dimension: .category),
                responseShapeHint: .groupedBreakdown
            )
        }

        if isFrequencyRankingPrompt(prompt) {
            return ProtectedShape(
                operation: .rank,
                measure: .transactionFrequency,
                entityMentions: [],
                grouping: MarinaGroupingCandidate(dimension: .transaction),
                ranking: MarinaRankingCandidate(direction: .mostFrequent),
                responseShapeHint: .rankedList
            )
        }

        if isMessyComparisonPrompt(prompt),
           let target = comparisonTarget(in: prompt) {
            return ProtectedShape(
                operation: .compare,
                measure: .spend,
                entityMentions: categoryMention(from: target),
                timeScopes: comparisonTimeScopes(from: prompt, intent: intent),
                grouping: MarinaGroupingCandidate(dimension: .category),
                responseShapeHint: .comparison
            )
        }

        return nil
    }

    private func isProjectionPrompt(_ prompt: String) -> Bool {
        prompt.contains("keep spending like this")
            && prompt.contains("left")
            && prompt.contains("end of the period")
    }

    private func isSimulationPrompt(_ prompt: String) -> Bool {
        (prompt.hasPrefix("if i add") || prompt.hasPrefix("if i increase"))
            && prompt.contains("does")
            && prompt.contains("still have room")
    }

    private func isExclusionPrompt(_ prompt: String) -> Bool {
        prompt.contains(" outside of ")
    }

    private func isBudgetLimitPrompt(_ prompt: String) -> Bool {
        prompt.contains("where it should be for this budget")
            || (prompt.contains(" over ") && prompt.contains("this budget"))
    }

    private func isCategoryDeltaRankingPrompt(_ prompt: String) -> Bool {
        prompt.contains("category changed the most")
            && prompt.contains("compared to")
    }

    private func isTransactionDeltaDriversPrompt(_ prompt: String) -> Bool {
        (prompt.contains("what expenses") || prompt.contains("which expenses"))
            && (prompt.contains("making this month higher than last month")
                || prompt.contains("made this month higher than last month"))
    }

    private func isCardRankingPrompt(_ prompt: String) -> Bool {
        (prompt.hasPrefix("what card ") || prompt.hasPrefix("which card "))
            && (prompt.contains("most") || prompt.contains("eating"))
    }

    private func isBreakdownPrompt(_ prompt: String) -> Bool {
        prompt.contains("break down")
            && (prompt.contains("where my money went") || prompt.contains("by category"))
    }

    private func isSharePrompt(_ prompt: String) -> Bool {
        prompt.contains("how much of my spending")
            || prompt.contains("share of my spending")
            || prompt.contains("percent of my spending")
            || prompt.contains("percentage of my spending")
    }

    private func isFrequencyRankingPrompt(_ prompt: String) -> Bool {
        prompt.contains("too often")
            || prompt.contains("not necessarily the most money")
    }

    private func isMessyComparisonPrompt(_ prompt: String) -> Bool {
        prompt.contains("spending more on")
            || prompt.hasPrefix("compare ")
            || prompt.contains("compared to last month")
            || prompt.contains("go up or down from")
            || prompt.contains("this month than last month")
            || prompt.contains("this month vs last month")
    }

    private func comparisonTarget(in prompt: String) -> String? {
        let patterns = [
            #"\bmore\s+on\s+(.+?)(?=\s+lately\b|\s+or\b|$)"#,
            #"\bwas\s+(.+?)(?=\s+compared\s+to\b|$)"#,
            #"\bdid\s+(.+?)\s+go\s+up\s+or\s+down\b"#,
            #"^compare\s+(.+?)(?=\s+this\s+month\b|\s+to\s+last\s+month\b|$)"#
        ]
        return firstCapture(in: prompt, patterns: patterns).map {
            cleanEntitySpan($0, operation: .compare, typeHint: .category)
        }
    }

    private func shareTarget(in prompt: String) -> String? {
        firstCapture(
            in: prompt,
            patterns: [
                #"\bwas\s+(.+?)$"#,
                #"\bspending\s+was\s+(.+?)$"#
            ]
        )
        .map { cleanEntitySpan($0, operation: .sum, typeHint: .category) }
    }

    private func budgetLimitTarget(in prompt: String) -> String? {
        firstCapture(
            in: prompt,
            patterns: [
                #"^is\s+(.+?)\s+over\b"#,
                #"^is\s+(.+?)\s+where\b"#
            ]
        )
        .map { cleanEntitySpan($0, operation: .compare, typeHint: .category) }
    }

    private func simulationMentions(from prompt: String) -> [MarinaUnresolvedEntityMention] {
        guard let input = firstCapture(in: prompt, patterns: [#"\bto\s+(.+?)\s+does\b"#]),
              let output = firstCapture(in: prompt, patterns: [#"\bdoes\s+(.+?)\s+still\s+have\s+room\b"#]) else {
            return []
        }
        return [
            MarinaUnresolvedEntityMention(
                role: .simulationInput,
                rawText: cleanEntitySpan(input, operation: .simulate, typeHint: .category),
                typeHint: .category,
                confidence: .medium
            ),
            MarinaUnresolvedEntityMention(
                role: .simulationOutput,
                rawText: cleanEntitySpan(output, operation: .simulate, typeHint: .category),
                typeHint: .category,
                confidence: .medium
            )
        ]
    }

    private func exclusionMentions(from prompt: String) -> [MarinaUnresolvedEntityMention] {
        guard let card = firstCapture(in: prompt, patterns: [#"\bon\s+(.+?)\s+outside\s+of\b"#]),
              let excludedCategory = firstCapture(in: prompt, patterns: [#"\boutside\s+of\s+(.+?)$"#]) else {
            return []
        }
        return [
            MarinaUnresolvedEntityMention(
                role: .filter,
                rawText: cleanEntitySpan(card, operation: .sum, typeHint: .card),
                typeHint: .card,
                confidence: .medium
            ),
            MarinaUnresolvedEntityMention(
                role: .filter,
                rawText: cleanEntitySpan(excludedCategory, operation: .sum, typeHint: .category),
                typeHint: .category,
                confidence: .medium
            )
        ]
    }

    private func categoryMention(from rawText: String?) -> [MarinaUnresolvedEntityMention] {
        guard let rawText,
              rawText.isEmpty == false else {
            return []
        }
        return [
            MarinaUnresolvedEntityMention(
                role: .primaryTarget,
                rawText: rawText,
                typeHint: .category,
                confidence: .medium
            )
        ]
    }

    private func comparisonTimeScopes(
        from prompt: String,
        intent: NormalizedQueryIntent
    ) -> [MarinaUnresolvedTimeScope]? {
        if let primary = intent.dateRange,
           let comparison = intent.comparisonDateRange {
            if prompt.contains(" from ") && prompt.contains(" to ") {
                return comparisonScopes(primary: comparison, comparison: primary)
            }
            return comparisonScopes(primary: primary, comparison: comparison)
        }

        if isCurrentVersusLastMonthComparison(prompt) || isLatelyBaselineComparison(prompt) {
            let primary = monthRange(containing: now())
            return comparisonScopes(
                primary: primary,
                comparison: previousMonthRange(before: primary.startDate)
            )
        }

        return nil
    }

    private func isCurrentVersusLastMonthComparison(_ prompt: String) -> Bool {
        prompt.contains("compared to last month")
            || prompt.contains("this month than last month")
            || prompt.contains("this month vs last month")
            || prompt.contains("this month versus last month")
            || prompt.contains("higher than last month")
    }

    private func isLatelyBaselineComparison(_ prompt: String) -> Bool {
        prompt.contains("lately")
            && (prompt.contains("about normal") || prompt.contains("more on"))
    }

    private func comparisonScopes(
        primary: HomeQueryDateRange,
        comparison: HomeQueryDateRange
    ) -> [MarinaUnresolvedTimeScope] {
        [
            MarinaUnresolvedTimeScope(
                role: .primary,
                rawText: nil,
                resolvedRangeHint: primary,
                periodUnitHint: .month
            ),
            MarinaUnresolvedTimeScope(
                role: .comparison,
                rawText: nil,
                resolvedRangeHint: comparison,
                periodUnitHint: .month
            )
        ]
    }

    private func monthRange(containing date: Date) -> HomeQueryDateRange {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func previousMonthRange(before date: Date) -> HomeQueryDateRange {
        let calendar = Calendar(identifier: .gregorian)
        let currentMonth = monthRange(containing: date)
        let previousStart = calendar.date(byAdding: .month, value: -1, to: currentMonth.startDate) ?? currentMonth.startDate
        return HomeQueryDateRange(startDate: previousStart, endDate: currentMonth.startDate)
    }

    private func cleanEntitySpan(
        _ text: String,
        operation: MarinaCandidateOperation?,
        typeHint: MarinaCandidateEntityTypeHint?
    ) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let stopPatterns = [
            #"\s+or\s+is\s+it\s+about\s+normal\b.*$"#,
            #"\s+lately\b.*$"#,
            #"\s+does\b.*$"#,
            #"\s+still\s+have\s+room\b.*$"#,
            #"\s+outside\s+of\b.*$"#,
            #"\s+by\s+category\b.*$"#,
            #"\s+over\s+the\s+last\b.*$"#,
            #"\s+over\s+the\b.*$"#,
            #"\s+right\s+now\b.*$"#,
            #"\s+this\s+month\b.*$"#,
            #"\s+last\s+month\b.*$"#,
            #"\s+compared\s+to\b.*$"#,
            #"\s+than\b.*$"#,
            #"\s+from\b.*$"#,
            #"\s+to\b.*$"#
        ]

        for pattern in stopPatterns {
            let candidate = cleaned.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.isEmpty == false, candidate != cleaned {
                cleaned = candidate
                break
            }
        }

        return cleaned
            .replacingOccurrences(of: #"^(?:my|the)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firstCapture(in text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range),
                  match.numberOfRanges >= 2,
                  let captureRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            let capture = String(text[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if capture.isEmpty == false {
                return capture
            }
        }
        return nil
    }
}

private struct ProtectedShape {
    let operation: MarinaCandidateOperation
    let measure: MarinaCandidateMeasure
    let entityMentions: [MarinaUnresolvedEntityMention]?
    let timeScopes: [MarinaUnresolvedTimeScope]?
    let grouping: MarinaGroupingCandidate?
    let ranking: MarinaRankingCandidate?
    let responseShapeHint: MarinaResponseShapeHint
    let unsupportedHint: MarinaUnsupportedHint?

    init(
        operation: MarinaCandidateOperation,
        measure: MarinaCandidateMeasure,
        entityMentions: [MarinaUnresolvedEntityMention]? = nil,
        timeScopes: [MarinaUnresolvedTimeScope]? = nil,
        grouping: MarinaGroupingCandidate? = nil,
        ranking: MarinaRankingCandidate? = nil,
        responseShapeHint: MarinaResponseShapeHint,
        unsupportedHint: MarinaUnsupportedHint? = nil
    ) {
        self.operation = operation
        self.measure = measure
        self.entityMentions = entityMentions
        self.timeScopes = timeScopes
        self.grouping = grouping
        self.ranking = ranking
        self.responseShapeHint = responseShapeHint
        self.unsupportedHint = unsupportedHint
    }
}
