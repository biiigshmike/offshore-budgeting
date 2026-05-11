import Foundation

struct MarinaNLQNormalizer {
    private let parser: HomeAssistantTextParser
    private let defaultPeriodUnit: HomeQueryPeriodUnit
    private let intentInterpreter: MarinaIntentInterpreter
    private let metricMapper: MarinaMetricMapper

    init(
        parser: HomeAssistantTextParser = HomeAssistantTextParser(),
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) {
        self.parser = parser
        self.defaultPeriodUnit = defaultPeriodUnit
        self.intentInterpreter = MarinaIntentInterpreter(
            parser: parser,
            defaultPeriodUnit: defaultPeriodUnit
        )
        self.metricMapper = MarinaMetricMapper()
    }

    func normalize(prompt: String) -> NormalizedQueryIntent {
        let normalizedPrompt = normalizeText(prompt)
        let comparisonRanges = extractedComparisonDateRanges(from: normalizedPrompt)
        let explicitDateRange = parser.parseDateRange(prompt, defaultPeriodUnit: defaultPeriodUnit)
        let dateRange = comparisonRanges?.primaryRange ?? explicitDateRange
        let comparisonDateRange: HomeQueryDateRange? = comparisonRanges?.comparisonRange
        let resultLimit = parser.parseLimit(prompt)
        let parserPlan = parser.parsePlan(prompt, defaultPeriodUnit: defaultPeriodUnit)
        let modifiers = modifiers(from: normalizedPrompt)
        let queryShape = intentInterpreter.interpretQueryShape(
            rawPrompt: prompt,
            normalizedPrompt: normalizedPrompt,
            modifiers: modifiers,
            dateRange: dateRange,
            comparisonDateRange: comparisonDateRange
        )
        let isWhatIfPrompt = isWhatIfPrompt(normalizedPrompt)
        let intentSignals = intentInterpreter.deriveSignals(from: queryShape)
        let shapeResolution: MarinaQueryShapeResolution = isWhatIfPrompt
            ? .unsupported(reason: .whatIfSimulation)
            : metricMapper.resolve(shape: queryShape)
        var unsupportedShapeReason: MarinaUnsupportedShapeReason?
        var metric: MarinaNormalizedMetric?

        switch shapeResolution {
        case .metric(let resolvedMetric):
            metric = resolvedMetric
            unsupportedShapeReason = nil
        case .unsupported(let reason):
            metric = nil
            unsupportedShapeReason = reason
        case .unresolved:
            metric = normalizedMetric(from: normalizedPrompt)
                ?? parserInferredMetric(from: parserPlan)
            unsupportedShapeReason = nil
        }

        if normalizedPrompt.contains("usually spend")
            || ((normalizedPrompt.contains("average spend")
                || normalizedPrompt.contains("average spending"))
                && queryShape.ranking == nil) {
            metric = .spendAveragePerPeriod
            unsupportedShapeReason = nil
        }

        let rawTargetText = queryShape.targetHint ?? extractRawTargetText(
            from: prompt,
            normalizedPrompt: normalizedPrompt,
            comparisonPrimarySnippet: comparisonRanges?.primarySnippet
        )
            ?? parserInferredTarget(from: parserPlan)

        if shouldPromoteToCategorySpendTotalForCostMe(
            normalizedPrompt: normalizedPrompt,
            metric: metric,
            rawTargetText: rawTargetText,
            queryShape: queryShape
        ) {
            metric = .categorySpendTotal
            unsupportedShapeReason = nil
        }

        return NormalizedQueryIntent(
            rawPrompt: prompt,
            normalizedMetric: metric,
            queryShape: queryShape,
            intentSignals: intentSignals,
            unsupportedShapeReason: unsupportedShapeReason,
            rawTargetText: rawTargetText,
            dateRange: dateRange,
            comparisonDateRange: comparisonDateRange,
            resultLimit: resultLimit,
            modifiers: modifiers,
            confidenceLevel: confidenceLevel(
                metric: metric,
                rawTargetText: rawTargetText,
                usedCompatibilityFallback: shapeResolution == .unresolved
            )
        )
    }

