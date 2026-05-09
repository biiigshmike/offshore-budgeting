import Foundation

struct MarinaIntentInterpreter {
    private let parser: HomeAssistantTextParser
    private let defaultPeriodUnit: HomeQueryPeriodUnit

    init(
        parser: HomeAssistantTextParser,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) {
        self.parser = parser
        self.defaultPeriodUnit = defaultPeriodUnit
    }

    func interpretQueryShape(
        rawPrompt: String,
        normalizedPrompt: String,
        modifiers: [String],
        dateRange: HomeQueryDateRange?,
        comparisonDateRange: HomeQueryDateRange?
    ) -> MarinaQueryShape {
        let tokens = Set(normalizedPrompt.split(separator: " ").map(String.init))
        let ranking = ranking(in: normalizedPrompt, tokens: tokens)
        let targetHint = targetHint(in: normalizedPrompt, ranking: ranking)
        let measure = measure(
            in: normalizedPrompt,
            tokens: tokens,
            ranking: ranking,
            targetHint: targetHint,
            comparisonDateRange: comparisonDateRange
        )
        let grouping = grouping(
            in: normalizedPrompt,
            tokens: tokens,
            measure: measure,
            ranking: ranking,
            targetHint: targetHint,
            comparisonDateRange: comparisonDateRange
        )

        return MarinaQueryShape(
            measure: measure,
            grouping: grouping,
            ranking: ranking,
            targetHint: targetHint,
            dateRange: dateRange,
            comparisonDateRange: comparisonDateRange,
            modifiers: modifiers
        )
    }

    func deriveSignals(from shape: MarinaQueryShape) -> MarinaIntentSignals {
        MarinaIntentSignals(
            family: family(from: shape),
            subject: subject(from: shape),
            rankingMode: rankingMode(from: shape.ranking),
            aggregationMode: aggregationMode(from: shape.measure, ranking: shape.ranking, targetHint: shape.targetHint),
            targetHint: shape.targetHint,
            modifiers: shape.modifiers
        )
    }

    func interpret(
        rawPrompt: String,
        normalizedPrompt: String,
        modifiers: [String]
    ) -> MarinaIntentSignals {
        let shape = interpretQueryShape(
            rawPrompt: rawPrompt,
            normalizedPrompt: normalizedPrompt,
            modifiers: modifiers,
            dateRange: nil,
            comparisonDateRange: nil
        )
        return deriveSignals(from: shape)
    }

    private func measure(
        in normalizedPrompt: String,
        tokens: Set<String>,
        ranking: MarinaQueryRanking?,
        targetHint: String?,
        comparisonDateRange: HomeQueryDateRange?
    ) -> MarinaQueryMeasure? {
        if containsAnyPhrase(MarinaIntentLexicon.mostFrequentPhrases, in: normalizedPrompt)
            || containsAnyPhrase(MarinaIntentLexicon.leastFrequentPhrases, in: normalizedPrompt)
            || tokens.intersection(MarinaIntentLexicon.frequencyTerms).isEmpty == false
        {
            return .transactionFrequency
        }

        if tokens.intersection(MarinaIntentLexicon.aggregateAverageTerms).isEmpty == false {
            if tokens.intersection(MarinaIntentLexicon.incomeTerms).isEmpty == false {
                return .incomeAverage
            }
            return .spendAverage
        }

        if normalizedPrompt.contains("usually spend") {
            return .spendAverage
        }

        if tokens.intersection(MarinaIntentLexicon.presetTerms).isEmpty == false,
           normalizedPrompt.contains("due soon") || normalizedPrompt.contains("upcoming")
        {
            return .presetStatus
        }

        if comparisonDateRange != nil
            || targetHint != nil
            || ranking != nil
            || containsAnyPhrase(MarinaIntentLexicon.aggregateAmountPhrases, in: normalizedPrompt)
            || tokens.intersection(MarinaIntentLexicon.aggregateTotalTerms).isEmpty == false
            || tokens.intersection(MarinaIntentLexicon.spendMoneyTerms).isEmpty == false
        {
            return .spendTotal
        }

        return nil
    }

