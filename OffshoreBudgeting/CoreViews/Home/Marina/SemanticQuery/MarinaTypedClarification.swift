import Foundation

enum MarinaClarificationKind: String, Codable, Equatable {
    case missingTarget
    case ambiguousTarget
    case missingDateRange
    case ambiguousDateRange
    case unsupportedShape
    case lowConfidence
}

enum MarinaClarificationPatchSlot: String, Codable, Equatable, Sendable {
    case target
    case date
    case comparison
    case amount
    case simulation
}

struct MarinaClarificationResumeIntent: Codable, Equatable {
    let candidate: MarinaQueryPlanCandidate?
    let semanticQuery: MarinaSemanticQuery?

    init(
        candidate: MarinaQueryPlanCandidate? = nil,
        semanticQuery: MarinaSemanticQuery? = nil
    ) {
        self.candidate = candidate
        self.semanticQuery = semanticQuery
    }
}

struct MarinaClarificationChoice: Codable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let subtitle: String?
    let entityRole: MarinaEntityMentionRole?
    let entityTypeHint: MarinaCandidateEntityTypeHint?
    let patchSlot: MarinaClarificationPatchSlot?
    let rawValue: String?
    let sourceID: UUID?
    let mentionID: UUID?
    let resumeIntent: MarinaClarificationResumeIntent?

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String? = nil,
        entityRole: MarinaEntityMentionRole? = nil,
        entityTypeHint: MarinaCandidateEntityTypeHint? = nil,
        patchSlot: MarinaClarificationPatchSlot? = nil,
        rawValue: String? = nil,
        sourceID: UUID? = nil,
        mentionID: UUID? = nil,
        resumeIntent: MarinaClarificationResumeIntent? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.entityRole = entityRole
        self.entityTypeHint = entityTypeHint
        self.patchSlot = patchSlot
        self.rawValue = rawValue
        self.sourceID = sourceID
        self.mentionID = mentionID
        self.resumeIntent = resumeIntent
    }
}

struct MarinaTypedClarification: Codable, Equatable, Identifiable {
    let id: UUID
    let kind: MarinaClarificationKind
    let message: String
    let candidate: MarinaQueryPlanCandidate?
    let pendingSemanticQuery: MarinaSemanticQuery?
    let patchSlot: MarinaClarificationPatchSlot?
    let choices: [MarinaClarificationChoice]
    let canRunBestEffort: Bool

    init(
        id: UUID = UUID(),
        kind: MarinaClarificationKind,
        message: String,
        candidate: MarinaQueryPlanCandidate? = nil,
        pendingSemanticQuery: MarinaSemanticQuery? = nil,
        patchSlot: MarinaClarificationPatchSlot? = nil,
        choices: [MarinaClarificationChoice] = [],
        canRunBestEffort: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.message = message
        self.candidate = candidate
        self.pendingSemanticQuery = pendingSemanticQuery
        self.patchSlot = patchSlot
        self.choices = choices
        self.canRunBestEffort = canRunBestEffort
    }
}

enum MarinaClarificationChoiceResolution: Equatable {
    case resolved(MarinaClarificationChoice)
    case ambiguous([MarinaClarificationChoice])
    case unresolved
}

struct MarinaClarificationChoiceResolver {
    func resolve(
        reply: String,
        clarification: MarinaTypedClarification
    ) -> MarinaClarificationChoiceResolution {
        let key = Self.normalized(reply)
        guard key.isEmpty == false else { return .unresolved }

        let choices = clarification.actionableChoices
        guard choices.isEmpty == false else { return .unresolved }

        let matches = choices.filter { choice in
            lookupKeys(for: choice).contains(key)
        }

        if matches.count == 1, let match = matches.first {
            return .resolved(match)
        }
        if matches.count > 1 {
            return .ambiguous(matches)
        }
        return .unresolved
    }

    static func displayTitle(for choice: MarinaClarificationChoice) -> String {
        choice.title
    }