    private func parserInferredMetric(from plan: HomeQueryPlan?) -> MarinaNormalizedMetric? {
        guard let plan else { return nil }
        switch plan.metric {
        case .spendTotal, .cardSpendTotal:
            return .spendTotal
        case .categorySpendTotal:
            return .categorySpendTotal
        case .merchantSpendTotal:
            return .merchantSpendTotal
        case .categorySpendShare:
            return .categorySpendShare
        case .monthComparison, .categoryMonthComparison, .merchantMonthComparison, .cardMonthComparison, .incomeSourceMonthComparison:
            return .monthComparison
        case .topCategories:
            return .topCategories
        case .topMerchants:
            return .topMerchants
        case .largestTransactions:
            return .largestTransactions
        case .mostFrequentTransactions:
            return .mostFrequentTransactions
        case .spendAveragePerPeriod:
            return .spendAveragePerPeriod
        case .incomeAverageActual:
            return .incomeAverageActual
        case .presetDueSoon:
            return .presetDueSoon
        default:
            return nil
        }
    }

    private func parserInferredTarget(from plan: HomeQueryPlan?) -> String? {
        guard let plan else { return nil }

        switch plan.metric {
        case .categorySpendTotal, .categorySpendShare, .merchantSpendTotal:
            return sanitizedTargetCandidate(plan.targetName ?? "")
        default:
            return nil
        }
    }

    private func normalizedMetric(from normalizedPrompt: String) -> MarinaNormalizedMetric? {
        if normalizedPrompt.contains("preset") && (normalizedPrompt.contains("due soon") || normalizedPrompt.contains("upcoming")) {
            return .presetDueSoon
        }

        if normalizedPrompt.contains("average income") || normalizedPrompt.contains("income average") {
            return .incomeAverageActual
        }

        if normalizedPrompt.contains("top merchants") {
            return .topMerchants
        }

        if normalizedPrompt.contains("top categories") {
            return .topCategories
        }

        if normalizedPrompt.contains("category breakdown")
            || normalizedPrompt.contains("categories breakdown") {
            return .categorySpendShare
        }

        if normalizedPrompt.contains("share of my spending")
            || normalizedPrompt.contains("share of spending")
            || normalizedPrompt.contains("percent of my spending")
            || normalizedPrompt.contains("percentage of my spending")
            || normalizedPrompt.contains("portion of my spending") {
            return .categorySpendShare
        }

        if normalizedPrompt.contains("average") {
            return .spendAveragePerPeriod
        }

        if normalizedPrompt.contains("largest") && (normalizedPrompt.contains("expense") || normalizedPrompt.contains("transaction")) {
            return .largestTransactions
        }

        if normalizedPrompt.contains("most frequent") && (normalizedPrompt.contains("expense") || normalizedPrompt.contains("transaction")) {
            return .mostFrequentTransactions
        }

        if normalizedPrompt.contains("compare") || normalizedPrompt.contains("versus") || normalizedPrompt.contains(" vs ") {
            return .monthComparison
        }

        if normalizedPrompt.contains("spend") || normalizedPrompt.contains("spent") {
            return .spendTotal
        }

        return nil
    }