    private func grouping(
        in normalizedPrompt: String,
        tokens: Set<String>,
        measure: MarinaQueryMeasure?,
        ranking: MarinaQueryRanking?,
        targetHint: String?,
        comparisonDateRange: HomeQueryDateRange?
    ) -> MarinaQueryGrouping? {
        if merchantRankingCueDetected(in: normalizedPrompt, tokens: tokens, ranking: ranking) {
            return .merchant
        }

        if isGroupedSpendRankingPrompt(normalizedPrompt, ranking: ranking) {
            return .category
        }

        if tokens.intersection(MarinaIntentLexicon.cardTerms).isEmpty == false {
            return .some(.none)
        }

        if tokens.intersection(MarinaIntentLexicon.categoryTerms).isEmpty == false {
            return .category
        }

        if tokens.intersection(MarinaIntentLexicon.incomeTerms).isEmpty == false {
            return .incomeSource
        }

        if tokens.intersection(MarinaIntentLexicon.presetTerms).isEmpty == false {
            return .preset
        }

        if tokens.intersection(MarinaIntentLexicon.transactionTerms).isEmpty == false {
            return .transaction
        }

        if tokens.intersection(MarinaIntentLexicon.merchantTerms).isEmpty == false {
            return .merchant
        }

        if measure == .spendTotal, targetHint != nil, merchantTargetPatternDetected(in: normalizedPrompt) {
            return .merchant
        }

        if measure == .spendTotal, targetHint != nil, cardTargetPatternDetected(in: normalizedPrompt) {
            return .some(.none)
        }

        if measure == .spendTotal, targetHint != nil,
           (normalizedPrompt.contains(" on ")
               || normalizedPrompt.contains(" spent in ")
               || normalizedPrompt.contains(" spending in ")
               || normalizedPrompt.contains(" money went to ")
               || normalizedPrompt.contains(" went to ")) {
            return .category
        }

        if comparisonDateRange != nil, targetHint != nil {
            return .category
        }

        return measure == .incomeAverage ? .some(.none) : nil
    }

    private func ranking(
        in normalizedPrompt: String,
        tokens: Set<String>
    ) -> MarinaQueryRanking? {
        if containsAnyPhrase(MarinaIntentLexicon.mostFrequentPhrases, in: normalizedPrompt) {
            return .mostFrequent
        }
        if containsAnyPhrase(MarinaIntentLexicon.leastFrequentPhrases, in: normalizedPrompt) {
            return .leastFrequent
        }
        if isIndirectGroupedSpendRankingPrompt(normalizedPrompt) {
            return .top
        }
        if tokens.intersection(MarinaIntentLexicon.rankingLargest).isEmpty == false {
            return .largest
        }
        if tokens.intersection(MarinaIntentLexicon.rankingSmallest).isEmpty == false {
            return .smallest
        }
        if tokens.intersection(MarinaIntentLexicon.rankingBottom).isEmpty == false {
            return .bottom
        }
        if tokens.intersection(MarinaIntentLexicon.rankingTop).isEmpty == false {
            return .top
        }
        return nil
    }

    private func targetHint(
        in normalizedPrompt: String,
        ranking: MarinaQueryRanking?
    ) -> String? {
        if ranking != nil, isPluralRankingPromptWithoutTarget(in: normalizedPrompt) {
            return nil
        }

        if ranking != nil, explicitTargetMarkerDetected(in: normalizedPrompt) == false {
            return nil
        }

        if let comparisonHint = comparisonTargetHint(in: normalizedPrompt) {
            return comparisonHint
        }

        if let scopedHint = scopedTargetHint(in: normalizedPrompt) {
            return scopedHint
        }

        return nil
    }

    private func family(from shape: MarinaQueryShape) -> MarinaIntentFamily? {
        if shape.comparisonDateRange != nil || shape.modifiers.contains("comparison") {
            return .comparison
        }

        if shape.measure == .transactionFrequency {
            return .frequency
        }

        if shape.ranking != nil, shape.targetHint == nil || shape.grouping != nil {
            return .ranking
        }

        if shape.measure == .presetStatus {
            return .upcoming
        }

        if shape.measure != nil {
            return .aggregate
        }

        return nil
    }