    nonisolated static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func lookupKeys(for choice: MarinaClarificationChoice) -> Set<String> {
        var keys: Set<String> = [
            Self.displayTitle(for: choice),
            choice.title
        ]
        if let rawValue = choice.rawValue {
            keys.insert(rawValue)
        }
        if let type = choice.entityTypeHint {
            keys.insert(type.rawValue)
            keys.insert("\(choice.title) \(type.rawValue)")
            keys.insert("\(choice.title) (\(type.rawValue))")
            for alias in Self.typeAliases(for: type) {
                keys.insert(alias)
                keys.insert("\(choice.title) \(alias)")
                keys.insert("\(choice.title) (\(alias))")
            }
        }
        return Set(keys.map(Self.normalized).filter { $0.isEmpty == false })
    }

    private static func typeAliases(for type: MarinaCandidateEntityTypeHint) -> [String] {
        switch type {
        case .category:
            return ["category"]
        case .card:
            return ["card"]
        case .merchant:
            return ["merchant", "expense description", "description"]
        case .expense, .transaction:
            return ["expense", "transaction", "purchase"]
        case .budget:
            return ["budget"]
        case .preset:
            return ["preset"]
        case .incomeSource:
            return ["income source"]
        case .allocationAccount:
            return ["reconciliation", "reconciliation account", "shared balance"]
        case .savingsAccount:
            return ["savings", "savings account"]
        case .workspace:
            return ["workspace"]
        }
    }
}

extension MarinaClarificationChoice {
    func isEcho(of prompt: String) -> Bool {
        let prompt = Self.normalized(prompt)
        guard prompt.isEmpty == false else { return false }
        let candidates = [title, rawValue, subtitle].compactMap { $0 }.map(Self.normalized)
        return candidates.contains { value in
            value == prompt || value.contains(prompt) || prompt.contains(value)
        }
    }

    func isActionableChoice(for prompt: String) -> Bool {
        if isFullPromptEchoWithoutStableIdentity(of: prompt) {
            return false
        }
        if entityTypeHint != nil || sourceID != nil || patchSlot != nil || mentionID != nil || resumeIntent != nil {
            return true
        }
        return isEcho(of: prompt) == false
    }

    private func isFullPromptEchoWithoutStableIdentity(of prompt: String) -> Bool {
        let prompt = Self.normalized(prompt)
        guard prompt.isEmpty == false,
              sourceID == nil,
              mentionID == nil else {
            return false
        }
        return [title, rawValue]
            .compactMap { $0 }
            .map(Self.normalized)
            .contains(prompt)
    }

    nonisolated private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension MarinaTypedClarification {
    func isActionable(for originalPrompt: String) -> Bool {
        let choices = actionableChoices(for: originalPrompt)
        switch kind {
        case .missingTarget:
            if choices.isEmpty == false {
                return true
            }
            return self.choices.isEmpty && (patchSlot != nil || pendingSemanticQuery != nil)
        case .ambiguousTarget, .ambiguousDateRange:
            return choices.count > 1
        case .missingDateRange:
            return patchSlot != nil || choices.isEmpty == false
        case .unsupportedShape, .lowConfidence:
            return false
        }
    }

    func actionableChoices(for originalPrompt: String) -> [MarinaClarificationChoice] {
        choices.filter { $0.isActionableChoice(for: originalPrompt) }
    }

    var actionableChoices: [MarinaClarificationChoice] {
        guard let prompt = candidate?.rawPrompt else { return choices }
        return actionableChoices(for: prompt)
    }
}

enum MarinaUnsupportedResponseKind: String, Codable, Equatable {
    case unsupportedOperation
    case unsupportedTargetType
    case unsupportedCombination
    case unsupportedSimulation
    case unsupportedDateShape
}

struct MarinaTypedUnsupportedResponse: Codable, Equatable, Identifiable {
    let id: UUID
    let kind: MarinaUnsupportedResponseKind
    let message: String
    let candidate: MarinaQueryPlanCandidate?

