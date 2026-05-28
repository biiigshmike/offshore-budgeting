import Foundation

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

        if let summaryTarget = summaryTarget(in: normalized) {
            return summaryRequest(for: summaryTarget, normalized: normalized)
        }

        if let categoryAvailabilityRequest = categoryAvailabilityRequest(for: normalized) {
            return categoryAvailabilityRequest
        }

        if containsAny(normalized, ["next planned expense", "upcoming planned expense"]) {
            let cardName = typedTarget(in: normalized, typeWords: ["card", "cards"])
            return MarinaSemanticRequest(
                entity: .plannedExpense,
                operation: .next,
                measure: .effectiveAmount,
                dimensions: cardName == nil ? [] : [.card],
                dateRangeToken: dateToken(for: normalized),
                targetName: cardName,
                sort: .dateAscending,
                expenseScope: .planned,
                expectedAnswerShape: .metric
            )
        }

        if normalized.contains("spend trends") || normalized.contains("spending trends") {
            return MarinaSemanticRequest(
                entity: .category,
                operation: .group,
                measure: .budgetImpact,
                dimensions: [.category, .date],
                dateRangeToken: dateToken(for: normalized),
                resultLimit: 3,
                sort: .amountDescending,
                expenseScope: .unified,
                expectedAnswerShape: .list
            )
        }

        if normalized.contains("category spotlight") {
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

        if (normalized.contains("if ") || normalized.contains("what if") || normalized.contains("afford")),
           firstCurrencyAmount(in: normalized) != nil {
            let whatIfTarget = whatIfTarget(in: normalized)
            return MarinaSemanticRequest(
                entity: .budget,
                operation: .whatIf,
                measure: normalized.contains("projected savings") || normalized.contains("savings") ? .savingsTotal : .remainingRoom,
                dimensions: whatIfTarget == nil ? [] : [.category],
                dateRangeToken: dateToken(for: normalized),
                targetName: whatIfTarget,
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
            if containsAny(normalized, ["savings outlook", "projected", "forecast"]) {
                return MarinaSemanticRequest(
                    entity: .savingsAccount,
                    operation: .forecast,
                    measure: .savingsTotal,
                    dateRangeToken: dateToken(for: normalized),
                    expectedAnswerShape: .metric
                )
            }
            if containsAny(normalized, ["actual savings", "actual", "saved"]) {
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
            if normalized.contains("progress") || normalized.contains("percentage") || normalized.contains("percent") {
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
                    dimensions: sourceDimensionIfNeeded(normalized),
                    dateRangeToken: dateToken(for: normalized),
                    targetName: incomeSource(in: normalized),
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

        if normalized.contains("budget") || normalized.contains("room") || normalized.contains("safe spend") || normalized.contains("afford") || normalized.contains("can i spend") {
            if normalized.contains("if ") || normalized.contains("what if") || normalized.contains("afford") {
                let whatIfTarget = whatIfTarget(in: normalized)
                return MarinaSemanticRequest(
                    entity: .budget,
                    operation: .whatIf,
                    measure: normalized.contains("projected savings") ? .savingsTotal : .remainingRoom,
                    dimensions: whatIfTarget == nil ? [] : [.category],
                    dateRangeToken: dateToken(for: normalized),
                    targetName: whatIfTarget,
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
                measure: containsAny(normalized, ["room", "safe spend", "can i spend"]) ? .remainingRoom : .budgetImpact,
                dateRangeToken: dateToken(for: normalized),
                expectedAnswerShape: .metric
            )
        }

        if let sharedSpend = sharedSpendTarget(in: normalized) {
            return MarinaSemanticRequest(
                entity: .reconciliationAccount,
                operation: .sum,
                measure: .reconciliationBalance,
                dimensions: sharedSpend.categoryName == nil ? [] : [.category],
                dateRangeToken: reconciliationDateToken(for: normalized),
                targetName: sharedSpend.accountName,
                comparisonTargetName: nil,
                textQuery: sharedSpend.categoryName,
                resultLimit: nil,
                sort: nil,
                expenseScope: .unified,
                expectedAnswerShape: .metric
            )
        }

        if let balanceTarget = balanceTarget(in: normalized) {
            return MarinaSemanticRequest(
                entity: .reconciliationAccount,
                operation: .sum,
                measure: .reconciliationBalance,
                dimensions: [.reconciliationAccount],
                dateRangeToken: reconciliationDateToken(for: normalized),
                targetName: balanceTarget,
                expenseScope: .unified,
                expectedAnswerShape: .metric
            )
        }

        if normalized.contains("compare"), let comparison = spendComparisonTargets(in: normalized) {
            let targetContainsCard = normalize(comparison.left).contains("card") || normalize(comparison.right).contains("card")
            return MarinaSemanticRequest(
                entity: targetContainsCard ? .card : .variableExpense,
                operation: .compare,
                measure: .budgetImpact,
                dimensions: targetContainsCard ? [.card] : [],
                dateRangeToken: dateToken(for: normalized),
                targetName: comparison.left,
                comparisonTargetName: comparison.right,
                expenseScope: .unified,
                expectedAnswerShape: .comparison
            )
        }

        if isGenericSpendPrompt(normalized), normalized.contains("compare") == false {
            let extractedTarget = spendTarget(in: normalized)
            let explicitTextTarget = expenseTextTarget(in: normalized)
            let rawTarget = explicitTextTarget ?? extractedTarget
            let target = rawTarget.flatMap { isGenericEntityTarget($0) ? nil : $0 }
            let isList = isListExpensePrompt(normalized)
            if let explicitTextTarget {
                return MarinaSemanticRequest(
                    entity: .variableExpense,
                    operation: isList ? .list : .sum,
                    measure: .budgetImpact,
                    dimensions: [.merchantText],
                    dateRangeToken: dateToken(for: normalized),
                    textQuery: explicitTextTarget,
                    resultLimit: isList ? (firstInteger(in: normalized) ?? 5) : nil,
                    sort: isList ? .dateDescending : nil,
                    expenseScope: .unified,
                    expectedAnswerShape: isList ? .list : .metric
                )
            }
            if target == nil, normalized.contains("card") {
                return MarinaSemanticRequest(
                    entity: .card,
                    operation: .sum,
                    measure: .budgetImpact,
                    dimensions: [.card],
                    dateRangeToken: dateToken(for: normalized),
                    expenseScope: .unified,
                    expectedAnswerShape: .metric
                )
            }
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

        if normalized.contains("category") {
            let categoryName = typedTarget(in: normalized, typeWords: ["category", "categories"])
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
                    targetName: categoryName,
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
                targetName: categoryName,
                expenseScope: .unified,
                expectedAnswerShape: .metric
            )
        }

        if normalized.contains("card")
            || normalized.contains("expense")
            || normalized.contains("shopping") {
            let cardName = typedTarget(in: normalized, typeWords: ["card", "cards"]) ?? spendTarget(in: normalized)
            if normalized.contains("compare") {
                let comparison = spendComparisonTargets(in: normalized)
                return MarinaSemanticRequest(
                    entity: .card,
                    operation: .compare,
                    measure: .budgetImpact,
                    dimensions: [.card],
                    dateRangeToken: dateToken(for: normalized),
                    targetName: comparison?.left ?? cardName,
                    comparisonTargetName: comparison?.right ?? comparisonTarget(in: normalized, after: " to "),
                    expenseScope: .unified,
                    expectedAnswerShape: .comparison
                )
            }
            if normalized.contains("last") || normalized.contains("when did") {
                return MarinaSemanticRequest(
                    entity: .variableExpense,
                    operation: .last,
                    measure: .budgetImpact,
                    dimensions: [],
                    dateRangeToken: .allTime,
                    targetName: lastExpenseTarget(in: normalized),
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
                    targetName: cardName,
                    resultLimit: firstInteger(in: normalized) ?? 5,
                    sort: .dateDescending,
                    expenseScope: .variable,
                    expectedAnswerShape: .list
                )
            }
            if let explicitTextTarget = expenseTextTarget(in: normalized), cardName == nil {
                return MarinaSemanticRequest(
                    entity: .variableExpense,
                    operation: .sum,
                    measure: .budgetImpact,
                    dimensions: [.merchantText],
                    dateRangeToken: dateToken(for: normalized),
                    textQuery: explicitTextTarget,
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
                targetName: cardName,
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

    private func categoryAvailabilityRequest(for normalized: String) -> MarinaSemanticRequest? {
        let filter = categoryAvailabilityFilter(in: normalized)
        let mentionsAvailabilitySummary = containsAny(normalized, [
            "category availability",
            "category limits",
            "category limit"
        ])
        let mentionsCategoryLimitStatus = normalized.contains("categor") && filter != nil

        guard mentionsAvailabilitySummary || mentionsCategoryLimitStatus else {
            return nil
        }

        let asksForRows = filter != nil && (
            containsAny(normalized, ["which", "list", "show", "what categories", "categories are"])
            || firstInteger(in: normalized) != nil
        )

        if asksForRows {
            return MarinaSemanticRequest(
                entity: .category,
                operation: .list,
                measure: .categoryAvailability,
                dimensions: [.category],
                dateRangeToken: dateToken(for: normalized),
                resultLimit: firstInteger(in: normalized) ?? 5,
                categoryAvailabilityFilter: filter,
                expectedAnswerShape: .list
            )
        }

        return MarinaSemanticRequest(
            entity: .category,
            operation: .forecast,
            measure: .categoryAvailability,
            dimensions: [.category],
            dateRangeToken: dateToken(for: normalized),
            expectedAnswerShape: .metric
        )
    }

    private func categoryAvailabilityFilter(in normalized: String) -> MarinaCategoryAvailabilityFilter? {
        if containsAny(normalized, [
            "over limit",
            "over budget",
            "over category limit",
            "categories over",
            "category over"
        ]) {
            return .over
        }

        if containsAny(normalized, [
            "near limit",
            "near budget",
            "near category limit",
            "categories near",
            "category near"
        ]) {
            return .near
        }

        if containsAny(normalized, [
            "under limit",
            "under budget",
            "within limit",
            "below limit",
            "under category limit",
            "categories under",
            "category under"
        ]) {
            return .underLimit
        }

        return nil
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

    private func summaryTarget(in normalized: String) -> String? {
        targetAfterAnyMarker(in: normalized, markers: [
            "summarize my ",
            "summarize the ",
            "summarize ",
            "summary of my ",
            "summary of the ",
            "summary of ",
            "summary for my ",
            "summary for the ",
            "summary for "
        ])
    }

    private func summaryRequest(for target: String, normalized: String) -> MarinaSemanticRequest {
        let targetNormalized = normalize(target)

        if targetNormalized.contains("card") {
            return MarinaSemanticRequest(
                entity: .card,
                operation: .sum,
                measure: .budgetImpact,
                dimensions: [.card],
                dateRangeToken: dateToken(for: normalized),
                targetName: target,
                expenseScope: .unified,
                expectedAnswerShape: .metric
            )
        }

        if targetNormalized.contains("savings") {
            return MarinaSemanticRequest(
                entity: .savingsAccount,
                operation: .sum,
                measure: .savingsTotal,
                dimensions: [.savingsAccount],
                dateRangeToken: hasExplicitDateScope(normalized) ? dateToken(for: normalized) : .allTime,
                targetName: target,
                expectedAnswerShape: .metric
            )
        }

        if targetNormalized.contains("income") {
            let source = strippedTarget(target, typeWords: ["income", "source"])
            return MarinaSemanticRequest(
                entity: .income,
                operation: .sum,
                measure: .incomeAmount,
                dimensions: source == nil ? [] : [.incomeSource],
                dateRangeToken: dateToken(for: normalized),
                targetName: source,
                incomeState: .all,
                expectedAnswerShape: .metric
            )
        }

        if targetNormalized.contains("preset") {
            return MarinaSemanticRequest(
                entity: .preset,
                operation: .sum,
                measure: .plannedAmount,
                dimensions: [.preset],
                dateRangeToken: dateToken(for: normalized),
                targetName: strippedTarget(target, typeWords: ["preset", "presets"]) ?? target,
                expectedAnswerShape: .metric
            )
        }

        if targetNormalized.contains("budget") {
            return MarinaSemanticRequest(
                entity: .budget,
                operation: .forecast,
                measure: .budgetImpact,
                dimensions: [.budget],
                dateRangeToken: dateToken(for: normalized),
                targetName: strippedTarget(target, typeWords: ["budget", "budgets"]) ?? target,
                expectedAnswerShape: .metric
            )
        }

        if targetNormalized.contains("category") {
            return MarinaSemanticRequest(
                entity: .category,
                operation: .sum,
                measure: .budgetImpact,
                dimensions: [.category],
                dateRangeToken: dateToken(for: normalized),
                targetName: strippedTarget(target, typeWords: ["category", "categories"]) ?? target,
                expenseScope: .unified,
                expectedAnswerShape: .metric
            )
        }

        return MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            dateRangeToken: dateToken(for: normalized),
            targetName: target,
            expenseScope: .unified,
            expectedAnswerShape: .metric
        )
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

    private func whatIfTarget(in normalized: String) -> String? {
        targetAfterAnyMarkerWithStop(
            in: normalized,
            markers: [" on "],
            stopMarkers: [" what happens", " how does", " to my", " to projected", " for "]
        )
    }

    private func expenseTextTarget(in normalized: String) -> String? {
        targetAfterAnyMarker(in: normalized, markers: [
            "merchant named ",
            "merchant ",
            "store named ",
            "store ",
            "vendor named ",
            "vendor ",
            "title named ",
            "title ",
            "description named ",
            "description "
        ])
    }

    private func lastExpenseTarget(in normalized: String) -> String? {
        targetAfterAnyMarkerWithStop(
            in: normalized,
            markers: [" shopping at ", " shopping on ", " at ", " on "],
            stopMarkers: [" this month", " this period", " last month", " last period"]
        )
    }

    private func sharedSpendTarget(in normalized: String) -> (accountName: String, categoryName: String?)? {
        guard let didRange = normalized.range(of: "did "),
              let spendRange = normalized.range(of: " spend", range: didRange.upperBound..<normalized.endIndex),
              didRange.upperBound < spendRange.lowerBound else {
            return nil
        }

        let rawAccount = String(normalized[didRange.upperBound..<spendRange.lowerBound])
        guard let accountName = cleanedTarget(rawAccount) else { return nil }
        guard isFirstPersonTarget(accountName) == false else { return nil }
        let categoryName = targetAfterAnyMarkerWithStop(
            in: String(normalized[spendRange.upperBound...]),
            markers: [" on ", " at "],
            stopMarkers: [" for ", " this month", " this period", " current period", " current month"]
        )
        return (accountName, categoryName)
    }

    private func balanceTarget(in normalized: String) -> String? {
        targetBeforeAnyMarker(in: normalized, markers: [
            " balance",
            " owed",
            " owe"
        ])
    }

    private func spendComparisonTargets(in normalized: String) -> (left: String, right: String)? {
        guard let compareRange = normalized.range(of: "compare ") else { return nil }
        let tail = String(normalized[compareRange.upperBound...])
        guard let separator = tail.range(of: " to ") ?? tail.range(of: " with ") else { return nil }
        let leftRaw = String(tail[..<separator.lowerBound])
        let rightRaw = String(tail[separator.upperBound...])
        guard let left = comparisonTarget(from: leftRaw),
              let right = comparisonTarget(from: rightRaw) else {
            return nil
        }
        return (left, right)
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

    private func targetAfterAnyMarkerWithStop(in normalized: String, markers: [String], stopMarkers: [String]) -> String? {
        for marker in markers {
            guard let range = normalized.range(of: marker) else { continue }
            let tail = String(normalized[range.upperBound...])
            let stopped = prefixBeforeAnyMarker(in: tail, markers: stopMarkers) ?? tail
            if let target = cleanedTarget(stopped) {
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

    private func prefixBeforeAnyMarker(in value: String, markers: [String]) -> String? {
        let matches = markers.compactMap { marker -> String.Index? in
            value.range(of: marker)?.lowerBound
        }
        guard let first = matches.min() else { return nil }
        return String(value[..<first])
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
        for phrase in [
            "what is my ",
            "what's my ",
            "what is ",
            "what's ",
            "how much is my ",
            "how much is ",
            "how much did i ",
            "show my ",
            "show ",
            "list my ",
            "list ",
            "summarize my ",
            "summarize the ",
            "summarize ",
            "compare my ",
            "compare the ",
            "compare ",
            "for "
        ] {
            if target.hasPrefix(phrase) {
                target.removeFirst(phrase.count)
            }
        }
        target = target
            .replacingOccurrences(of: "'s", with: "")
            .replacingOccurrences(of: " my ", with: " ")
            .replacingOccurrences(of: " the ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["my ", "the ", "current ", "actual ", "planned ", "total "] {
            if target.hasPrefix(prefix) {
                target.removeFirst(prefix.count)
            }
        }
        if ["current", "actual", "planned", "total"].contains(target) {
            return nil
        }
        guard target.isEmpty == false else { return nil }
        return target
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + String($0.dropFirst()) }
            .joined(separator: " ")
    }

    private func incomeSource(in normalized: String) -> String? {
        if let target = targetAfterAnyMarker(in: normalized, markers: [
            "income from ",
            "income source ",
            "source "
        ]) {
            return target
        }
        return typedTarget(in: normalized, typeWords: ["income"])
    }

    private func savingsTarget(in normalized: String) -> String? {
        if normalized.contains("savings account"),
           let target = targetBeforeAnyMarker(in: normalized, markers: [" balance", " total"]) {
            return target
        }
        return typedTarget(in: normalized, typeWords: ["savings account", "savings"])
    }

    private func typedTarget(in normalized: String, typeWords: [String]) -> String? {
        for typeWord in typeWords.sorted(by: { $0.count > $1.count }) {
            if let target = targetBeforeAnyMarker(in: normalized, markers: [" \(typeWord)"]) {
                if shouldKeepTypeWord(typeWord) {
                    return cleanedTarget("\(target) \(typeWord)")
                }
                return strippedTarget(target, typeWords: typeWords) ?? target
            }

            if let target = targetAfterAnyMarker(in: normalized, markers: [
                "\(typeWord) named ",
                "\(typeWord) called "
            ]) {
                return target
            }
        }
        return nil
    }

    private func isFirstPersonTarget(_ target: String) -> Bool {
        ["I", "Me", "My", "We", "Us", "Our"].contains(target)
    }

    private func isGenericEntityTarget(_ target: String) -> Bool {
        [
            "Budget",
            "Budgets",
            "Card",
            "Cards",
            "Category",
            "Categories",
            "Expense",
            "Expenses",
            "Income",
            "Preset",
            "Presets",
            "Savings"
        ].contains(target)
    }

    private func shouldKeepTypeWord(_ typeWord: String) -> Bool {
        typeWord == "card" || typeWord == "cards" || typeWord.contains("savings")
    }

    private func strippedTarget(_ target: String, typeWords: [String]) -> String? {
        let typeWordSet = Set(typeWords.flatMap { word in
            word.split(separator: " ").map { String($0).lowercased() }
        })
        let words = target.split(separator: " ").filter { word in
            typeWordSet.contains(String(word).lowercased()) == false
        }
        guard words.isEmpty == false else { return nil }
        return words
            .map { $0.prefix(1).uppercased() + String($0.dropFirst()) }
            .joined(separator: " ")
    }

    private func comparisonTarget(in normalized: String, after marker: String) -> String? {
        guard let range = normalized.range(of: marker) else { return nil }
        let tail = String(normalized[range.upperBound...])
        return comparisonTarget(from: tail)
    }

    private func comparisonTarget(from value: String) -> String? {
        if let target = targetBeforeAnyMarker(in: value, markers: [" spend", " spending", " expenses", " income"]) {
            return target
        }
        return cleanedTarget(value)
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