    private func subject(from shape: MarinaQueryShape) -> MarinaIntentSubject? {
        switch shape.grouping {
        case .some(.transaction):
            return .transaction
        case .some(.category):
            return .category
        case .some(.merchant):
            return .merchant
        case .some(.preset):
            return .preset
        case .some(.incomeSource):
            return .income
        case .some(.none):
            if shape.measure == .spendTotal || shape.measure == .spendAverage {
                return .spend
            }
            return nil
        case nil:
            if shape.measure == .spendTotal || shape.measure == .spendAverage {
                return .spend
            }
            return nil
        }
    }

    private func rankingMode(from ranking: MarinaQueryRanking?) -> MarinaRankingMode? {
        switch ranking {
        case .top:
            return .top
        case .bottom:
            return .bottom
        case .largest:
            return .largest
        case .smallest:
            return .smallest
        case .mostFrequent:
            return .mostFrequent
        case .leastFrequent:
            return .leastFrequent
        case nil:
            return nil
        }
    }

    private func aggregationMode(
        from measure: MarinaQueryMeasure?,
        ranking: MarinaQueryRanking?,
        targetHint: String?
    ) -> MarinaAggregationMode? {
        guard ranking == nil || targetHint != nil else { return nil }

        switch measure {
        case .spendTotal:
            return .total
        case .spendAverage, .incomeAverage:
            return .average
        case .transactionFrequency:
            return .count
        default:
            return nil
        }
    }

    private func comparisonTargetHint(in normalizedPrompt: String) -> String? {
        guard normalizedPrompt.contains("compare ") else { return nil }

        if let range = normalizedPrompt.range(of: #"^compare\s+(.+?)\s+(?:vs|versus|to)\s+.+$"#, options: .regularExpression) {
            let match = String(normalizedPrompt[range])
            let candidate = match
                .replacingOccurrences(of: #"^compare\s+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+(?:vs|versus|to)\s+.+$"#, with: "", options: .regularExpression)
            return cleanedTargetHint(candidate)
        }

        return nil
    }

    private func scopedTargetHint(in normalizedPrompt: String) -> String? {
        let markerPatterns = [
            #"\bon\s+([a-z0-9 '&\.-]+?)(?=\s+(?:today|yesterday|this|last|in|from|vs|versus|to|so|current|all time|ever)\b|$)"#,
            #"\bat\s+([a-z0-9 '&\.-]+?)(?=\s+(?:today|yesterday|this|last|in|from|vs|versus|to|so|current|all time|ever)\b|$)"#,
            #"\bwith\s+([a-z0-9 '&\.-]+?)(?=\s+(?:today|yesterday|this|last|in|from|vs|versus|to|so|current|all time|ever)\b|$)"#,
            #"\bto\s+([a-z0-9 '&\.-]+?)(?=\s+(?:today|yesterday|this|last|in|from|vs|versus|so|current|all time|ever)\b|$)"#
        ]

        for pattern in markerPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(normalizedPrompt.startIndex..., in: normalizedPrompt)
            guard let match = regex.firstMatch(in: normalizedPrompt, options: [], range: range),
                  match.numberOfRanges >= 2,
                  let captureRange = Range(match.range(at: 1), in: normalizedPrompt) else {
                continue
            }

            let capture = String(normalizedPrompt[captureRange])
            if let cleaned = cleanedTargetHint(capture) {
                return cleaned
            }
        }

        return nil
    }