    init(
        id: UUID = UUID(),
        kind: MarinaUnsupportedResponseKind,
        message: String,
        candidate: MarinaQueryPlanCandidate? = nil
    ) {
        self.id = id
        self.kind = kind
        self.message = message
        self.candidate = candidate
    }
}

enum MarinaPlanValidationOutcome: Codable, Equatable {
    case executable(MarinaAggregationPlan)
    case clarification(MarinaTypedClarification)
    case unsupported(MarinaTypedUnsupportedResponse)
}

@MainActor
struct MarinaConversationalQueryPlanner {
    func clarification(
        candidate: MarinaQueryPlanCandidate,
        outcome: MarinaPlanValidationOutcome,
        context: MarinaTurnContext,
        explicitConstraints: MarinaExplicitPromptConstraints
    ) -> MarinaTypedClarification? {
        switch outcome {
        case .clarification, .executable:
            return nil
        case .unsupported(let unsupported):
            if let savingsClarification = savingsClarification(
                candidate: candidate,
                context: context,
                unsupported: unsupported
            ) {
                return savingsClarification
            }
            return bareShowClarification(
                candidate: candidate,
                context: context,
                explicitConstraints: explicitConstraints,
                unsupported: unsupported
            )
        }
    }

    func clarificationForDroppedConstraints(
        candidate: MarinaQueryPlanCandidate,
        context: MarinaTurnContext,
        explicitConstraints: MarinaExplicitPromptConstraints,
        unsupported: MarinaTypedUnsupportedResponse
    ) -> MarinaTypedClarification? {
        bareShowClarification(
            candidate: candidate,
            context: context,
            explicitConstraints: explicitConstraints,
            unsupported: unsupported
        )
    }

