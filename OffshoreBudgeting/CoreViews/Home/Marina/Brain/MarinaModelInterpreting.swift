import Foundation

protocol MarinaModelInterpreting {
    func interpretedSemanticRequest(for prompt: String, context: MarinaBrainContext) async throws -> MarinaInterpretedSemanticRequest
}

extension MarinaModelInterpreting {
    func semanticRequest(for prompt: String, context: MarinaBrainContext) async throws -> MarinaSemanticRequest {
        try await interpretedSemanticRequest(for: prompt, context: context).request
    }
}

struct MarinaUnavailableModelInterpreter: MarinaModelInterpreting {
    func interpretedSemanticRequest(for prompt: String, context: MarinaBrainContext) async throws -> MarinaInterpretedSemanticRequest {
        MarinaInterpretedSemanticRequest(
            request: MarinaSemanticRequest(
                entity: .workspace,
                operation: .list,
                expectedAnswerShape: .unsupported,
                unsupportedReason: .unavailableModel
            ),
            confidence: .low,
            source: .unavailableFallback
        )
    }
}

struct MarinaRuleBasedInterpreter: MarinaModelInterpreting {
    func interpretedSemanticRequest(for prompt: String, context: MarinaBrainContext) async throws -> MarinaInterpretedSemanticRequest {
        interpretWithConfidence(prompt)
    }

    func interpret(_ prompt: String) -> MarinaSemanticRequest {
        semanticRequest(for: prompt)
    }

    func interpretWithConfidence(_ prompt: String) -> MarinaInterpretedSemanticRequest {
        let request = semanticRequest(for: prompt)
        let confidence: MarinaSemanticConfidence = request.unsupportedReason == .unsupportedCombination ? .low : .high
        return MarinaInterpretedSemanticRequest(
            request: request,
            confidence: confidence,
            source: .ruleBased
        )
    }