    private func cleanedTargetHint(_ text: String) -> String? {
        let stripped = dropTrailingParsedDatePhrase(from: text)
        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        let deowned = trimmed.replacingOccurrences(
            of: #"^(?:my|the)\s+"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let unprefixed = deowned.replacingOccurrences(
            of: #"^(?:on|at|for)\s+"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let withoutPeriodUnit = unprefixed.replacingOccurrences(
            of: #"\s+per\s+(month|week|year)\b"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let finalTrimmed = withoutPeriodUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard finalTrimmed.isEmpty == false else { return nil }
        guard finalTrimmed.contains(" and ") == false, finalTrimmed.contains(",") == false else { return nil }
        return finalTrimmed
    }

    private func dropTrailingParsedDatePhrase(from text: String) -> String {
        let tokens = text.split(separator: " ").map(String.init)
        guard tokens.count > 1 else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }

        for startIndex in 1..<tokens.count {
            let suffix = tokens[startIndex...].joined(separator: " ")
            if parser.parseDateRange(suffix, defaultPeriodUnit: defaultPeriodUnit) != nil {
                let prefix = tokens[..<startIndex].joined(separator: " ")
                return prefix.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsAnyPhrase(_ phrases: [String], in text: String) -> Bool {
        phrases.contains(where: text.contains)
    }

    private func explicitTargetMarkerDetected(in normalizedPrompt: String) -> Bool {
        MarinaIntentLexicon.targetMarkers.contains { marker in
            normalizedPrompt.contains(" \(marker) ")
        }
    }

    private func merchantTargetPatternDetected(in normalizedPrompt: String) -> Bool {
        if normalizedPrompt.contains(" at ")
            || normalizedPrompt.contains(" with ")
            || containsAnyPhrase(["merchant", "store", "vendor", "payee", "shop", "business"], in: normalizedPrompt) {
            return true
        }

        guard normalizedPrompt.contains(" to ") else { return false }
        return normalizedPrompt.range(
            of: #"\b(?:pay|paid|give|gave|sent)\b.*\bto\s+[a-z0-9 '&\.-]+"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private func cardTargetPatternDetected(in normalizedPrompt: String) -> Bool {
        MarinaIntentLexicon.cardTerms.contains { normalizedPrompt.contains(" \($0)") }
    }

    private func merchantRankingCueDetected(
        in normalizedPrompt: String,
        tokens: Set<String>,
        ranking: MarinaQueryRanking?
    ) -> Bool {
        guard ranking != nil else { return false }
        guard tokens.intersection(MarinaIntentLexicon.merchantTerms).isEmpty == false else { return false }
        return normalizedPrompt.contains("spend the most at")
            || normalizedPrompt.contains("spent the most at")
            || normalizedPrompt.contains("top merchant")
            || normalizedPrompt.contains("top merchants")
            || (normalizedPrompt.contains("spend") && normalizedPrompt.contains("most"))
    }

    private func isGroupedSpendRankingPrompt(_ normalizedPrompt: String, ranking: MarinaQueryRanking?) -> Bool {
        guard ranking == .top else { return false }

        if containsAnyPhrase(MarinaIntentLexicon.categoryRankingPhrases, in: normalizedPrompt)
            || containsAnyPhrase(MarinaIntentLexicon.indirectCategoryRankingPhrases, in: normalizedPrompt) {
            return true
        }

        return normalizedPrompt.contains("spend the most on")
            || (normalizedPrompt.contains("most of my money") && tokensSuggestMoneyMovement(normalizedPrompt))
    }

    private func isIndirectGroupedSpendRankingPrompt(_ normalizedPrompt: String) -> Bool {
        containsAnyPhrase(MarinaIntentLexicon.indirectCategoryRankingPhrases, in: normalizedPrompt)
            || normalizedPrompt.contains("spend the most money on")
            || (normalizedPrompt.contains("most of my money") && tokensSuggestMoneyMovement(normalizedPrompt))
    }

    private func tokensSuggestMoneyMovement(_ normalizedPrompt: String) -> Bool {
        let tokens = Set(normalizedPrompt.split(separator: " ").map(String.init))
        return tokens.intersection(MarinaIntentLexicon.spendMoneyTerms).isEmpty == false
            && tokens.intersection(MarinaIntentLexicon.movementTerms).isEmpty == false
    }

    private func isPluralRankingPromptWithoutTarget(in normalizedPrompt: String) -> Bool {
        normalizedPrompt.hasPrefix("what merchants ")
            || normalizedPrompt.hasPrefix("which merchants ")
            || normalizedPrompt.contains(" top merchants ")
            || normalizedPrompt.hasPrefix("what categories ")
            || normalizedPrompt.hasPrefix("which categories ")
            || normalizedPrompt.contains(" top categories ")
    }
}