    private func bareShowClarification(
        candidate: MarinaQueryPlanCandidate,
        context: MarinaTurnContext,
        explicitConstraints: MarinaExplicitPromptConstraints,
        unsupported: MarinaTypedUnsupportedResponse
    ) -> MarinaTypedClarification? {
        let prompt = normalized(candidate.rawPrompt)
        guard isBareShowPrompt(prompt) || unsupported.kind == .unsupportedOperation || unsupported.kind == .unsupportedCombination else {
            return nil
        }

        let targetText = bareTargetText(in: prompt)
            ?? candidate.entityMentions.compactMap(\.rawText).first
            ?? explicitConstraints.categories.first
            ?? explicitConstraints.cards.first
        guard let targetText, targetText.isEmpty == false else { return nil }

        var choices: [MarinaClarificationChoice] = []
        let matchedCategories = matchedNames(
            context.routerContext.categoryNames,
            targetText: targetText,
            prompt: prompt
        )
        let matchedCards = matchedNames(
            context.routerContext.cardNames,
            targetText: targetText,
            prompt: prompt
        )
        let matchedBudgets = matchedNames(
            context.routerContext.budgetNames,
            targetText: targetText,
            prompt: prompt
        )
        let matchedPresets = matchedNames(
            context.routerContext.presetTitles,
            targetText: targetText,
            prompt: prompt
        )
        let matchedIncomeSources = matchedNames(
            context.routerContext.incomeSourceNames,
            targetText: targetText,
            prompt: prompt
        )

        for name in matchedCategories {
            choices.append(operationChoice(
                title: "\(name) spending",
                subtitle: "Total category spending",
                targetName: name,
                targetType: .category,
                operation: .sum,
                measure: .spend,
                responseShape: .scalarCurrency,
                prompt: candidate.rawPrompt
            ))
            choices.append(operationChoice(
                title: "\(name) expenses",
                subtitle: "List matching purchases",
                targetName: name,
                targetType: .category,
                operation: .listRows,
                measure: .transactionAmount,
                grouping: .transaction,
                ranking: MarinaRankingCandidate(direction: .newest, limit: 10),
                limit: 10,
                responseShape: .rankedList,
                prompt: candidate.rawPrompt
            ))
            choices.append(budgetLimitChoice(
                title: "\(name) budget limit",
                targetName: name,
                prompt: candidate.rawPrompt
            ))
        }

        for name in matchedCards {
            choices.append(operationChoice(
                title: "\(name) spending",
                subtitle: "Total card spending",
                targetName: name,
                targetType: .card,
                operation: .sum,
                measure: .spend,
                responseShape: .scalarCurrency,
                prompt: candidate.rawPrompt
            ))
            choices.append(operationChoice(
                title: "\(name) transactions",
                subtitle: "List card purchases",
                targetName: name,
                targetType: .card,
                operation: .listRows,
                measure: .transactionAmount,
                grouping: .transaction,
                ranking: MarinaRankingCandidate(direction: .newest, limit: 10),
                limit: 10,
                responseShape: .rankedList,
                prompt: candidate.rawPrompt
            ))
        }

        for name in matchedBudgets {
            choices.append(budgetChoice(
                title: "\(name) summary",
                targetName: name,
                requestedDetail: .general,
                prompt: candidate.rawPrompt
            ))
            choices.append(budgetChoice(
                title: "\(name) linked cards",
                targetName: name,
                requestedDetail: .linkedCards,
                prompt: candidate.rawPrompt
            ))
            choices.append(budgetChoice(
                title: "\(name) linked presets",
                targetName: name,
                requestedDetail: .linkedPresets,
                prompt: candidate.rawPrompt
            ))
        }

        for name in matchedPresets {
            choices.append(operationChoice(
                title: "\(name) preset",
                subtitle: "Show preset details",
                targetName: name,
                targetType: .preset,
                operation: .lookupDetails,
                measure: .presetAmount,
                responseShape: .summaryCard,
                prompt: candidate.rawPrompt
            ))
            choices.append(operationChoice(
                title: "\(name) planned expenses",
                subtitle: "List scheduled rows from this preset",
                targetName: name,
                targetType: .preset,
                operation: .listRows,
                measure: .presetAmount,
                grouping: .transaction,
                ranking: MarinaRankingCandidate(direction: .newest, limit: 10),
                limit: 10,
                responseShape: .rankedList,
                prompt: candidate.rawPrompt
            ))
        }

        for name in matchedIncomeSources {
            choices.append(operationChoice(
                title: "\(name) income",
                subtitle: "Total income from this source",
                targetName: name,
                targetType: .incomeSource,
                operation: .sum,
                measure: .income,
                responseShape: .scalarCurrency,
                prompt: candidate.rawPrompt
            ))
        }

        if shouldOfferMerchantChoice(
            targetText: targetText,
            prompt: candidate.rawPrompt,
            matchedCards: matchedCards,
            matchedCategories: matchedCategories
        ) {
            let merchantName = displayText(targetText)
            choices.append(operationChoice(
                title: "\(merchantName) merchant spending",
                subtitle: "Total spending at matching merchants",
                targetName: merchantName,
                targetType: .merchant,
                operation: .sum,
                measure: .spend,
                responseShape: .scalarCurrency,
                prompt: candidate.rawPrompt
            ))
            choices.append(operationChoice(
                title: "\(merchantName) purchases",
                subtitle: "List matching merchant purchases",
                targetName: merchantName,
                targetType: .merchant,
                operation: .listRows,
                measure: .transactionAmount,
                grouping: .transaction,
                ranking: MarinaRankingCandidate(direction: .newest, limit: 10),
                limit: 10,
                responseShape: .rankedList,
                prompt: candidate.rawPrompt
            ))
        }

        let uniqueChoices = deduped(choices)
        guard uniqueChoices.count > 1 else { return nil }
        return MarinaTypedClarification(
            kind: .ambiguousTarget,
            message: "What would you like Marina to show for \(displayText(targetText))?",
            candidate: candidate,
            choices: uniqueChoices
        )
    }