    private func semanticRequest(for prompt: String) -> MarinaSemanticRequest {
        let normalized = normalize(prompt)

        if containsAny(normalized, ["delete ", "remove ", "move ", "edit ", "change ", "rename "]) {
            return unsupported(.readOnly)
        }

        if normalized.contains("workspace") {
            if normalized.contains("color") {
                return MarinaSemanticRequest(
                    entity: .workspace,
                    operation: .list,
                    measure: .color,
                    dimensions: [.workspace],
                    expectedAnswerShape: .metric
                )
            }
            return MarinaSemanticRequest(
                entity: .workspace,
                operation: .list,
                measure: .name,
                dimensions: [.workspace],
                expectedAnswerShape: .metric
            )
        }

        if (normalized.contains("if ") || normalized.contains("what if") || normalized.contains("afford")),
           firstCurrencyAmount(in: normalized) != nil {
            return MarinaSemanticRequest(
                entity: .budget,
                operation: .whatIf,
                measure: normalized.contains("projected savings") || normalized.contains("savings") ? .savingsTotal : .remainingRoom,
                dimensions: categoryDimensionIfNeeded(normalized),
                dateRangeToken: dateToken(for: normalized),
                targetName: targetCategory(in: normalized),
                textQuery: merchantText(in: normalized),
                whatIfAmount: firstCurrencyAmount(in: normalized),
                expectedAnswerShape: .comparison
            )
        }

        if normalized.contains("how many cards") {
            return MarinaSemanticRequest(
                entity: .card,
                operation: .count,
                expectedAnswerShape: .metric
            )
        }

        if normalized.contains("savings") {
            if containsAny(normalized, ["projected", "forecast"]) {
                return MarinaSemanticRequest(
                    entity: .savingsAccount,
                    operation: .forecast,
                    measure: .savingsTotal,
                    dateRangeToken: dateToken(for: normalized),
                    expectedAnswerShape: .metric
                )
            }
            if containsAny(normalized, ["actual", "saved"]) {
                return MarinaSemanticRequest(
                    entity: .savingsAccount,
                    operation: .sum,
                    measure: .savingsTotal,
                    dateRangeToken: dateToken(for: normalized),
                    expectedAnswerShape: .metric
                )
            }
            return MarinaSemanticRequest(
                entity: .savingsAccount,
                operation: .sum,
                measure: .savingsTotal,
                dimensions: savingsTarget(in: normalized) == nil ? [] : [.savingsAccount],
                dateRangeToken: hasExplicitDateScope(normalized) ? dateToken(for: normalized) : .allTime,
                targetName: savingsTarget(in: normalized),
                expectedAnswerShape: .metric
            )
        }

        if normalized.contains("income") {
            let state: MarinaSemanticIncomeState = normalized.contains("planned income") && normalized.contains("actual income") == false
                ? .planned
                : (normalized.contains("actual") ? .actual : .all)
            if normalized.contains("percentage") || normalized.contains("percent") {
                return MarinaSemanticRequest(
                    entity: .income,
                    operation: .share,
                    measure: .incomeAmount,
                    dateRangeToken: dateToken(for: normalized),
                    incomeState: .actual,
                    expectedAnswerShape: .metric
                )
            }
            if normalized.contains("compare") {
                return MarinaSemanticRequest(
                    entity: .income,
                    operation: .compare,
                    measure: .incomeAmount,
                    dateRangeToken: dateToken(for: normalized),
                    incomeState: state,
                    expectedAnswerShape: .comparison
                )
            }
            return MarinaSemanticRequest(
                entity: .income,
                operation: normalized.contains("average") ? .average : .sum,
                measure: .incomeAmount,
                dimensions: sourceDimensionIfNeeded(normalized),
                dateRangeToken: dateToken(for: normalized),
                targetName: incomeSource(in: normalized),
                incomeState: state,
                expectedAnswerShape: .metric
            )
        }

        if normalized.contains("preset") || normalized.contains("presets") {
            if containsAny(normalized, ["due next", "next"]) {
                return MarinaSemanticRequest(
                    entity: .preset,
                    operation: .next,
                    measure: .plannedAmount,
                    dateRangeToken: dateToken(for: normalized),
                    sort: .dateAscending,
                    expectedAnswerShape: .metric
                )
            }
            if normalized.contains("actual amount greater than 0") || normalized.contains("actualized") {
                return MarinaSemanticRequest(
                    entity: .preset,
                    operation: .list,
                    measure: .actualAmount,
                    dateRangeToken: dateToken(for: normalized),
                    resultLimit: 10,
                    sort: .dateDescending,
                    expectedAnswerShape: .list
                )
            }
            if normalized.contains("most presets") || normalized.contains("most assigned") {
                return MarinaSemanticRequest(
                    entity: .preset,
                    operation: .group,
                    measure: .plannedAmount,
                    dimensions: [.category],
                    dateRangeToken: .allTime,
                    sort: .amountDescending,
                    expectedAnswerShape: .list
                )
            }
            if containsAny(normalized, ["tied to", "assigned to", "linked to"]) {
                return MarinaSemanticRequest(
                    entity: .preset,
                    operation: .list,
                    measure: .plannedAmount,
                    dimensions: [.category],
                    dateRangeToken: .allTime,
                    targetName: targetAfterAnyMarker(in: normalized, markers: ["tied to ", "assigned to ", "linked to "]),
                    resultLimit: firstInteger(in: normalized) ?? 10,
                    sort: .amountDescending,
                    expectedAnswerShape: .list
                )
            }
            return MarinaSemanticRequest(
                entity: .preset,
                operation: .list,
                measure: .plannedAmount,
                dateRangeToken: dateToken(for: normalized),
                expectedAnswerShape: .list
            )
        }

        if normalized.contains("budget") || normalized.contains("room") || normalized.contains("safe spend") || normalized.contains("afford") {
            if normalized.contains("if ") || normalized.contains("what if") || normalized.contains("afford") {
                return MarinaSemanticRequest(
                    entity: .budget,
                    operation: .whatIf,
                    measure: normalized.contains("projected savings") ? .savingsTotal : .remainingRoom,
                    dimensions: categoryDimensionIfNeeded(normalized),
                    dateRangeToken: dateToken(for: normalized),
                    targetName: targetCategory(in: normalized),
                    textQuery: merchantText(in: normalized),
                    whatIfAmount: firstCurrencyAmount(in: normalized),
                    expectedAnswerShape: .comparison
                )
            }
            if normalized.contains("compare") {
                return MarinaSemanticRequest(
                    entity: .budget,
                    operation: .compare,
                    measure: .budgetImpact,
                    dateRangeToken: dateToken(for: normalized),
                    expectedAnswerShape: .comparison
                )
            }
            return MarinaSemanticRequest(
                entity: .budget,
                operation: .forecast,
                measure: normalized.contains("room") ? .remainingRoom : .budgetImpact,
                dateRangeToken: dateToken(for: normalized),
                expectedAnswerShape: .metric
            )
        }

        if let reconciliationName = reconciliationTarget(in: normalized) {
            let hasCategory = targetCategory(in: normalized)
            return MarinaSemanticRequest(
                entity: .reconciliationAccount,
                operation: hasCategory == nil ? .sum : .sum,
                measure: .reconciliationBalance,
                dimensions: hasCategory == nil ? [] : [.category],
                dateRangeToken: reconciliationDateToken(for: normalized),
                targetName: reconciliationName,
                comparisonTargetName: nil,
                textQuery: hasCategory,
                resultLimit: nil,
                sort: nil,
                expenseScope: .unified,
                expectedAnswerShape: .metric
            )
        }

        if isGenericSpendPrompt(normalized), normalized.contains("compare") == false {
            let extractedTarget = spendTarget(in: normalized)
            let target = extractedTarget.map { normalize($0).contains("card") } == true
                ? extractedTarget
                : (merchantText(in: normalized) ?? extractedTarget)
            let isList = isListExpensePrompt(normalized)
            if let target, normalize(target).contains("card") {
                return MarinaSemanticRequest(
                    entity: isList ? .variableExpense : .card,
                    operation: isList ? .list : .sum,
                    measure: .budgetImpact,
                    dimensions: [.card],
                    dateRangeToken: dateToken(for: normalized),
                    targetName: target,
                    resultLimit: isList ? (firstInteger(in: normalized) ?? 5) : nil,
                    sort: isList ? .dateDescending : nil,
                    expenseScope: .unified,
                    expectedAnswerShape: isList ? .list : .metric
                )
            }
            return MarinaSemanticRequest(
                entity: .variableExpense,
                operation: isList ? .list : .sum,
                measure: .budgetImpact,
                dateRangeToken: dateToken(for: normalized),
                targetName: target,
                resultLimit: isList ? (firstInteger(in: normalized) ?? 5) : nil,
                sort: isList ? .dateDescending : nil,
                expenseScope: .unified,
                expectedAnswerShape: isList ? .list : .metric
            )
        }

        if normalized.contains("category") || normalized.contains("groceries") || normalized.contains("dining") || normalized.contains("food") {
            if normalized.contains("top") || normalized.contains("highest") || normalized.contains("most") {
                return MarinaSemanticRequest(
                    entity: .category,
                    operation: .group,
                    measure: .budgetImpact,
                    dimensions: [.category],
                    dateRangeToken: dateToken(for: normalized),
                    resultLimit: 5,
                    sort: .amountDescending,
                    expenseScope: .unified,
                    expectedAnswerShape: .list
                )
            }
            if normalized.contains("compare") {
                return MarinaSemanticRequest(
                    entity: .category,
                    operation: .compare,
                    measure: .budgetImpact,
                    dimensions: [.category],
                    dateRangeToken: dateToken(for: normalized),
                    targetName: targetCategory(in: normalized),
                    comparisonTargetName: comparisonTarget(in: normalized, after: " to "),
                    expenseScope: .unified,
                    expectedAnswerShape: .comparison
                )
            }
            return MarinaSemanticRequest(
                entity: .category,
                operation: .sum,
                measure: .budgetImpact,
                dimensions: [.category],
                dateRangeToken: dateToken(for: normalized),
                targetName: targetCategory(in: normalized),
                expenseScope: .unified,
                expectedAnswerShape: .metric
            )
        }

        if normalized.contains("card")
            || normalized.contains("chase")
            || normalized.contains("apple card")
            || normalized.contains("target")
            || normalized.contains("expense")
            || normalized.contains("shopping") {
            if normalized.contains("compare") {
                return MarinaSemanticRequest(
                    entity: .card,
                    operation: .compare,
                    measure: .budgetImpact,
                    dimensions: [.card],
                    dateRangeToken: dateToken(for: normalized),
                    targetName: cardTarget(in: normalized),
                    comparisonTargetName: comparisonTarget(in: normalized, after: " to "),
                    expenseScope: .unified,
                    expectedAnswerShape: .comparison
                )
            }
            if normalized.contains("last") || normalized.contains("when did") {
                return MarinaSemanticRequest(
                    entity: .variableExpense,
                    operation: .last,
                    measure: .budgetImpact,
                    dimensions: [.merchantText],
                    dateRangeToken: .allTime,
                    textQuery: merchantText(in: normalized),
                    expenseScope: .variable,
                    expectedAnswerShape: .metric
                )
            }
            if normalized.contains("list") || normalized.contains("recent") {
                return MarinaSemanticRequest(
                    entity: .variableExpense,
                    operation: .list,
                    measure: .budgetImpact,
                    dimensions: [.card],
                    dateRangeToken: dateToken(for: normalized),
                    targetName: cardTarget(in: normalized),
                    resultLimit: firstInteger(in: normalized) ?? 5,
                    sort: .dateDescending,
                    expenseScope: .variable,
                    expectedAnswerShape: .list
                )
            }
            if let merchant = merchantText(in: normalized), cardTarget(in: normalized) == nil {
                return MarinaSemanticRequest(
                    entity: .variableExpense,
                    operation: .sum,
                    measure: .budgetImpact,
                    dimensions: [.merchantText],
                    dateRangeToken: dateToken(for: normalized),
                    textQuery: merchant,
                    expenseScope: .variable,
                    expectedAnswerShape: .metric
                )
            }
            return MarinaSemanticRequest(
                entity: .card,
                operation: .sum,
                measure: .budgetImpact,
                dimensions: [.card],
                dateRangeToken: dateToken(for: normalized),
                targetName: cardTarget(in: normalized),
                expenseScope: .unified,
                expectedAnswerShape: .metric
            )
        }

        return unsupported(.unsupportedCombination)
    }