    private func extractRawTargetText(
        from prompt: String,
        normalizedPrompt: String,
        comparisonPrimarySnippet: String?
    ) -> String? {
        var stripped = comparisonPrimarySnippet ?? normalizedPrompt

        let fillerPrefixes = [
            "what is my",
            "who is my",
            "how much did i",
            "show me",
            "tell me",
            "what did i",
            "can you"
        ]

        for filler in fillerPrefixes {
            if stripped.hasPrefix(filler + " ") {
                stripped = String(stripped.dropFirst(filler.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        let weakFragments: Set<String> = [
            "what is my current",
            "how much did i spend"
        ]

        if weakFragments.contains(stripped) {
            return nil
        }

        if let shareTarget = sharePromptTarget(in: stripped) {
            return shareTarget
        }

        let cleanedPromptSegment = sanitizedTargetCandidate(stripped)
        if isLikelyUnscopedMetricPhrase(cleanedPromptSegment) == false,
           isBroadQueryScaffoldingPhrase(cleanedPromptSegment) == false,
           isStrongTarget(cleanedPromptSegment) {
            return cleanedPromptSegment
        }

        let markerPatterns = [
            " on ",
            " at ",
            " for ",
            " in ",
            " with "
        ]

        for marker in markerPatterns {
            if let range = stripped.range(of: marker, options: .backwards) {
                let suffix = stripped[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                let cleaned = sanitizedTargetCandidate(String(suffix))
                if isBroadQueryScaffoldingPhrase(cleaned) == false, isStrongTarget(cleaned) {
                    return cleaned
                }
            }
        }

        return nil
    }

    private func sharePromptTarget(in text: String) -> String? {
        let normalized = normalizeText(text)
        let shareSignals = ["share", "percent", "percentage", "portion"]
        guard shareSignals.contains(where: normalized.contains) else { return nil }

        let patterns = [
            #"\b(?:is|was)\s+([a-z0-9 '&-]+?)(?=\s+(?:this|last|in|for|from|over|during)\b|$)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(normalized.startIndex..., in: normalized)
            guard let match = regex.firstMatch(in: normalized, options: [], range: range),
                  match.numberOfRanges >= 2,
                  let captureRange = Range(match.range(at: 1), in: normalized) else {
                continue
            }

            let candidate = sanitizedTargetCandidate(String(normalized[captureRange]))
            if isStrongTarget(candidate) {
                return candidate
            }
        }

        return nil
    }

    private func stripDateTail(_ text: String) -> String {
        let dateTokens = [
            " this month", " last month", " this week", " last week", " this year", " last year",
            " today", " yesterday", " so far", " currently"
        ]

        var output = text
        for token in dateTokens {
            if let range = output.range(of: token, options: .caseInsensitive) {
                output = String(output[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return output
    }

    private func stripExplicitTemporalFragments(_ text: String) -> String {
        let fragments = [
            "\\bof\\s+all\\s+time\\b",
            "\\ball\\s*[- ]time\\b",
            "\\bever\\b"
        ]

        var output = text
        for fragment in fragments {
            output = output.replacingOccurrences(
                of: fragment,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return output
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizedTargetCandidate(_ text: String) -> String {
        let strippedDateTail = stripDateTail(text)
        let strippedTemporalFragments = stripExplicitTemporalFragments(strippedDateTail)
        let strippedPeriodUnit = strippedTemporalFragments.replacingOccurrences(
            of: #"\s+per\s+(month|week|year)\b"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return dropTrailingParsedDatePhrase(from: strippedPeriodUnit)
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

    private func extractedComparisonDateRanges(
        from normalizedPrompt: String
    ) -> (primarySnippet: String, primaryRange: HomeQueryDateRange, comparisonRange: HomeQueryDateRange)? {
        let candidatePairs: [(String, String)] = [
            capturedComparisonSnippets(
                normalizedPrompt: normalizedPrompt,
                pattern: "\\bfrom\\s+(.+?)\\s+to\\s+(.+)$"
            ),
            capturedComparisonSnippets(
                normalizedPrompt: normalizedPrompt,
                pattern: "\\bbetween\\s+(.+?)\\s+and\\s+(.+)$"
            ),
            capturedComparisonSnippets(
                normalizedPrompt: normalizedPrompt,
                pattern: "\\bcompare\\s+(.+?)\\s+(?:vs|versus)\\s+(.+)$"
            ),
            comparisonSnippetsSeparatedByTo(normalizedPrompt: normalizedPrompt)
        ].compactMap { $0 }

        for (firstSnippet, secondSnippet) in candidatePairs {
            guard let firstRange = parser.parseDateRange(firstSnippet, defaultPeriodUnit: defaultPeriodUnit),
                  let secondRange = parser.parseDateRange(secondSnippet, defaultPeriodUnit: defaultPeriodUnit),
                  firstRange != secondRange else {
                continue
            }

            return (
                primarySnippet: firstSnippet.trimmingCharacters(in: .whitespacesAndNewlines),
                primaryRange: firstRange,
                comparisonRange: secondRange
            )
        }

        return nil
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

    private func isStrongTarget(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return false }
        let tokenCount = trimmed.split(separator: " ").count
        if tokenCount == 1 {
            let lowInfoSingles: Set<String> = ["current", "month", "week", "year", "spend", "spent"]
            if lowInfoSingles.contains(trimmed.lowercased()) {
                return false
            }
        }
        return true
    }

    private func isLikelyUnscopedMetricPhrase(_ text: String) -> Bool {
        let normalized = normalizeText(text)
        guard normalized.isEmpty == false else { return false }

        let subjectTokens = [
            "merchant", "merchants",
            "expense", "expenses",
            "transaction", "transactions",
            "purchase", "purchases",
            "category", "categories"
        ]
        let hasSubjectToken = subjectTokens.contains { normalized.contains($0) }
        guard hasSubjectToken else { return false }

        let rankingPhrases = [
            "top",
            "largest",
            "biggest",
            "highest",
            "most frequent",
            "least frequent"
        ]

        return rankingPhrases.contains { normalized.contains($0) }
    }

    private func isBroadQueryScaffoldingPhrase(_ text: String) -> Bool {
        let normalized = normalizeText(text)
        guard normalized.isEmpty == false else { return false }

        let broadPhrases = [
            "how much have i spent",
            "what s my total spending",
            "what is my total spending",
            "how much money went out",
            "show me what i spent",
            "where did most of my money go",
            "where is most of my money going",
            "who did i pay the most",
            "what stores did i spend the most at"
        ]

        return broadPhrases.contains { phrase in
            normalized == phrase || normalized.hasPrefix(phrase + " ")
        }
    }

    private func modifiers(from normalizedPrompt: String) -> [String] {
        var values: [String] = []
        if normalizedPrompt.contains("so far") { values.append("so_far") }
        if normalizedPrompt.contains("current") { values.append("current") }
        if normalizedPrompt.contains("last") { values.append("last") }
        if normalizedPrompt.contains("compare") || normalizedPrompt.contains("versus") || normalizedPrompt.contains(" vs ") {
            values.append("comparison")
        }
        if normalizedPrompt.contains("by category")
            || normalizedPrompt.contains("category breakdown")
            || normalizedPrompt.contains("categories breakdown") {
            values.append("breakdown_by_category")
        }
        if normalizedPrompt.contains("by merchant") { values.append("breakdown_by_merchant") }
        if normalizedPrompt.contains("by card") { values.append("breakdown_by_card") }
        if normalizedPrompt.contains("share of my spending")
            || normalizedPrompt.contains("share of spending")
            || normalizedPrompt.contains("percent of my spending")
            || normalizedPrompt.contains("percentage of my spending")
            || normalizedPrompt.contains("portion of my spending") {
            values.append("share_of_total")
        }
        return values
    }

    private func confidenceLevel(
        metric: MarinaNormalizedMetric?,
        rawTargetText: String?,
        usedCompatibilityFallback: Bool
    ) -> MarinaNLQConfidenceLevel {
        guard metric != nil else { return .low }
        if usedCompatibilityFallback {
            return rawTargetText == nil ? .low : .medium
        }
        if rawTargetText == nil { return .medium }
        return .high
    }

    private func normalizeText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shouldPromoteToCategorySpendTotalForCostMe(
        normalizedPrompt: String,
        metric: MarinaNormalizedMetric?,
        rawTargetText: String?,
        queryShape: MarinaQueryShape
    ) -> Bool {
        guard normalizedPrompt.contains("cost me"),
              let rawTargetText,
              rawTargetText.isEmpty == false else {
            return false
        }

        guard metric == .spendTotal || metric == nil else { return false }
        if queryShape.grouping == .merchant
            || queryShape.grouping == .transaction
            || queryShape.grouping == .some(.none) {
            return false
        }

        let normalizedTarget = normalizeText(rawTargetText)
        let merchantSignals = [" at ", " with ", "starbucks", "costco", "target", "merchant", "store", "vendor"]
        if merchantSignals.contains(where: normalizedPrompt.contains) {
            return false
        }
        if normalizedTarget.contains("card") || normalizedTarget.contains("merchant") || normalizedTarget.contains("store") {
            return false
        }

        return true
    }

    private func isWhatIfPrompt(_ normalizedPrompt: String) -> Bool {
        let whatIfPhrases = [
            "if i spend",
            "if i buy",
            "how will that affect",
            "can i still stay within",
            "what if"
        ]
        return whatIfPhrases.contains(where: normalizedPrompt.contains)
    }
}