    private func savingsClarification(
        candidate: MarinaQueryPlanCandidate,
        context _: MarinaTurnContext,
        unsupported: MarinaTypedUnsupportedResponse
    ) -> MarinaTypedClarification? {
        let prompt = normalized(candidate.rawPrompt)
        guard prompt.contains("savings") || prompt.contains("saving") else { return nil }
        guard prompt.contains("activity") == false else { return nil }
        guard unsupported.kind == .unsupportedOperation || unsupported.kind == .unsupportedCombination else { return nil }

        let choices = [
            operationChoice(
                title: "Actual savings",
                subtitle: "Show savings account status",
                targetName: nil,
                targetType: .savingsAccount,
                operation: .lookupDetails,
                measure: .savings,
                responseShape: .summaryCard,
                prompt: candidate.rawPrompt
            ),
            operationChoice(
                title: "Projected savings",
                subtitle: "Forecast savings for the current period",
                targetName: nil,
                targetType: nil,
                operation: .forecast,
                measure: .savings,
                responseShape: .summaryCard,
                prompt: candidate.rawPrompt
            ),
            operationChoice(
                title: "Savings activity",
                subtitle: "List savings ledger movements",
                targetName: nil,
                targetType: .savingsAccount,
                operation: .listRows,
                measure: .savingsMovement,
                grouping: .savingsLedgerEntry,
                ranking: MarinaRankingCandidate(direction: .newest, limit: 10),
                limit: 10,
                responseShape: .rankedList,
                prompt: candidate.rawPrompt
            )
        ]

        return MarinaTypedClarification(
            kind: .ambiguousTarget,
            message: "Which savings view did you mean?",
            candidate: candidate,
            choices: choices
        )
    }

    private func operationChoice(
        title: String,
        subtitle: String?,
        targetName: String?,
        targetType: MarinaCandidateEntityTypeHint?,
        operation: MarinaCandidateOperation,
        measure: MarinaCandidateMeasure,
        grouping: MarinaGroupingDimensionCandidate? = nil,
        ranking: MarinaRankingCandidate? = nil,
        limit: Int? = nil,
        responseShape: MarinaResponseShapeHint,
        prompt: String
    ) -> MarinaClarificationChoice {
        let mention = targetName.map {
            MarinaUnresolvedEntityMention(
                role: .filter,
                rawText: $0,
                typeHint: targetType,
                allowedTypeHints: targetType.map { [$0] },
                confidence: .high
            )
        }
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: prompt,
            operation: operation,
            measure: measure,
            entityMentions: mention.map { [$0] } ?? [],
            grouping: grouping.map { MarinaGroupingCandidate(dimension: $0) },
            ranking: ranking,
            limit: limit,
            responseShapeHint: responseShape,
            confidence: .high
        )
        return MarinaClarificationChoice(
            title: title,
            subtitle: subtitle,
            entityRole: targetName == nil ? nil : .filter,
            entityTypeHint: targetType,
            rawValue: targetName,
            resumeIntent: MarinaClarificationResumeIntent(candidate: candidate)
        )
    }

