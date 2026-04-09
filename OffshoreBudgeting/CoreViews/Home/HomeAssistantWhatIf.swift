//
//  HomeAssistantWhatIf.swift
//  OffshoreBudgeting
//
//  Created by OpenAI on 4/9/26.
//

import Foundation

struct HomeAssistantWhatIfPlannerDraft: Equatable {
    let categoryScenarioSpendByID: [UUID: Double]
    let plannedIncomeOverride: Double?
    let actualIncomeOverride: Double?
    let sourcePrompt: String
    let summary: String
}

enum HomeAssistantWhatIfTargetKind: Equatable {
    case merchant
    case category(UUID)
    case actualIncome
    case plannedIncome
}

enum HomeAssistantWhatIfValueMode: Equatable {
    case additionalAmount(Double)
    case recurringAmount(amount: Double, minimumDayInterval: Int, maximumDayInterval: Int)
    case setAmount(Double)
    case adjustAmount(Double)
    case adjustPercent(Double)
}

struct HomeAssistantWhatIfRequest: Equatable {
    let targetKind: HomeAssistantWhatIfTargetKind
    let targetName: String?
    let valueMode: HomeAssistantWhatIfValueMode
    let dateRange: HomeQueryDateRange?
    let isAffordabilityPrompt: Bool
}

enum HomeAssistantWhatIfParseResult: Equatable {
    case request(HomeAssistantWhatIfRequest)
    case clarification(String)
}

struct HomeAssistantWhatIfContext: Equatable {
    let request: HomeAssistantWhatIfRequest
    let resolvedDateRange: HomeQueryDateRange
    let directPlannerDraft: HomeAssistantWhatIfPlannerDraft?
    let exactAdditionalSpendForPlanner: Double?
    let requiresPlannerCategoryName: Bool
    let requiresExactCadenceSelection: Bool
}

struct HomeAssistantWhatIfAnswerBuildResult {
    let rawAnswer: HomeAnswer
    let primaryQuery: HomeQuery
    let footerQueries: [HomeQuery]
    let context: HomeAssistantWhatIfContext
}

struct HomeAssistantWhatIfParser {
    private let calendar: Calendar
    private let nowProvider: () -> Date

    init(
        calendar: Calendar = .current,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.calendar = calendar
        self.nowProvider = nowProvider
    }