    private func unsupported(_ reason: MarinaSemanticUnsupportedReason) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .workspace,
            operation: .list,
            expectedAnswerShape: .unsupported,
            unsupportedReason: reason
        )
    }

    private func clarification(
        _ question: String,
        targetName: String? = nil,
        textQuery: String? = nil,
        dateRangeToken: MarinaSemanticDateRangeToken = .currentPeriod
    ) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .workspace,
            operation: .list,
            dateRangeToken: dateRangeToken,
            targetName: targetName,
            textQuery: textQuery,
            expectedAnswerShape: .clarification,
            clarificationQuestion: question,
            unsupportedReason: .ambiguousEntity
        )
    }

    private func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
    }

    private func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains { value.contains($0) }
    }

    private func dateToken(for normalized: String) -> MarinaSemanticDateRangeToken {
        if normalized.contains("this month") {
            return .currentMonth
        }
        if normalized.contains("last month") || normalized.contains("previous month") {
            return .previousMonth
        }
        if normalized.contains("last period") || normalized.contains("previous period") {
            return .previousPeriod
        }
        if normalized.contains("next 7 days") || normalized.contains("next seven days") {
            return .nextSevenDays
        }
        if normalized.contains("all time") || normalized.contains("ever") {
            return .allTime
        }
        return .currentPeriod
    }

    private func reconciliationDateToken(for normalized: String) -> MarinaSemanticDateRangeToken {
        if hasExplicitDateScope(normalized) {
            return dateToken(for: normalized)
        }
        if containsAny(normalized, ["balance", "owed", "owe"]) {
            return .allTime
        }
        return dateToken(for: normalized)
    }

    private func hasExplicitDateScope(_ normalized: String) -> Bool {
        containsAny(normalized, [
            "this period",
            "current period",
            "last period",
            "previous period",
            "this month",
            "current month",
            "last month",
            "previous month",
            "next 7 days",
            "next seven days",
            "all time",
            "ever"
        ])
    }

    private func sourceDimensionIfNeeded(_ normalized: String) -> [MarinaSemanticDimension] {
        incomeSource(in: normalized) == nil ? [] : [.incomeSource]
    }

    private func isGenericSpendPrompt(_ normalized: String) -> Bool {
        containsAny(normalized, [
            "spend",
            "spent",
            "expenses",
            "expense"
        ])
    }

    private func isListExpensePrompt(_ normalized: String) -> Bool {
        containsAny(normalized, ["show ", "list ", "recent", "expenses"])
    }

    private func spendTarget(in normalized: String) -> String? {
        if let target = targetAfterAnyMarker(in: normalized, markers: [
            "spend on ",
            "spent on ",
            "spend at ",
            "spent at ",
            "expenses on ",
            "expenses at ",
            "expense on ",
            "expense at "
        ]) {
            return target
        }

        if normalized.hasPrefix("show "), normalized.contains(" expenses") {
            let tail = String(normalized.dropFirst("show ".count))
            return targetBeforeAnyMarker(in: tail, markers: [" expenses"])
        }

        if normalized.hasPrefix("list "), normalized.contains(" expenses") {
            let tail = String(normalized.dropFirst("list ".count))
            return targetBeforeAnyMarker(in: tail, markers: [" expenses"])
        }

        if let target = targetBeforeAnyMarker(in: normalized, markers: [" spend"]) {
            return cleanedTarget(
                target
                    .replacingOccurrences(of: "what is my ", with: "")
                    .replacingOccurrences(of: "what's my ", with: "")
                    .replacingOccurrences(of: "how much is my ", with: "")
            )
        }

        return nil
    }

    private func targetAfterAnyMarker(in normalized: String, markers: [String]) -> String? {
        for marker in markers {
            guard let range = normalized.range(of: marker) else { continue }
            let tail = String(normalized[range.upperBound...])
            if let target = cleanedTarget(tail) {
                return target
            }
        }
        return nil
    }

    private func targetBeforeAnyMarker(in normalized: String, markers: [String]) -> String? {
        for marker in markers {
            guard let range = normalized.range(of: marker) else { continue }
            let head = String(normalized[..<range.lowerBound])
            if let target = cleanedTarget(head) {
                return target
            }
        }
        return nil
    }

    private func cleanedTarget(_ value: String) -> String? {
        var target = value
        for phrase in [
            " this month",
            " current month",
            " last month",
            " previous month",
            " this period",
            " current period",
            " last period",
            " previous period",
            " all time",
            " ever",
            " next 7 days",
            " next seven days"
        ] {
            target = target.replacingOccurrences(of: phrase, with: "")
        }
        target = target
            .replacingOccurrences(of: " my ", with: " ")
            .replacingOccurrences(of: " the ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if target.hasPrefix("my ") {
            target.removeFirst("my ".count)
        }
        if target.hasPrefix("the ") {
            target.removeFirst("the ".count)
        }
        guard target.isEmpty == false else { return nil }
        return target
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + String($0.dropFirst()) }
            .joined(separator: " ")
    }

    private func categoryDimensionIfNeeded(_ normalized: String) -> [MarinaSemanticDimension] {
        targetCategory(in: normalized) == nil ? [] : [.category]
    }

    private func incomeSource(in normalized: String) -> String? {
        knownTarget(in: normalized, candidates: ["salary", "freelance", "paycheck", "bonus"])
    }

    private func savingsTarget(in normalized: String) -> String? {
        if normalized.contains("savings account") {
            return "Savings Account"
        }
        return nil
    }

    private func targetCategory(in normalized: String) -> String? {
        knownTarget(in: normalized, candidates: ["groceries", "dining", "bills", "travel", "food"])
    }

    private func cardTarget(in normalized: String) -> String? {
        if normalized.contains("apple card") { return "Apple Card" }
        if normalized.contains("chase") { return "Chase" }
        return nil
    }

    private func reconciliationTarget(in normalized: String) -> String? {
        knownTarget(in: normalized, candidates: ["alejandro", "alex"])
    }

    private func merchantText(in normalized: String) -> String? {
        knownTarget(in: normalized, candidates: ["target", "starbucks", "amazon", "apple"])
    }

    private func knownTarget(in normalized: String, candidates: [String]) -> String? {
        guard let raw = candidates.first(where: { normalized.contains($0) }) else { return nil }
        return raw
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + String($0.dropFirst()) }
            .joined(separator: " ")
    }

    private func comparisonTarget(in normalized: String, after marker: String) -> String? {
        guard let range = normalized.range(of: marker) else { return nil }
        let tail = String(normalized[range.upperBound...])
        return cardTarget(in: tail) ?? targetCategory(in: tail) ?? incomeSource(in: tail)
    }

    private func firstCurrencyAmount(in normalized: String) -> Double? {
        let pattern = #"[$]?\s*([0-9]+(?:[.][0-9]+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = normalized as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: normalized, range: range),
              match.numberOfRanges > 1 else {
            return nil
        }
        let raw = ns.substring(with: match.range(at: 1))
        return Double(raw)
    }

    private func firstInteger(in normalized: String) -> Int? {
        let pattern = #"(?<![.])\b([0-9]+)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = normalized as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: normalized, range: range),
              match.numberOfRanges > 1 else {
            return nil
        }
        return Int(ns.substring(with: match.range(at: 1)))
    }
}