    private func budgetLimitChoice(
        title: String,
        targetName: String,
        prompt: String
    ) -> MarinaClarificationChoice {
        let command = MarinaSemanticCommand(
            family: .analytics,
            action: .lookupDetails,
            datasets: [.budgets],
            measure: .remainingBudget,
            includeFilters: [
                MarinaSemanticCommandFilter(rawText: targetName, allowedTypes: [.category])
            ],
            requestedDetail: .categoryLimits
        )
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: prompt,
            operation: .lookupDetails,
            measure: .remainingBudget,
            entityMentions: [
                MarinaUnresolvedEntityMention(
                    role: .primaryTarget,
                    rawText: targetName,
                    typeHint: .category,
                    allowedTypeHints: [.category],
                    confidence: .high
                )
            ],
            responseShapeHint: .summaryCard,
            confidence: .high,
            semanticCommand: command
        )
        return MarinaClarificationChoice(
            title: title,
            subtitle: "Show budget category limit",
            entityRole: .primaryTarget,
            entityTypeHint: .category,
            rawValue: targetName,
            resumeIntent: MarinaClarificationResumeIntent(candidate: candidate)
        )
    }

    private func budgetChoice(
        title: String,
        targetName: String,
        requestedDetail: MarinaSemanticRequestedDetail,
        prompt: String
    ) -> MarinaClarificationChoice {
        let command = MarinaSemanticCommand(
            family: .analytics,
            action: .lookupDetails,
            datasets: [.budgets],
            measure: .remainingBudget,
            includeFilters: [
                MarinaSemanticCommandFilter(rawText: targetName, allowedTypes: [.budget])
            ],
            requestedDetail: requestedDetail
        )
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: prompt,
            operation: .lookupDetails,
            measure: .remainingBudget,
            entityMentions: [
                MarinaUnresolvedEntityMention(
                    role: .primaryTarget,
                    rawText: targetName,
                    typeHint: .budget,
                    allowedTypeHints: [.budget],
                    confidence: .high
                )
            ],
            responseShapeHint: requestedDetail == .general ? .summaryCard : .relationshipList,
            confidence: .high,
            semanticCommand: command
        )
        return MarinaClarificationChoice(
            title: title,
            subtitle: requestedDetail == .general ? "Show budget details" : "Show budget relationship",
            entityRole: .primaryTarget,
            entityTypeHint: .budget,
            rawValue: targetName,
            resumeIntent: MarinaClarificationResumeIntent(candidate: candidate)
        )
    }

    private func isBareShowPrompt(_ prompt: String) -> Bool {
        prompt.hasPrefix("show ")
            || prompt.hasPrefix("tell me about ")
            || prompt.hasPrefix("open ")
            || prompt.range(of: "^(show|open)\\s+[a-z0-9& ]+$", options: .regularExpression) != nil
    }

    private func bareTargetText(in prompt: String) -> String? {
        let prefixes = ["show ", "tell me about ", "open "]
        for prefix in prefixes where prompt.hasPrefix(prefix) {
            return String(prompt.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines).marinaNilIfBlank
        }
        return nil
    }

    private func matchedNames(_ names: [String], targetText: String, prompt: String) -> [String] {
        let target = normalized(targetText)
        guard target.isEmpty == false else { return [] }
        return names.filter { name in
            let normalizedName = normalized(name)
            return containsWholePhrase(normalizedName, in: prompt)
                || normalizedName == target
                || normalizedName.hasPrefix("\(target) ")
                || target.hasPrefix("\(normalizedName) ")
        }
    }

    private func shouldOfferMerchantChoice(
        targetText: String,
        prompt: String,
        matchedCards: [String],
        matchedCategories: [String]
    ) -> Bool {
        let target = normalized(targetText)
        guard target.count >= 3 else { return false }
        if matchedCards.isEmpty == false,
           containsWholePhrase("card", in: normalized(prompt)) {
            return false
        }
        return matchedCards.isEmpty || matchedCategories.isEmpty
    }

    private func deduped(_ choices: [MarinaClarificationChoice]) -> [MarinaClarificationChoice] {
        var seen: Set<String> = []
        return choices.filter { choice in
            let key = normalized([choice.title, choice.subtitle, choice.rawValue].compactMap { $0 }.joined(separator: "|"))
            guard seen.contains(key) == false else { return false }
            seen.insert(key)
            return true
        }
    }

    private func displayText(_ value: String) -> String {
        value
            .split(separator: " ")
            .map { part in
                part.prefix(1).uppercased() + String(part.dropFirst())
            }
            .joined(separator: " ")
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

private extension String {
    var marinaNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