    func parse(
        _ rawText: String,
        categories: [Category],
        fallbackDateRange: HomeQueryDateRange?,
        dateParser: HomeAssistantTextParser,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> HomeAssistantWhatIfParseResult? {
        let normalized = normalizedPrompt(rawText)
        guard normalized.isEmpty == false else { return nil }

        let isWhatIfPrompt = normalized.contains("what if")
            || normalized.contains("can i afford")
            || normalized.hasPrefix("if ")
        guard isWhatIfPrompt else { return nil }

        if normalized.contains("can i afford"),
           containsExplicitWhatIfAmount(normalized) == false {
            return .clarification("Tell me the amount and timing you want me to test, like 25 every 4 days or an extra 100 this month.")
        }

        let resolvedDateRange = dateParser.parseDateRange(
            rawText,
            defaultPeriodUnit: defaultPeriodUnit
        ) ?? fallbackDateRange ?? monthRange(containing: nowProvider())

        if let incomeRequest = parseIncomeRequest(normalized, dateRange: resolvedDateRange) {
            return .request(incomeRequest)
        }

        if let recurringRequest = parseRecurringRequest(
            normalized,
            categories: categories,
            dateRange: resolvedDateRange,
            isAffordabilityPrompt: normalized.contains("can i afford")
        ) {
            return .request(recurringRequest)
        }

        if let additionalRequest = parseAdditionalSpendRequest(
            normalized,
            categories: categories,
            dateRange: resolvedDateRange,
            isAffordabilityPrompt: normalized.contains("can i afford")
        ) {
            return .request(additionalRequest)
        }

        if let categoryRequest = parseCategoryAdjustmentRequest(
            normalized,
            categories: categories,
            dateRange: resolvedDateRange
        ) {
            return .request(categoryRequest)
        }

        return .clarification("I can run a What If if you give me one concrete change, like an extra amount, a cadence, a category total, or an income amount.")
    }

    private func containsExplicitWhatIfAmount(_ normalized: String) -> Bool {
        captureFirst(normalized, pattern: "(\\d+(?:\\.\\d+)?)") != nil
    }

    private func parseIncomeRequest(
        _ normalized: String,
        dateRange: HomeQueryDateRange
    ) -> HomeAssistantWhatIfRequest? {
        guard let amount = captureAmount(
            normalized,
            patterns: [
                "\\bactual income\\s+(?:was|were|is|to)\\s+(\\d+(?:\\.\\d+)?)\\b",
                "\\bincome\\s+(?:was|were|is|to)\\s+(\\d+(?:\\.\\d+)?)\\b"
            ]
        ) else {
            if let plannedAmount = captureAmount(
                normalized,
                patterns: [
                    "\\bplanned income\\s+(?:was|were|is|to)\\s+(\\d+(?:\\.\\d+)?)\\b"
                ]
            ) {
                return HomeAssistantWhatIfRequest(
                    targetKind: .plannedIncome,
                    targetName: "Planned income",
                    valueMode: .setAmount(plannedAmount),
                    dateRange: dateRange,
                    isAffordabilityPrompt: false
                )
            }
            return nil
        }

        let targetKind: HomeAssistantWhatIfTargetKind = normalized.contains("planned income") ? .plannedIncome : .actualIncome
        let targetName: String
        switch targetKind {
        case .plannedIncome:
            targetName = "Planned income"
        default:
            targetName = "Actual income"
        }
        return HomeAssistantWhatIfRequest(
            targetKind: targetKind,
            targetName: targetName,
            valueMode: .setAmount(amount),
            dateRange: dateRange,
            isAffordabilityPrompt: false
        )
    }

    private func parseRecurringRequest(
        _ normalized: String,
        categories: [Category],
        dateRange: HomeQueryDateRange,
        isAffordabilityPrompt: Bool
    ) -> HomeAssistantWhatIfRequest? {
        let patterns = [
            "\\b(?:were\\s+to\\s+)?(?:start\\s+)?(?:spend(?:ing)?\\s+)?(\\d+(?:\\.\\d+)?)\\s*(?:every|per)\\s*(\\d+)(?:\\s+or\\s+(\\d+))?\\s+days?\\b",
            "\\b(?:were\\s+to\\s+)?(?:start\\s+)?(?:spend(?:ing)?\\s+)?(\\d+(?:\\.\\d+)?)\\s*(?:a\\s+|per\\s+)?(?:day|daily)\\b",
            "\\b(?:were\\s+to\\s+)?(?:start\\s+)?(?:spend(?:ing)?\\s+)?(\\d+(?:\\.\\d+)?)\\s+a\\s+week\\b",
            "\\b(?:were\\s+to\\s+)?(?:start\\s+)?(?:spend(?:ing)?\\s+)?(\\d+(?:\\.\\d+)?)\\s+every\\s+week\\b",
            "\\b(?:were\\s+to\\s+)?(?:start\\s+)?(?:spend(?:ing)?\\s+)?(\\d+(?:\\.\\d+)?)\\s*(?:per\\s+)?(?:week|wk|weekly)\\b",
            "\\b(?:cost me|costs me)\\s+(\\d+(?:\\.\\d+)?)\\s*(?:per\\s+)?(?:week|wk|weekly)\\b",
            "\\b[a-z0-9 '&\\-\\.]+\\s+cost(?:s)?\\s+me\\s+(\\d+(?:\\.\\d+)?)\\s*(?:per\\s+)?(?:week|wk|weekly)\\b",
            "\\b[a-z0-9 '&\\-\\.]+\\s+run(?:s)?\\s+me\\s+(\\d+(?:\\.\\d+)?)\\s*(?:per\\s+)?(?:week|wk|weekly)\\b"
        ]

        for pattern in patterns {
            guard let captures = captureGroups(normalized, pattern: pattern) else { continue }
            guard let amount = Double(captures[0]) else { continue }

            let minimumDayInterval: Int
            let maximumDayInterval: Int
            if captures.count >= 2, let firstInterval = Int(captures[1]) {
                minimumDayInterval = firstInterval
                maximumDayInterval = Int(captures[safe: 2] ?? "") ?? firstInterval
            } else if pattern.contains("day|daily") {
                minimumDayInterval = 1
                maximumDayInterval = 1
            } else {
                minimumDayInterval = 7
                maximumDayInterval = 7
            }

            guard let resolvedTarget = resolveTarget(normalized, categories: categories) else {
                return nil
            }

            return HomeAssistantWhatIfRequest(
                targetKind: resolvedTarget.kind,
                targetName: resolvedTarget.name,
                valueMode: .recurringAmount(
                    amount: amount,
                    minimumDayInterval: min(minimumDayInterval, maximumDayInterval),
                    maximumDayInterval: max(minimumDayInterval, maximumDayInterval)
                ),
                dateRange: dateRange,
                isAffordabilityPrompt: isAffordabilityPrompt
            )
        }

        return nil
    }

    private func parseAdditionalSpendRequest(
        _ normalized: String,
        categories: [Category],
        dateRange: HomeQueryDateRange,
        isAffordabilityPrompt: Bool
    ) -> HomeAssistantWhatIfRequest? {
        let patterns = [
            "\\b(?:spent|spend)\\s+(?:an\\s+)?additional\\s+(\\d+(?:\\.\\d+)?)\\b",
            "\\badditional\\s+(\\d+(?:\\.\\d+)?)\\b"
        ]

        guard let amount = captureAmount(normalized, patterns: patterns) else { return nil }
        guard let resolvedTarget = resolveTarget(normalized, categories: categories) else { return nil }

        return HomeAssistantWhatIfRequest(
            targetKind: resolvedTarget.kind,
            targetName: resolvedTarget.name,
            valueMode: .additionalAmount(amount),
            dateRange: dateRange,
            isAffordabilityPrompt: isAffordabilityPrompt
        )
    }

    private func parseCategoryAdjustmentRequest(
        _ normalized: String,
        categories: [Category],
        dateRange: HomeQueryDateRange
    ) -> HomeAssistantWhatIfRequest? {
        guard let category = bestCategoryMatch(in: normalized, categories: categories) else { return nil }
        let categoryName = category.name

        if let amount = captureAmount(
            normalized,
            patterns: [
                "\\b\(NSRegularExpression.escapedPattern(for: normalizedPrompt(categoryName)))\\s+(?:was|were|is|to)\\s+(\\d+(?:\\.\\d+)?)\\b",
                "\\bspent\\s+(\\d+(?:\\.\\d+)?)\\s+on\\s+\(NSRegularExpression.escapedPattern(for: normalizedPrompt(categoryName)))\\b"
            ]
        ) {
            return HomeAssistantWhatIfRequest(
                targetKind: .category(category.id),
                targetName: categoryName,
                valueMode: .setAmount(amount),
                dateRange: dateRange,
                isAffordabilityPrompt: false
            )
        }

        if let captures = captureGroups(
            normalized,
            pattern: "\\b(cut|reduce|decrease|increase|add)\\s+\(NSRegularExpression.escapedPattern(for: normalizedPrompt(categoryName)))\\s+by\\s+(\\d+(?:\\.\\d+)?)\\s*(percent|%)?\\b"
        ), captures.count >= 2 {
            let verb = captures[0]
            let amountString = captures[1]
            let isPercent = captures[safe: 2]?.isEmpty == false
            guard let amount = Double(amountString) else { return nil }
            let sign = ["cut", "reduce", "decrease"].contains(verb) ? -1.0 : 1.0
            let mode: HomeAssistantWhatIfValueMode = isPercent
                ? .adjustPercent(sign * amount)
                : .adjustAmount(sign * amount)
            return HomeAssistantWhatIfRequest(
                targetKind: .category(category.id),
                targetName: categoryName,
                valueMode: mode,
                dateRange: dateRange,
                isAffordabilityPrompt: false
            )
        }

        return nil
    }

    private func resolveTarget(
        _ normalized: String,
        categories: [Category]
    ) -> (kind: HomeAssistantWhatIfTargetKind, name: String)? {
        if let category = bestCategoryMatch(in: normalized, categories: categories) {
            return (.category(category.id), category.name)
        }

        if let merchant = extractMerchantName(from: normalized) {
            return (.merchant, merchant)
        }

        return nil
    }

    private func bestCategoryMatch(
        in normalized: String,
        categories: [Category]
    ) -> Category? {
        let sorted = categories.sorted { $0.name.count > $1.name.count }
        return sorted.first { category in
            let name = normalizedPrompt(category.name)
            return normalized.contains(name)
        }
    }

    private func extractMerchantName(from normalized: String) -> String? {
        let leadingPatterns = [
            "^what if ([a-z0-9 '&\\-\\.]+?)\\s+(?:cost me|costs me)\\s+\\d",
            "^if ([a-z0-9 '&\\-\\.]+?)\\s+(?:cost me|costs me)\\s+\\d",
            "^what if ([a-z0-9 '&\\-\\.]+?)\\s+run(?:s)?\\s+me\\s+\\d",
            "^if ([a-z0-9 '&\\-\\.]+?)\\s+run(?:s)?\\s+me\\s+\\d"
        ]

        for pattern in leadingPatterns {
            if let merchant = captureFirst(normalized, pattern: pattern) {
                let cleaned = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.isEmpty == false {
                    return cleaned.capitalized
                }
            }
        }

        let markers = [" at ", " with ", " from ", " on "]
        let stopMarkers = [
            " this ", " last ", " every ", " per ", " month", " week", " weekly", " wk", " year",
            " today", " yesterday", " please", " and ", " or ", " if ", " so "
        ]

        for marker in markers {
            guard let range = normalized.range(of: marker) else { continue }
            var tail = String(normalized[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            for stopMarker in stopMarkers {
                if let stopRange = tail.range(of: stopMarker) {
                    tail = String(tail[..<stopRange.lowerBound])
                    break
                }
            }
            let cleaned = tail.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty == false {
                return cleaned.capitalized
            }
        }

        return nil
    }

    private func captureAmount(_ text: String, patterns: [String]) -> Double? {
        for pattern in patterns {
            if let match = captureFirst(text, pattern: pattern), let amount = Double(match) {
                return amount
            }
        }
        return nil
    }

    private func captureFirst(_ text: String, pattern: String) -> String? {
        captureGroups(text, pattern: pattern)?.first
    }

    private func captureGroups(_ text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let searchRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: searchRange) else {
            return nil
        }

        var captures: [String] = []
        for index in 1..<match.numberOfRanges {
            guard let range = Range(match.range(at: index), in: text) else {
                captures.append("")
                continue
            }
            captures.append(String(text[range]))
        }
        return captures
    }

    private func monthRange(containing date: Date) -> HomeQueryDateRange {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? date
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func normalizedPrompt(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s%]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct HomeAssistantWhatIfAnswerBuilder {
    private let calendar: Calendar
    private let nowProvider: () -> Date

    init(
        calendar: Calendar = .current,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.calendar = calendar
        self.nowProvider = nowProvider
    }

    func makeAnswer(
        queryID: UUID,
        userPrompt: String,
        request: HomeAssistantWhatIfRequest,
        categories: [Category],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        incomes: [Income]
    ) -> HomeAssistantWhatIfAnswerBuildResult {
        let range = request.dateRange ?? monthRange(containing: nowProvider())
        let currentSpendTotal = totalSpend(in: range, plannedExpenses: plannedExpenses, variableExpenses: variableExpenses)
        let currentActualIncome = totalIncome(in: range, incomes: incomes, isPlanned: false)
        let currentPlannedIncome = totalIncome(in: range, incomes: incomes, isPlanned: true)

        let currentSpendByCategoryID = spendByCategoryID(
            in: range,
            categories: categories,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses
        )

        let currentMerchantSpend = merchantSpendTotal(
            targetName: request.targetName,
            in: range,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses
        )

        let projection = projectedScenario(
            request: request,
            range: range,
            currentSpendTotal: currentSpendTotal,
            currentSpendByCategoryID: currentSpendByCategoryID,
            currentMerchantSpend: currentMerchantSpend,
            currentActualIncome: currentActualIncome,
            currentPlannedIncome: currentPlannedIncome
        )

        var rows: [HomeAnswerRow] = [
            HomeAnswerRow(title: "Current total spend", value: CurrencyFormatter.string(from: currentSpendTotal))
        ]

        if let targetName = request.targetName,
           case .merchant = request.targetKind {
            rows.append(
                HomeAnswerRow(
                    title: "Current \(targetName)",
                    value: CurrencyFormatter.string(from: currentMerchantSpend)
                )
            )
        }

        if case let .category(categoryID) = request.targetKind,
           let category = categories.first(where: { $0.id == categoryID }) {
            rows.append(
                HomeAnswerRow(
                    title: "Current \(category.name)",
                    value: CurrencyFormatter.string(from: currentSpendByCategoryID[categoryID, default: 0])
                )
            )
        }

        rows.append(HomeAnswerRow(title: "Hypothetical change", value: projection.changeLabel))

        if let targetRow = projection.projectedTargetLabel,
           let targetValue = projection.projectedTargetValue {
            rows.append(HomeAnswerRow(title: targetRow, value: targetValue))
        }

        rows.append(HomeAnswerRow(title: "Projected total spend", value: projection.projectedSpendLabel))
        rows.append(HomeAnswerRow(title: "Projected outcome", value: projection.actualOutcomeLabel))

        if currentPlannedIncome > 0 || projection.plannedOutcomeLabel != nil {
            rows.append(
                HomeAnswerRow(
                    title: "Projected outcome (planned income)",
                    value: projection.plannedOutcomeLabel ?? CurrencyFormatter.string(from: currentPlannedIncome - currentSpendTotal)
                )
            )
        }

        let subtitle = projection.subtitle
        let rawAnswer = HomeAnswer(
            queryID: queryID,
            kind: .list,
            userPrompt: userPrompt,
            title: request.isAffordabilityPrompt ? "What If Affordability" : "What If Preview",
            subtitle: subtitle,
            primaryValue: projection.actualOutcomeLabel,
            rows: rows
        )

        let spendQuery = HomeQuery(intent: .spendThisMonth, dateRange: range)
        let incomeQuery = HomeQuery(intent: .incomeAverageActual, dateRange: range)

        let context = HomeAssistantWhatIfContext(
            request: request,
            resolvedDateRange: range,
            directPlannerDraft: projection.directPlannerDraft,
            exactAdditionalSpendForPlanner: projection.exactAdditionalSpendForPlanner,
            requiresPlannerCategoryName: projection.requiresPlannerCategoryName,
            requiresExactCadenceSelection: projection.requiresExactCadenceSelection
        )

        return HomeAssistantWhatIfAnswerBuildResult(
            rawAnswer: rawAnswer,
            primaryQuery: spendQuery,
            footerQueries: [spendQuery, incomeQuery],
            context: context
        )
    }

    private func projectedScenario(
        request: HomeAssistantWhatIfRequest,
        range: HomeQueryDateRange,
        currentSpendTotal: Double,
        currentSpendByCategoryID: [UUID: Double],
        currentMerchantSpend: Double,
        currentActualIncome: Double,
        currentPlannedIncome: Double
    ) -> (
        changeLabel: String,
        projectedTargetLabel: String?,
        projectedTargetValue: String?,
        projectedSpendLabel: String,
        actualOutcomeLabel: String,
        plannedOutcomeLabel: String?,
        subtitle: String,
        directPlannerDraft: HomeAssistantWhatIfPlannerDraft?,
        exactAdditionalSpendForPlanner: Double?,
        requiresPlannerCategoryName: Bool,
        requiresExactCadenceSelection: Bool
    ) {
        switch request.targetKind {
        case let .category(categoryID):
            let baseline = currentSpendByCategoryID[categoryID, default: 0]
            let categoryName = request.targetName ?? "Category"
            let resolved = resolveCategoryProjection(valueMode: request.valueMode, baseline: baseline, range: range)
            let projectedSpend = currentSpendTotal - baseline + resolved.projectedTotal.lowerBound
            let projectedSpendUpper = currentSpendTotal - baseline + resolved.projectedTotal.upperBound
            let projectedSpendLabel = currencyLabel(projectedSpend...projectedSpendUpper)
            let actualOutcomeLabel = currencyLabel((currentActualIncome - projectedSpendUpper)...(currentActualIncome - projectedSpend))
            let plannedOutcomeLabel = currencyLabel((currentPlannedIncome - projectedSpendUpper)...(currentPlannedIncome - projectedSpend))
            let directDraft = resolved.exactProjectedTotal.map {
                HomeAssistantWhatIfPlannerDraft(
                    categoryScenarioSpendByID: [categoryID: $0],
                    plannedIncomeOverride: nil,
                    actualIncomeOverride: nil,
                    sourcePrompt: request.targetName ?? categoryName,
                    summary: "Applied \(categoryName) What If from Marina."
                )
            }
            return (
                changeLabel: resolved.changeLabel,
                projectedTargetLabel: "Projected \(categoryName)",
                projectedTargetValue: currencyLabel(resolved.projectedTotal),
                projectedSpendLabel: projectedSpendLabel,
                actualOutcomeLabel: actualOutcomeLabel,
                plannedOutcomeLabel: plannedOutcomeLabel,
                subtitle: "This is a temporary What If preview. Say open this in What If planner if you want to keep working with it.",
                directPlannerDraft: directDraft,
                exactAdditionalSpendForPlanner: nil,
                requiresPlannerCategoryName: false,
                requiresExactCadenceSelection: resolved.exactProjectedTotal == nil
            )

        case .merchant:
            let merchantName = request.targetName ?? "merchant"
            let resolved = resolveMerchantProjection(valueMode: request.valueMode, currentMerchantSpend: currentMerchantSpend, range: range)
            let projectedSpend = currentSpendTotal + resolved.additionalSpend.lowerBound
            let projectedSpendUpper = currentSpendTotal + resolved.additionalSpend.upperBound
            let projectedSpendLabel = currencyLabel(projectedSpend...projectedSpendUpper)
            let actualOutcomeLabel = currencyLabel((currentActualIncome - projectedSpendUpper)...(currentActualIncome - projectedSpend))
            let plannedOutcomeLabel = currencyLabel((currentPlannedIncome - projectedSpendUpper)...(currentPlannedIncome - projectedSpend))
            let subtitle: String
            if resolved.requiresExactCadenceSelection {
                subtitle = "\(resolved.assumptionLine) If you want this in What If planner later, tell me whether to use the faster or slower cadence first."
            } else {
                subtitle = "\(resolved.assumptionLine) If you want this in What If planner later, I can map it to a category after this answer."
            }
            return (
                changeLabel: resolved.changeLabel,
                projectedTargetLabel: "Projected \(merchantName)",
                projectedTargetValue: currencyLabel(resolved.projectedMerchantSpend),
                projectedSpendLabel: projectedSpendLabel,
                actualOutcomeLabel: actualOutcomeLabel,
                plannedOutcomeLabel: plannedOutcomeLabel,
                subtitle: subtitle,
                directPlannerDraft: nil,
                exactAdditionalSpendForPlanner: resolved.exactAdditionalSpend,
                requiresPlannerCategoryName: resolved.exactAdditionalSpend != nil,
                requiresExactCadenceSelection: resolved.requiresExactCadenceSelection
            )

        case .actualIncome, .plannedIncome:
            let setAmount: Double
            switch request.valueMode {
            case let .setAmount(amount):
                setAmount = amount
            default:
                setAmount = request.targetKind == .actualIncome ? currentActualIncome : currentPlannedIncome
            }
            let outcome = setAmount - currentSpendTotal
            let plannedOutcome = request.targetKind == .plannedIncome ? outcome : (currentPlannedIncome - currentSpendTotal)
            let actualOutcome = request.targetKind == .actualIncome ? outcome : (currentActualIncome - currentSpendTotal)
            let draft = HomeAssistantWhatIfPlannerDraft(
                categoryScenarioSpendByID: [:],
                plannedIncomeOverride: request.targetKind == .plannedIncome ? setAmount : nil,
                actualIncomeOverride: request.targetKind == .actualIncome ? setAmount : nil,
                sourcePrompt: request.targetName ?? "Income What If",
                summary: "Applied income What If from Marina."
            )
            let incomeLabel = request.targetKind == .plannedIncome ? "Projected planned income" : "Projected actual income"
            return (
                changeLabel: CurrencyFormatter.string(from: setAmount),
                projectedTargetLabel: incomeLabel,
                projectedTargetValue: CurrencyFormatter.string(from: setAmount),
                projectedSpendLabel: CurrencyFormatter.string(from: currentSpendTotal),
                actualOutcomeLabel: CurrencyFormatter.string(from: actualOutcome),
                plannedOutcomeLabel: CurrencyFormatter.string(from: plannedOutcome),
                subtitle: "This is a temporary What If preview. Say open this in What If planner if you want to keep working with it.",
                directPlannerDraft: draft,
                exactAdditionalSpendForPlanner: nil,
                requiresPlannerCategoryName: false,
                requiresExactCadenceSelection: false
            )
        }
    }

    private func resolveCategoryProjection(
        valueMode: HomeAssistantWhatIfValueMode,
        baseline: Double,
        range: HomeQueryDateRange
    ) -> (
        changeLabel: String,
        projectedTotal: ClosedRange<Double>,
        exactProjectedTotal: Double?
    ) {
        switch valueMode {
        case let .additionalAmount(amount):
            let projected = baseline + amount
            return (
                changeLabel: "+\(CurrencyFormatter.string(from: amount))",
                projectedTotal: projected...projected,
                exactProjectedTotal: projected
            )
        case let .setAmount(amount):
            return (
                changeLabel: CurrencyFormatter.string(from: amount),
                projectedTotal: amount...amount,
                exactProjectedTotal: amount
            )
        case let .adjustAmount(delta):
            let projected = max(0, baseline + delta)
            let prefix = delta >= 0 ? "+" : ""
            return (
                changeLabel: "\(prefix)\(CurrencyFormatter.string(from: delta))",
                projectedTotal: projected...projected,
                exactProjectedTotal: projected
            )
        case let .adjustPercent(percent):
            let projected = max(0, baseline * (1 + (percent / 100)))
            let prefix = percent >= 0 ? "+" : ""
            return (
                changeLabel: "\(prefix)\(CurrencyFormatter.string(from: abs(baseline * (percent / 100)))) (\(prefix)\(percent.formatted(.number.precision(.fractionLength(0))))%)",
                projectedTotal: projected...projected,
                exactProjectedTotal: projected
            )
        case let .recurringAmount(amount, minimumDayInterval, maximumDayInterval):
            let extra = recurringSpendRange(
                amountPerOccurrence: amount,
                range: range,
                minimumDayInterval: minimumDayInterval,
                maximumDayInterval: maximumDayInterval
            )
            return (
                changeLabel: currencyLabel(extra),
                projectedTotal: (baseline + extra.lowerBound)...(baseline + extra.upperBound),
                exactProjectedTotal: minimumDayInterval == maximumDayInterval ? baseline + extra.lowerBound : nil
            )
        }
    }

    private func resolveMerchantProjection(
        valueMode: HomeAssistantWhatIfValueMode,
        currentMerchantSpend: Double,
        range: HomeQueryDateRange
    ) -> (
        changeLabel: String,
        additionalSpend: ClosedRange<Double>,
        projectedMerchantSpend: ClosedRange<Double>,
        exactAdditionalSpend: Double?,
        assumptionLine: String,
        requiresExactCadenceSelection: Bool
    ) {
        switch valueMode {
        case let .additionalAmount(amount):
            return (
                changeLabel: "+\(CurrencyFormatter.string(from: amount))",
                additionalSpend: amount...amount,
                projectedMerchantSpend: (currentMerchantSpend + amount)...(currentMerchantSpend + amount),
                exactAdditionalSpend: amount,
                assumptionLine: "I treated that as one extra spend in this range.",
                requiresExactCadenceSelection: false
            )
        case let .recurringAmount(amount, minimumDayInterval, maximumDayInterval):
            let extraRange = recurringSpendRange(
                amountPerOccurrence: amount,
                range: range,
                minimumDayInterval: minimumDayInterval,
                maximumDayInterval: maximumDayInterval
            )
            let assumptionLine: String
            if minimumDayInterval == maximumDayInterval {
                assumptionLine = "I assumed one purchase starts now and repeats every \(minimumDayInterval) days through the end of this range."
            } else {
                assumptionLine = "I assumed one purchase starts now and repeats every \(minimumDayInterval)-\(maximumDayInterval) days through the end of this range."
            }
            return (
                changeLabel: currencyLabel(extraRange),
                additionalSpend: extraRange,
                projectedMerchantSpend: (currentMerchantSpend + extraRange.lowerBound)...(currentMerchantSpend + extraRange.upperBound),
                exactAdditionalSpend: minimumDayInterval == maximumDayInterval ? extraRange.lowerBound : nil,
                assumptionLine: assumptionLine,
                requiresExactCadenceSelection: minimumDayInterval != maximumDayInterval
            )
        case let .setAmount(amount):
            return (
                changeLabel: CurrencyFormatter.string(from: amount),
                additionalSpend: max(0, amount - currentMerchantSpend)...max(0, amount - currentMerchantSpend),
                projectedMerchantSpend: amount...amount,
                exactAdditionalSpend: max(0, amount - currentMerchantSpend),
                assumptionLine: "I treated that as the merchant total for this range.",
                requiresExactCadenceSelection: false
            )
        case let .adjustAmount(delta):
            return (
                changeLabel: "\(delta >= 0 ? "+" : "")\(CurrencyFormatter.string(from: delta))",
                additionalSpend: max(0, delta)...max(0, delta),
                projectedMerchantSpend: max(0, currentMerchantSpend + delta)...max(0, currentMerchantSpend + delta),
                exactAdditionalSpend: max(0, delta),
                assumptionLine: "I treated that as a merchant adjustment in this range.",
                requiresExactCadenceSelection: false
            )
        case .adjustPercent:
            return (
                changeLabel: CurrencyFormatter.string(from: currentMerchantSpend),
                additionalSpend: 0...0,
                projectedMerchantSpend: currentMerchantSpend...currentMerchantSpend,
                exactAdditionalSpend: nil,
                assumptionLine: "I need a category or merchant total to map percent changes cleanly.",
                requiresExactCadenceSelection: true
            )
        }
    }

    private func recurringSpendRange(
        amountPerOccurrence: Double,
        range: HomeQueryDateRange,
        minimumDayInterval: Int,
        maximumDayInterval: Int
    ) -> ClosedRange<Double> {
        let start = max(calendar.startOfDay(for: nowProvider()), calendar.startOfDay(for: range.startDate))
        let end = range.endDate
        guard start <= end else { return 0...0 }

        let fasterCount = occurrenceCount(from: start, through: end, every: max(1, minimumDayInterval))
        let slowerCount = occurrenceCount(from: start, through: end, every: max(1, maximumDayInterval))
        let low = Double(min(fasterCount, slowerCount)) * amountPerOccurrence
        let high = Double(max(fasterCount, slowerCount)) * amountPerOccurrence
        return CurrencyFormatter.roundedToCurrency(low)...CurrencyFormatter.roundedToCurrency(high)
    }

    private func occurrenceCount(from start: Date, through end: Date, every intervalDays: Int) -> Int {
        guard start <= end else { return 0 }
        let daySpan = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
        return max(1, (daySpan / max(1, intervalDays)) + 1)
    }

    private func spendByCategoryID(
        in range: HomeQueryDateRange,
        categories: [Category],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense]
    ) -> [UUID: Double] {
        var totals: [UUID: Double] = [:]
        totals.reserveCapacity(categories.count)

        for expense in plannedExpenses where expense.expenseDate >= range.startDate && expense.expenseDate <= range.endDate {
            guard let category = expense.category else { continue }
            totals[category.id, default: 0] += max(0, CurrencyFormatter.roundedToCurrency(expense.effectiveAmount()))
        }

        for expense in variableExpenses where expense.transactionDate >= range.startDate && expense.transactionDate <= range.endDate {
            guard let category = expense.category else { continue }
            totals[category.id, default: 0] += expense.ledgerSignedAmount()
        }

        return totals.mapValues { CurrencyFormatter.roundedToCurrency(max(0, $0)) }
    }

    private func totalSpend(
        in range: HomeQueryDateRange,
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense]
    ) -> Double {
        let planned = plannedExpenses
            .filter { $0.expenseDate >= range.startDate && $0.expenseDate <= range.endDate }
            .reduce(0.0) { $0 + max(0, CurrencyFormatter.roundedToCurrency($1.effectiveAmount())) }
        let variable = variableExpenses
            .filter { $0.transactionDate >= range.startDate && $0.transactionDate <= range.endDate }
            .reduce(0.0) { $0 + $1.ledgerSignedAmount() }
        return CurrencyFormatter.roundedToCurrency(max(0, planned + variable))
    }

    private func merchantSpendTotal(
        targetName: String?,
        in range: HomeQueryDateRange,
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense]
    ) -> Double {
        guard let targetName else { return 0 }
        let merchantKey = MerchantNormalizer.normalizeKey(targetName)
        let planned = plannedExpenses
            .filter { $0.expenseDate >= range.startDate && $0.expenseDate <= range.endDate }
            .filter { MerchantNormalizer.normalizeKey($0.title) == merchantKey }
            .reduce(0.0) { $0 + max(0, CurrencyFormatter.roundedToCurrency($1.effectiveAmount())) }
        let variable = variableExpenses
            .filter { $0.transactionDate >= range.startDate && $0.transactionDate <= range.endDate }
            .filter { MerchantNormalizer.normalizeKey($0.descriptionText) == merchantKey }
            .reduce(0.0) { $0 + $1.ledgerSignedAmount() }
        return CurrencyFormatter.roundedToCurrency(max(0, planned + variable))
    }

    private func totalIncome(
        in range: HomeQueryDateRange,
        incomes: [Income],
        isPlanned: Bool
    ) -> Double {
        incomes
            .filter { $0.isPlanned == isPlanned }
            .filter { $0.date >= range.startDate && $0.date <= range.endDate }
            .reduce(0.0) { $0 + max(0, CurrencyFormatter.roundedToCurrency($1.amount)) }
    }

    private func currencyLabel(_ range: ClosedRange<Double>) -> String {
        if abs(range.lowerBound - range.upperBound) < 0.000_1 {
            return CurrencyFormatter.string(from: range.lowerBound)
        }
        return "\(CurrencyFormatter.string(from: range.lowerBound)) - \(CurrencyFormatter.string(from: range.upperBound))"
    }

    private func monthRange(containing date: Date) -> HomeQueryDateRange {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? date
        return HomeQueryDateRange(startDate: start, endDate: end)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
