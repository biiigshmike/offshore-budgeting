import Foundation

struct MarinaSemanticCandidateResolution: Equatable, Sendable {
    let interpreted: MarinaInterpretedSemanticRequest
    let candidateSearches: [MarinaCandidateSearchTrace]
}

struct MarinaSemanticCandidateResolver {
    private enum TargetSlot {
        case primary
        case comparison
    }

    private let candidateSearchService: MarinaCandidateSearchService

    init(candidateSearchService: MarinaCandidateSearchService = MarinaCandidateSearchService()) {
        self.candidateSearchService = candidateSearchService
    }

    func resolve(
        interpreted: MarinaInterpretedSemanticRequest,
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaInterpretedSemanticRequest {
        resolveWithTrace(interpreted: interpreted, snapshot: snapshot).interpreted
    }

    func resolveWithTrace(
        interpreted: MarinaInterpretedSemanticRequest,
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaSemanticCandidateResolution {
        var request = interpreted.request
        var notes = interpreted.diagnosticNotes
        var candidateSearches: [MarinaCandidateSearchTrace] = []

        guard request.expectedAnswerShape != .clarification,
              request.expectedAnswerShape != .unsupported,
              hasResolvableTarget(request) else {
            return MarinaSemanticCandidateResolution(
                interpreted: interpreted,
                candidateSearches: candidateSearches
            )
        }

        if let target = primaryTargetText(from: request), target.isEmpty == false {
            let searchResult = candidateSearchResult(target: target, request: request, snapshot: snapshot)
            candidateSearches.append(MarinaCandidateSearchTrace(rawTargetText: target, slot: "primary", result: searchResult))

            if let terminal = terminalInterpretedRequest(
                searchResult: searchResult,
                target: target,
                slot: .primary,
                request: request,
                interpreted: interpreted,
                notes: notes
            ) {
                return MarinaSemanticCandidateResolution(
                    interpreted: terminal,
                    candidateSearches: candidateSearches
                )
            }

            if let explicitMatch = explicitDimensionMatch(in: searchResult, request: request) {
                request = semanticRequest(applying: explicitMatch, to: .primary, target: target, baseRequest: request)
                notes.append("Candidate resolver selected explicit \(explicitMatch.entity.rawValue) match \(explicitMatch.displayName) for \"\(target)\".")
            } else if let recommendedMatch = searchResult.recommendedMatch {
                request = semanticRequest(applying: recommendedMatch, to: .primary, target: target, baseRequest: request)
                notes.append("Candidate resolver selected \(recommendedMatch.displayName) for \"\(target)\".")
            } else if shouldResolveUntypedTarget(request) {
                notes.append("Candidate resolver found no valid meanings for \"\(target)\".")
                return MarinaSemanticCandidateResolution(
                    interpreted: interpretedWith(
                        request: unsupportedRequest(.unresolvedEntity),
                        interpreted: interpreted,
                        notes: notes,
                        choices: interpreted.clarificationChoices
                    ),
                    candidateSearches: candidateSearches
                )
            }
        }

        if let comparisonTargetName = request.comparisonTargetName,
           comparisonTargetName.isEmpty == false {
            let searchResult = candidateSearchResult(target: comparisonTargetName, request: request, snapshot: snapshot)
            candidateSearches.append(MarinaCandidateSearchTrace(rawTargetText: comparisonTargetName, slot: "comparison", result: searchResult))

            if let terminal = terminalInterpretedRequest(
                searchResult: searchResult,
                target: comparisonTargetName,
                slot: .comparison,
                request: request,
                interpreted: interpreted,
                notes: notes
            ) {
                return MarinaSemanticCandidateResolution(
                    interpreted: terminal,
                    candidateSearches: candidateSearches
                )
            }

            if let explicitMatch = explicitDimensionMatch(in: searchResult, request: request) {
                request = semanticRequest(applying: explicitMatch, to: .comparison, target: comparisonTargetName, baseRequest: request)
                notes.append("Candidate resolver selected explicit \(explicitMatch.entity.rawValue) match \(explicitMatch.displayName) for comparison target \"\(comparisonTargetName)\".")
            } else if let recommendedMatch = searchResult.recommendedMatch {
                request = semanticRequest(applying: recommendedMatch, to: .comparison, target: comparisonTargetName, baseRequest: request)
                notes.append("Candidate resolver selected \(recommendedMatch.displayName) for comparison target \"\(comparisonTargetName)\".")
            }
        }

        return MarinaSemanticCandidateResolution(
            interpreted: interpretedWith(
                request: request,
                interpreted: interpreted,
                notes: notes,
                choices: interpreted.clarificationChoices
            ),
            candidateSearches: candidateSearches
        )
    }

    func resolveExplicitPromptTargetsWithTrace(
        interpreted: MarinaInterpretedSemanticRequest,
        snapshot: MarinaWorkspaceSnapshot,
        explicitPromptTargets: [String]
    ) -> MarinaSemanticCandidateResolution {
        var notes = interpreted.diagnosticNotes
        var candidateSearches: [MarinaCandidateSearchTrace] = []

        guard interpreted.request.expectedAnswerShape != .clarification,
              interpreted.request.expectedAnswerShape != .unsupported,
              explicitPromptTargets.isEmpty == false else {
            return MarinaSemanticCandidateResolution(
                interpreted: interpreted,
                candidateSearches: candidateSearches
            )
        }

        if explicitPromptTargets.count > 1 {
            let choices = explicitPromptTargets.flatMap { target -> [MarinaClarificationChoice] in
                let searchResult = candidateSearchResult(target: target, request: interpreted.request, snapshot: snapshot)
                candidateSearches.append(MarinaCandidateSearchTrace(rawTargetText: target, slot: "explicitPromptTarget", result: searchResult))
                return candidateChoices(
                    from: searchResult.matches.filter(\.isStrongEnoughForAutomaticResolution),
                    target: target,
                    slot: .primary,
                    baseRequest: interpreted.request
                )
            }
            let dedupedChoices = deduped(choices)
            guard dedupedChoices.count > 1 else {
                return MarinaSemanticCandidateResolution(
                    interpreted: interpreted,
                    candidateSearches: candidateSearches
                )
            }

            let question = MarinaL10n.string("marina.clarification.explicitPromptTargetFallback", defaultValue: "Which target should Marina use?", comment: "Clarification question when multiple prompt targets could be recovered.")
            var request = clarificationRequest(
                question: question,
                target: explicitPromptTargets.joined(separator: ", "),
                dateRangeToken: interpreted.request.dateRangeToken
            )
            request.targetName = nil
            request.textQuery = nil
            notes.append("Candidate resolver found multiple explicit prompt targets: \(explicitPromptTargets.joined(separator: ", ")).")
            return MarinaSemanticCandidateResolution(
                interpreted: interpretedWith(
                    request: request,
                    interpreted: interpreted,
                    notes: notes,
                    choices: MarinaClarificationChoices(question: question, choices: dedupedChoices)
                ),
                candidateSearches: candidateSearches
            )
        }

        let target = explicitPromptTargets[0]
        let searchResult = candidateSearchResult(target: target, request: interpreted.request, snapshot: snapshot)
        candidateSearches.append(MarinaCandidateSearchTrace(rawTargetText: target, slot: "explicitPromptTarget", result: searchResult))

        if let terminal = terminalInterpretedRequest(
            searchResult: searchResult,
            target: target,
            slot: .primary,
            request: interpreted.request,
            interpreted: interpreted,
            notes: notes
        ) {
            return MarinaSemanticCandidateResolution(
                interpreted: terminal,
                candidateSearches: candidateSearches
            )
        }

        let match = explicitDimensionMatch(in: searchResult, request: interpreted.request)
            ?? searchResult.recommendedMatch
        guard let match else {
            return MarinaSemanticCandidateResolution(
                interpreted: interpreted,
                candidateSearches: candidateSearches
            )
        }

        let request = fallbackSemanticRequest(applying: match, target: target, baseRequest: interpreted.request)
        notes.append("Candidate resolver recovered explicit prompt target \(match.displayName) from \"\(target)\".")
        return MarinaSemanticCandidateResolution(
            interpreted: interpretedWith(
                request: request,
                interpreted: interpreted,
                notes: notes,
                choices: interpreted.clarificationChoices
            ),
            candidateSearches: candidateSearches
        )
    }

    private func interpretedWith(
        request: MarinaSemanticRequest,
        interpreted: MarinaInterpretedSemanticRequest,
        notes: [String],
        choices: MarinaClarificationChoices?
    ) -> MarinaInterpretedSemanticRequest {
        MarinaInterpretedSemanticRequest(
            request: request,
            confidence: interpreted.confidence,
            source: interpreted.source,
            diagnosticNotes: notes,
            clarificationChoices: choices
        )
    }

    private func explicitDimensionMatch(
        in searchResult: MarinaCandidateSearchResult,
        request: MarinaSemanticRequest
    ) -> MarinaCandidateMatch? {
        guard let entity = explicitlyTargetedEntity(in: request) else {
            return nil
        }

        let matches = searchResult.matches.filter {
            $0.entity == entity && $0.isStrongEnoughForAutomaticResolution
        }
        guard matches.count == 1 else {
            return nil
        }
        return matches[0]
    }

    private func explicitlyTargetedEntity(in request: MarinaSemanticRequest) -> MarinaSemanticEntity? {
        if request.dimensions.contains(.card) { return .card }
        if request.dimensions.contains(.category) { return .category }
        if request.dimensions.contains(.incomeSource) { return .income }
        if request.dimensions.contains(.preset) { return .preset }
        if request.dimensions.contains(.savingsAccount) { return .savingsAccount }
        if request.dimensions.contains(.reconciliationAccount) { return .reconciliationAccount }
        if request.dimensions.contains(.budget) { return .budget }
        return nil
    }

    private func shouldResolveUntypedTarget(_ request: MarinaSemanticRequest) -> Bool {
        if request.dimensions.contains(.merchantText) { return false }
        if request.dimensions.contains(.card) { return false }
        if request.dimensions.contains(.category) { return false }
        if request.dimensions.contains(.incomeSource) { return false }
        if request.dimensions.contains(.preset) { return false }
        if request.dimensions.contains(.savingsAccount) { return false }
        if request.dimensions.contains(.reconciliationAccount) { return false }
        if request.dimensions.contains(.budget) { return false }
        if request.dimensions.contains(.workspace) { return false }

        switch request.entity {
        case .variableExpense, .plannedExpense:
            return true
        default:
            return false
        }
    }

    private func terminalInterpretedRequest(
        searchResult: MarinaCandidateSearchResult,
        target: String,
        slot: TargetSlot,
        request: MarinaSemanticRequest,
        interpreted: MarinaInterpretedSemanticRequest,
        notes: [String]
    ) -> MarinaInterpretedSemanticRequest? {
        let usefulMatches = searchResult.matches.filter(\.isStrongEnoughForAutomaticResolution)
        guard usefulMatches.count > 1, searchResult.ambiguityStatus == .ambiguous else {
            return nil
        }

        let choices = candidateChoices(from: usefulMatches, target: target, slot: slot, baseRequest: request)
        guard choices.count > 1 else {
            return nil
        }

        let question = MarinaL10n.format("marina.clarification.targetMeaningFormat", defaultValue: "What should Marina use for \"%@\"?", comment: "Clarification question for resolving an ambiguous target.", target)
        var request = clarificationRequest(
            question: question,
            target: target,
            dateRangeToken: request.dateRangeToken
        )
        request.comparisonTargetName = slot == .comparison ? target : nil
        var notes = notes
        notes.append("Candidate resolver found \(choices.count) possible meanings for \"\(target)\".")
        return interpretedWith(
            request: request,
            interpreted: interpreted,
            notes: notes,
            choices: MarinaClarificationChoices(question: question, choices: choices)
        )
    }

    private func candidateSearchResult(
        target: String,
        request: MarinaSemanticRequest,
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaCandidateSearchResult {
        candidateSearchService.search(
            MarinaCandidateSearchRequest(
                rawTargetText: target,
                semanticRequest: request,
                snapshot: snapshot
            )
        )
    }

    private func candidateChoices(
        from matches: [MarinaCandidateMatch],
        target: String,
        slot: TargetSlot,
        baseRequest: MarinaSemanticRequest
    ) -> [MarinaClarificationChoice] {
        let expenseMatches = matches.filter(isExpenseTextMatch)
        let hasMultipleExpenseTextMatches = expenseMatches.count > 1
        var choices = matches.map {
            clarificationChoice(
                for: $0,
                target: target,
                slot: slot,
                baseRequest: baseRequest,
                includeGenericExpenseAliases: hasMultipleExpenseTextMatches == false
            )
        }

        if slot == .primary, hasMultipleExpenseTextMatches {
            choices.append(aggregateExpenseTextChoice(for: target, baseRequest: baseRequest))
        }

        return deduped(choices)
    }

    private func semanticRequest(
        applying match: MarinaCandidateMatch,
        to slot: TargetSlot,
        target: String,
        baseRequest request: MarinaSemanticRequest
    ) -> MarinaSemanticRequest {
        if slot == .comparison {
            var repaired = request
            repaired.comparisonTargetName = match.displayName
            return repaired
        }

        if let repaired = requestPreservingExplicitShape(applying: match, to: request) {
            return repaired
        }

        switch match.entity {
        case .category:
            return categoryRequest(categoryName: match.displayName, baseRequest: request)
        case .income:
            return incomeSourceRequest(source: match.displayName, baseRequest: request)
        case .variableExpense, .plannedExpense:
            return expenseTextRequest(textQuery: match.displayName, displayName: match.displayName, baseRequest: request)
        case .card:
            return cardRequest(cardName: match.displayName, baseRequest: request)
        case .budget:
            return budgetRequest(budgetName: match.displayName, baseRequest: request)
        case .preset:
            return presetRequest(presetName: match.displayName, baseRequest: request)
        case .savingsAccount:
            return savingsAccountRequest(accountName: match.displayName, baseRequest: request)
        case .reconciliationAccount:
            return reconciliationAccountRequest(accountName: match.displayName, baseRequest: request)
        case .workspace:
            return request
        }
    }

    private func fallbackSemanticRequest(
        applying match: MarinaCandidateMatch,
        target: String,
        baseRequest request: MarinaSemanticRequest
    ) -> MarinaSemanticRequest {
        switch match.entity {
        case .category:
            return categoryRequest(categoryName: match.displayName, baseRequest: request)
        case .income:
            return incomeSourceRequest(source: match.displayName, baseRequest: request)
        case .variableExpense, .plannedExpense:
            return expenseTextRequest(textQuery: match.displayName, displayName: match.displayName, baseRequest: request)
        case .card:
            return cardRequest(cardName: match.displayName, baseRequest: request)
        case .budget:
            return budgetRequest(budgetName: match.displayName, baseRequest: request)
        case .preset:
            return presetRequest(presetName: match.displayName, baseRequest: request)
        case .savingsAccount:
            return savingsAccountRequest(accountName: match.displayName, baseRequest: request)
        case .reconciliationAccount:
            return reconciliationAccountRequest(accountName: match.displayName, baseRequest: request)
        case .workspace:
            var repaired = request
            repaired.targetName = target
            repaired.targetDisplayName = match.displayName
            return repaired
        }
    }

    private func requestPreservingExplicitShape(
        applying match: MarinaCandidateMatch,
        to request: MarinaSemanticRequest
    ) -> MarinaSemanticRequest? {
        var repaired = request

        switch match.entity {
        case .card where request.entity == .card || request.dimensions.contains(.card):
            repaired.targetName = match.displayName
            repaired.targetDisplayName = match.displayName
            return repaired
        case .category where request.entity == .category || request.dimensions.contains(.category):
            repaired.targetName = match.displayName
            repaired.targetDisplayName = match.displayName
            if request.entity == .reconciliationAccount {
                repaired.textQuery = match.displayName
            }
            return repaired
        case .income where request.entity == .income || request.dimensions.contains(.incomeSource):
            repaired.targetName = match.displayName
            repaired.targetDisplayName = match.displayName
            return repaired
        case .preset where request.entity == .preset || request.dimensions.contains(.preset):
            repaired.targetName = match.displayName
            repaired.targetDisplayName = match.displayName
            return repaired
        case .savingsAccount where request.entity == .savingsAccount || request.dimensions.contains(.savingsAccount):
            repaired.targetName = match.displayName
            repaired.targetDisplayName = match.displayName
            return repaired
        case .reconciliationAccount where request.entity == .reconciliationAccount || request.dimensions.contains(.reconciliationAccount):
            repaired.targetName = match.displayName
            repaired.targetDisplayName = match.displayName
            return repaired
        case .budget where request.entity == .budget || request.dimensions.contains(.budget):
            repaired.targetName = match.displayName
            repaired.targetDisplayName = match.displayName
            return repaired
        case .variableExpense where request.dimensions.contains(.merchantText):
            repaired.targetName = nil
            repaired.textQuery = match.displayName
            repaired.targetDisplayName = match.displayName
            return repaired
        case .plannedExpense where request.dimensions.contains(.merchantText):
            repaired.targetName = nil
            repaired.textQuery = match.displayName
            repaired.targetDisplayName = match.displayName
            return repaired
        default:
            return nil
        }
    }

    private func clarificationChoice(
        for match: MarinaCandidateMatch,
        target: String,
        slot: TargetSlot,
        baseRequest: MarinaSemanticRequest,
        includeGenericExpenseAliases: Bool
    ) -> MarinaClarificationChoice {
        MarinaClarificationChoice(
            title: match.displayName,
            kindLabel: kindLabel(for: match),
            subtitle: subtitle(for: match),
            aliases: aliases(for: match.displayName) + aliases(for: target) + aliases(for: match, includeGenericExpenseAliases: includeGenericExpenseAliases),
            request: semanticRequest(applying: match, to: slot, target: target, baseRequest: baseRequest)
        )
    }

    private func aggregateExpenseTextChoice(
        for target: String,
        baseRequest: MarinaSemanticRequest
    ) -> MarinaClarificationChoice {
        let displayName = MarinaL10n.format("marina.clarification.allExpenseMatchesFormat", defaultValue: "All expense matches for \"%@\"", comment: "Clarification choice title for all expense matches.", displayTarget(target))
        return MarinaClarificationChoice(
            title: displayName,
            kindLabel: MarinaL10n.string("marina.clarification.kind.expenseSearch", defaultValue: "Expense search", comment: "Kind label for expense search."),
            subtitle: MarinaL10n.format("marina.clarification.searchEveryExpenseTextFormat", defaultValue: "Search every expense title and description matching %@.", comment: "Clarification choice subtitle for searching every matching expense title and description.", displayTarget(target)),
            aliases: aliases(for: target) + ["merchant", "store", "vendor", "expense", "expenses", "title", "description", "search"],
            request: expenseTextRequest(
                textQuery: target,
                displayName: displayName,
                baseRequest: baseRequest
            )
        )
    }

    private func categoryRequest(categoryName: String, baseRequest: MarinaSemanticRequest) -> MarinaSemanticRequest {
        if baseRequest.operation == .list {
            return MarinaSemanticRequest(
                entity: .variableExpense,
                operation: .list,
                measure: .budgetImpact,
                dimensions: [.category],
                dateRangeToken: baseRequest.dateRangeToken,
                targetName: categoryName,
                targetDisplayName: categoryName,
                resultLimit: baseRequest.resultLimit,
                sort: baseRequest.sort ?? .dateDescending,
                expenseScope: .unified,
                expectedAnswerShape: .list
            )
        }

        return MarinaSemanticRequest(
            entity: .category,
            operation: baseRequest.operation == .average ? .average : .sum,
            measure: .budgetImpact,
            dimensions: [.category],
            dateRangeToken: baseRequest.dateRangeToken,
            targetName: categoryName,
            targetDisplayName: categoryName,
            expenseScope: .unified,
            expectedAnswerShape: .metric
        )
    }

    private func expenseTextRequest(
        textQuery: String,
        displayName: String,
        baseRequest: MarinaSemanticRequest
    ) -> MarinaSemanticRequest {
        let operation: MarinaSemanticOperation
        switch baseRequest.operation {
        case .list, .last, .sum, .average, .count:
            operation = baseRequest.operation
        default:
            operation = .sum
        }

        return MarinaSemanticRequest(
            entity: .variableExpense,
            operation: operation,
            measure: .budgetImpact,
            dimensions: [.merchantText],
            dateRangeToken: baseRequest.dateRangeToken,
            textQuery: textQuery,
            targetDisplayName: displayName,
            resultLimit: baseRequest.resultLimit,
            sort: baseRequest.sort ?? .dateDescending,
            expenseScope: .unified,
            expectedAnswerShape: operation == .list ? .list : .metric
        )
    }

    private func cardRequest(cardName: String, baseRequest: MarinaSemanticRequest) -> MarinaSemanticRequest {
        if baseRequest.operation == .list || baseRequest.operation == .last {
            return MarinaSemanticRequest(
                entity: .variableExpense,
                operation: baseRequest.operation,
                measure: .budgetImpact,
                dimensions: [.card],
                dateRangeToken: baseRequest.dateRangeToken,
                targetName: cardName,
                targetDisplayName: cardName,
                resultLimit: baseRequest.resultLimit,
                sort: baseRequest.sort ?? .dateDescending,
                expenseScope: .unified,
                expectedAnswerShape: baseRequest.operation == .list ? .list : .metric
            )
        }

        return MarinaSemanticRequest(
            entity: .card,
            operation: baseRequest.operation == .average ? .average : .sum,
            measure: .budgetImpact,
            dimensions: [.card],
            dateRangeToken: baseRequest.dateRangeToken,
            targetName: cardName,
            targetDisplayName: cardName,
            expenseScope: .unified,
            expectedAnswerShape: .metric
        )
    }

    private func incomeSourceRequest(source: String, baseRequest: MarinaSemanticRequest) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .income,
            operation: baseRequest.operation == .average ? .average : .sum,
            measure: .incomeAmount,
            dimensions: [.incomeSource],
            dateRangeToken: baseRequest.dateRangeToken,
            targetName: source,
            targetDisplayName: source,
            incomeState: baseRequest.incomeState ?? .all,
            expectedAnswerShape: .metric
        )
    }

    private func budgetRequest(budgetName: String, baseRequest: MarinaSemanticRequest) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .budget,
            operation: .forecast,
            measure: .budgetImpact,
            dimensions: [.budget],
            dateRangeToken: baseRequest.dateRangeToken,
            targetName: budgetName,
            targetDisplayName: budgetName,
            expectedAnswerShape: .metric
        )
    }

    private func presetRequest(presetName: String, baseRequest: MarinaSemanticRequest) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .preset,
            operation: baseRequest.operation == .list ? .list : .sum,
            measure: .plannedAmount,
            dimensions: [.preset],
            dateRangeToken: baseRequest.dateRangeToken,
            targetName: presetName,
            targetDisplayName: presetName,
            resultLimit: baseRequest.resultLimit,
            sort: baseRequest.sort,
            expectedAnswerShape: baseRequest.operation == .list ? .list : .metric
        )
    }

    private func savingsAccountRequest(accountName: String, baseRequest: MarinaSemanticRequest) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .savingsAccount,
            operation: .sum,
            measure: .savingsTotal,
            dimensions: [.savingsAccount],
            dateRangeToken: baseRequest.dateRangeToken,
            targetName: accountName,
            targetDisplayName: accountName,
            expectedAnswerShape: .metric
        )
    }

    private func reconciliationAccountRequest(accountName: String, baseRequest: MarinaSemanticRequest) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .reconciliationAccount,
            operation: .sum,
            measure: .reconciliationBalance,
            dimensions: [.reconciliationAccount],
            dateRangeToken: baseRequest.dateRangeToken,
            targetName: accountName,
            targetDisplayName: accountName,
            expenseScope: .unified,
            expectedAnswerShape: .metric
        )
    }

    private func primaryTargetText(from request: MarinaSemanticRequest) -> String? {
        request.targetName ?? request.textQuery
    }

    private func hasResolvableTarget(_ request: MarinaSemanticRequest) -> Bool {
        if request.targetName == nil,
           request.dimensions.contains(.merchantText),
           request.textQuery?.isEmpty == false {
            return false
        }

        if let target = primaryTargetText(from: request), target.isEmpty == false {
            return true
        }
        if let comparisonTargetName = request.comparisonTargetName, comparisonTargetName.isEmpty == false {
            return true
        }
        return false
    }

    private func clarificationRequest(
        question: String,
        target: String,
        dateRangeToken: MarinaSemanticDateRangeToken
    ) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .workspace,
            operation: .list,
            dateRangeToken: dateRangeToken,
            targetName: target,
            textQuery: target,
            expectedAnswerShape: .clarification,
            clarificationQuestion: question,
            unsupportedReason: .ambiguousEntity
        )
    }

    private func unsupportedRequest(_ reason: MarinaSemanticUnsupportedReason) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .workspace,
            operation: .list,
            expectedAnswerShape: .unsupported,
            unsupportedReason: reason
        )
    }

    private func canonical(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "[^A-Za-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
            .split(separator: " ")
            .map { singularized($0) }
            .joined(separator: " ")
    }

    private func singularized(_ word: Substring) -> String {
        var value = String(word)
        if value.hasSuffix("ies"), value.count > 3 {
            value.removeLast(3)
            return value + "y"
        }
        if value.hasSuffix("ses") == false,
           value.hasSuffix("s"),
           value.count > 1 {
            value.removeLast()
        }
        return value
    }

    private func displayTarget(_ value: String) -> String {
        value
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + String($0.dropFirst()) }
            .joined(separator: " ")
    }

    private func aliases(for value: String) -> [String] {
        let canonicalValue = canonical(value)
        let displayValue = displayTarget(value)
        return Array(Set([value, displayValue, canonicalValue]))
    }

    private func aliases(
        for match: MarinaCandidateMatch,
        includeGenericExpenseAliases: Bool
    ) -> [String] {
        switch match.entity {
        case .category:
            return ["category"]
        case .income:
            return ["income", "income source"]
        case .variableExpense:
            return includeGenericExpenseAliases ? ["merchant", "store", "vendor", "expense", "expenses", "description", "search"] : ["expense match"]
        case .plannedExpense:
            return includeGenericExpenseAliases ? ["planned", "planned expense", "title", "expense", "search"] : ["planned expense match"]
        case .card:
            return ["card"]
        case .budget:
            return ["budget"]
        case .preset:
            return ["preset"]
        case .savingsAccount:
            return ["savings", "savings account"]
        case .reconciliationAccount:
            return ["balance", "reconciliation", "shared balance"]
        case .workspace:
            return ["workspace"]
        }
    }

    private func kindLabel(for match: MarinaCandidateMatch) -> String {
        switch match.entity {
        case .category:
            return MarinaL10n.common("category", defaultValue: "Category", comment: "Common label for category.")
        case .income:
            return MarinaL10n.string("marina.clarification.kind.incomeSource", defaultValue: "Income source", comment: "Kind label for an income source clarification choice.")
        case .variableExpense:
            return MarinaL10n.string("marina.clarification.kind.expenseMatch", defaultValue: "Expense match", comment: "Kind label for a matching expense.")
        case .plannedExpense:
            return MarinaL10n.string("marina.clarification.kind.plannedExpenseMatch", defaultValue: "Planned expense match", comment: "Kind label for a matching planned expense.")
        case .card:
            return MarinaL10n.common("card", defaultValue: "Card", comment: "Common label for card.")
        case .budget:
            return MarinaL10n.common("budget", defaultValue: "Budget", comment: "Common label for budget.")
        case .preset:
            return MarinaL10n.common("preset", defaultValue: "Preset", comment: "Common label for preset.")
        case .savingsAccount:
            return MarinaL10n.string("marina.clarification.kind.savingsAccount", defaultValue: "Savings account", comment: "Kind label for savings account clarification choice.")
        case .reconciliationAccount:
            return MarinaL10n.string("marina.clarification.kind.reconciliationAccount", defaultValue: "Reconciliation account", comment: "Kind label for reconciliation account clarification choice.")
        case .workspace:
            return MarinaL10n.common("workspace", defaultValue: "Workspace", comment: "Common label for workspace.")
        }
    }

    private func subtitle(for match: MarinaCandidateMatch) -> String {
        switch match.entity {
        case .category:
            return MarinaL10n.format("marina.clarification.useCategoryFormat", defaultValue: "Use the %@ category.", comment: "Clarification choice subtitle for using a category.", match.displayName)
        case .income:
            return MarinaL10n.format("marina.clarification.useIncomeSourceFormat", defaultValue: "Use %@ as the income source.", comment: "Clarification choice subtitle for using an income source.", match.displayName)
        case .variableExpense, .plannedExpense:
            if match.occurrenceCount > 1 {
                return MarinaL10n.format("marina.clarification.searchExpenseTextCountFormat", defaultValue: "Search %@ matching expense rows.", comment: "Clarification choice subtitle for searching matching expense text rows.", "\(match.occurrenceCount)")
            }
            return MarinaL10n.format("marina.clarification.searchExpenseTextFormat", defaultValue: "Search expense titles and descriptions for %@.", comment: "Clarification choice subtitle for searching expense text.", match.displayName)
        case .card:
            return MarinaL10n.format("marina.clarification.useAsCardFormat", defaultValue: "Use %@ as the card.", comment: "Clarification choice subtitle for using a card.", match.displayName)
        case .budget:
            return MarinaL10n.format("marina.clarification.useBudgetFormat", defaultValue: "Use the %@ budget.", comment: "Clarification choice subtitle for using a budget.", match.displayName)
        case .preset:
            return MarinaL10n.format("marina.clarification.usePresetFormat", defaultValue: "Use the %@ preset.", comment: "Clarification choice subtitle for using a preset.", match.displayName)
        case .savingsAccount:
            return MarinaL10n.format("marina.clarification.useSavingsAccountFormat", defaultValue: "Use %@ as the savings account.", comment: "Clarification choice subtitle for using a savings account.", match.displayName)
        case .reconciliationAccount:
            return MarinaL10n.format("marina.clarification.useReconciliationAccountFormat", defaultValue: "Use %@ as the reconciliation account.", comment: "Clarification choice subtitle for using a reconciliation account.", match.displayName)
        case .workspace:
            return match.displayName
        }
    }

    private func deduped(_ choices: [MarinaClarificationChoice]) -> [MarinaClarificationChoice] {
        var seen: Set<String> = []
        var result: [MarinaClarificationChoice] = []
        for choice in choices {
            let key = "\(canonical(choice.title))|\(choice.kindLabel ?? "")"
            guard seen.contains(key) == false else { continue }
            seen.insert(key)
            result.append(choice)
        }
        return result
    }

    private func isExpenseTextMatch(_ match: MarinaCandidateMatch) -> Bool {
        match.entity == .variableExpense || match.entity == .plannedExpense
    }
}
