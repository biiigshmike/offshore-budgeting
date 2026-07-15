import Foundation

struct MarinaSemanticCandidateResolution: Equatable, Sendable {
    let interpreted: MarinaInterpretedSemanticRequest
    let candidateSearches: [MarinaCandidateSearchTrace]
}

struct MarinaSemanticCandidateResolver {
    private enum TargetSlot {
        case primary
        case comparison

        var clarificationSlot: MarinaClarificationTargetSlot {
            switch self {
            case .primary: .primary
            case .comparison: .comparison
            }
        }
    }

    private struct ConstraintResolution {
        let request: MarinaSemanticRequest
        let notes: [String]
        let candidateSearches: [MarinaCandidateSearchTrace]
        let terminal: MarinaInterpretedSemanticRequest?
    }

    private let candidateSearchService: MarinaCandidateSearchService

    init(candidateSearchService: MarinaCandidateSearchService = MarinaCandidateSearchService()) {
        self.candidateSearchService = candidateSearchService
    }

    func resolve(
        interpreted: MarinaInterpretedSemanticRequest,
        snapshot: MarinaWorkspaceSnapshot,
        candidateDateRange: HomeQueryDateRange? = nil
    ) -> MarinaInterpretedSemanticRequest {
        resolveWithTrace(
            interpreted: interpreted,
            snapshot: snapshot,
            candidateDateRange: candidateDateRange
        ).interpreted
    }

    func resolveWithTrace(
        interpreted: MarinaInterpretedSemanticRequest,
        snapshot: MarinaWorkspaceSnapshot,
        candidateDateRange: HomeQueryDateRange? = nil
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

        if request.constraints.contains(where: { $0.dimension != .date && $0.resolvedReference == nil }) {
            let constraintResolution = resolveConstraints(
                request: request,
                interpreted: interpreted,
                notes: notes,
                snapshot: snapshot,
                candidateDateRange: candidateDateRange
            )
            request = constraintResolution.request
            notes = constraintResolution.notes
            candidateSearches.append(contentsOf: constraintResolution.candidateSearches)
            if let terminal = constraintResolution.terminal {
                return MarinaSemanticCandidateResolution(
                    interpreted: terminal,
                    candidateSearches: candidateSearches
                )
            }
        }

        if let target = primaryTargetText(from: request), target.isEmpty == false {
            let searchResult = candidateSearchResult(
                target: target,
                request: request,
                snapshot: snapshot,
                dateRange: candidateDateRange
            )
            candidateSearches.append(MarinaCandidateSearchTrace(rawTargetText: target, slot: "primary", result: searchResult))

            if isExplicitMerchantAggregate(request) {
                let expenseEvidence = searchResult.matches.filter {
                    isExpenseTextMatch($0) && $0.occurrenceCount > 0
                }
                guard expenseEvidence.isEmpty == false else {
                    notes.append("Candidate resolver found no scoped expense-text evidence for \"\(target)\".")
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
                request = applyingExplicitMerchantAggregate(
                    target,
                    to: request,
                    workspaceID: snapshot.workspace.id
                )
                notes.append("Candidate resolver grounded explicit merchant text \"\(target)\" as one aggregate expense search.")
            } else {
                if let terminal = terminalInterpretedRequest(
                    searchResult: searchResult,
                    target: target,
                    slot: .primary,
                    request: request,
                    interpreted: interpreted,
                    notes: notes,
                    workspaceID: snapshot.workspace.id
                ) {
                    return MarinaSemanticCandidateResolution(
                        interpreted: terminal,
                        candidateSearches: candidateSearches
                    )
                }

                if let explicitMatch = explicitDimensionMatch(in: searchResult, request: request, slot: .primary) {
                    request = semanticRequest(
                        applying: explicitMatch,
                        to: .primary,
                        target: target,
                        baseRequest: request,
                        provenance: request.targetKindSource == .explicit ? .explicitTargetType : nil,
                        workspaceID: snapshot.workspace.id
                    )
                    notes.append("Candidate resolver selected explicit \(explicitMatch.entity.rawValue) match \(explicitMatch.displayName) for \"\(target)\".")
                } else if let recommendedMatch = searchResult.recommendedMatch {
                    request = semanticRequest(
                        applying: recommendedMatch,
                        to: .primary,
                        target: target,
                        baseRequest: request,
                        workspaceID: snapshot.workspace.id
                    )
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
        }

        if let comparisonTargetName = request.comparisonTargetName,
           comparisonTargetName.isEmpty == false {
            let searchResult = candidateSearchResult(
                target: comparisonTargetName,
                request: request,
                snapshot: snapshot,
                dateRange: candidateDateRange
            )
            candidateSearches.append(MarinaCandidateSearchTrace(rawTargetText: comparisonTargetName, slot: "comparison", result: searchResult))

            if let terminal = terminalInterpretedRequest(
                searchResult: searchResult,
                target: comparisonTargetName,
                slot: .comparison,
                request: request,
                interpreted: interpreted,
                notes: notes,
                workspaceID: snapshot.workspace.id
            ) {
                return MarinaSemanticCandidateResolution(
                    interpreted: terminal,
                    candidateSearches: candidateSearches
                )
            }

            if let explicitMatch = explicitDimensionMatch(in: searchResult, request: request, slot: .comparison) {
                request = semanticRequest(
                    applying: explicitMatch,
                    to: .comparison,
                    target: comparisonTargetName,
                    baseRequest: request,
                    provenance: request.comparisonTargetKindSource == .explicit ? .explicitTargetType : nil,
                    workspaceID: snapshot.workspace.id
                )
                notes.append("Candidate resolver selected explicit \(explicitMatch.entity.rawValue) match \(explicitMatch.displayName) for comparison target \"\(comparisonTargetName)\".")
            } else if let recommendedMatch = searchResult.recommendedMatch {
                request = semanticRequest(
                    applying: recommendedMatch,
                    to: .comparison,
                    target: comparisonTargetName,
                    baseRequest: request,
                    workspaceID: snapshot.workspace.id
                )
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
        request: MarinaSemanticRequest,
        slot: TargetSlot
    ) -> MarinaCandidateMatch? {
        let kindSource = switch slot {
        case .primary: request.targetKindSource
        case .comparison: request.comparisonTargetKindSource
        }
        guard kindSource == .explicit || kindSource == .unspecified else { return nil }
        guard let entity = explicitlyTargetedEntity(in: request) else {
            return nil
        }

        let matches = searchResult.matches.filter {
            $0.entity == entity && $0.isStrongEnoughForAutomaticResolution
        }
        let liveMatches = matches.filter { $0.evidence == .liveRecord }
        if liveMatches.count == 1 {
            return liveMatches[0]
        }
        guard liveMatches.isEmpty, matches.count == 1 else { return nil }
        return matches[0]
    }

    private func explicitlyTargetedEntity(in request: MarinaSemanticRequest) -> MarinaSemanticEntity? {
        if request.dimensions.contains(.card) { return .card }
        if request.dimensions.contains(.category) { return .category }
        if request.dimensions.contains(.incomeSource) { return .income }
        if request.dimensions.contains(.incomeSeries) { return .incomeSeries }
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
        if request.dimensions.contains(.incomeSeries) { return false }
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

    private func resolveConstraints(
        request originalRequest: MarinaSemanticRequest,
        interpreted: MarinaInterpretedSemanticRequest,
        notes originalNotes: [String],
        snapshot: MarinaWorkspaceSnapshot,
        candidateDateRange: HomeQueryDateRange?
    ) -> ConstraintResolution {
        var request = originalRequest
        var notes = originalNotes
        var traces: [MarinaCandidateSearchTrace] = []

        let orderedConstraintIndices = request.constraints.indices.sorted { lhs, rhs in
            let lhsIsBudget = request.constraints[lhs].dimension == .budget
            let rhsIsBudget = request.constraints[rhs].dimension == .budget
            return lhsIsBudget && rhsIsBudget == false
        }
        for index in orderedConstraintIndices {
            let constraint = request.constraints[index]
            guard constraint.dimension != .date,
                  constraint.resolvedReference == nil else {
                continue
            }

            let result = candidateSearchResult(
                target: constraint.value,
                request: request,
                snapshot: snapshot,
                dateRange: candidateDateRange
            )
            traces.append(
                MarinaCandidateSearchTrace(
                    rawTargetText: constraint.value,
                    slot: "constraint.\(constraint.dimension.rawValue)",
                    result: result
                )
            )

            let matching = result.matches.filter {
                match($0, satisfies: constraint.dimension)
                    && $0.semanticHintFit != .conflicting
            }
            let exact = matching.filter { $0.matchStrength.isExactEquivalent }

            if constraint.dimension == .merchantText,
               matching.contains(where: { $0.occurrenceCount > 0 }) {
                request = applyingMerchantAggregateConstraint(
                    at: index,
                    target: constraint.value,
                    to: request,
                    workspaceID: snapshot.workspace.id
                )
                notes.append("Candidate resolver grounded merchant-text constraint \"\(constraint.value)\" as an aggregate expense search.")
                continue
            }

            let preferredExact = preferredExactMatches(in: exact)
            if preferredExact.count == 1, let match = preferredExact.first {
                request = applyingConstraintMatch(match, at: index, to: request, workspaceID: snapshot.workspace.id)
                notes.append("Candidate resolver grounded \(constraint.dimension.rawValue) constraint \"\(constraint.value)\" to \(match.displayName).")
                continue
            }

            let suggestions = preferredExact.isEmpty
                ? matching.filter { $0.matchStrength.isExactEquivalent == false }
                : preferredExact
            if suggestions.isEmpty == false {
                let choices = constraintChoices(
                    from: suggestions,
                    constraintIndex: index,
                    baseRequest: request,
                    workspaceID: snapshot.workspace.id
                )
                let question = MarinaL10n.format(
                    "marina.clarification.constraintMeaningFormat",
                    defaultValue: "Which %@ should Marina use for \"%@\"?",
                    comment: "Clarification question for resolving an ambiguous typed constraint.",
                    constraint.dimension.rawValue,
                    constraint.value
                )
                var terminalRequest = request
                terminalRequest.expectedAnswerShape = .clarification
                terminalRequest.clarificationQuestion = question
                terminalRequest.unsupportedReason = .ambiguousEntity
                notes.append("Candidate resolver found \(choices.count) possible \(constraint.dimension.rawValue) meanings for \"\(constraint.value)\".")
                let terminal = interpretedWith(
                    request: terminalRequest,
                    interpreted: interpreted,
                    notes: notes,
                    choices: MarinaClarificationChoices(question: question, choices: choices)
                )
                return ConstraintResolution(
                    request: terminalRequest,
                    notes: notes,
                    candidateSearches: traces,
                    terminal: terminal
                )
            }

            notes.append("Candidate resolver could not ground \(constraint.dimension.rawValue) constraint \"\(constraint.value)\".")
            let terminalRequest = unsupportedRequest(.unresolvedEntity)
            let terminal = interpretedWith(
                request: terminalRequest,
                interpreted: interpreted,
                notes: notes,
                choices: interpreted.clarificationChoices
            )
            return ConstraintResolution(
                request: terminalRequest,
                notes: notes,
                candidateSearches: traces,
                terminal: terminal
            )
        }

        return ConstraintResolution(
            request: request,
            notes: notes,
            candidateSearches: traces,
            terminal: nil
        )
    }

    private func preferredExactMatches(in matches: [MarinaCandidateMatch]) -> [MarinaCandidateMatch] {
        let aliases = matches.filter { $0.evidence == .assistantAlias }
        return aliases.isEmpty ? matches : aliases
    }

    private func match(
        _ match: MarinaCandidateMatch,
        satisfies dimension: MarinaSemanticDimension
    ) -> Bool {
        switch dimension {
        case .date:
            return false
        case .category:
            return match.entity == .category
        case .card:
            return match.entity == .card
        case .merchantText:
            return isExpenseTextMatch(match)
        case .budget:
            return match.entity == .budget
        case .incomeSource:
            return match.entity == .income
        case .incomeSeries:
            return match.entity == .incomeSeries
        case .preset:
            return match.entity == .preset
        case .savingsAccount:
            return match.entity == .savingsAccount
        case .reconciliationAccount:
            return match.entity == .reconciliationAccount
        case .workspace:
            return match.entity == .workspace
        }
    }

    private func applyingConstraintMatch(
        _ match: MarinaCandidateMatch,
        at index: Int,
        to baseRequest: MarinaSemanticRequest,
        workspaceID: UUID,
        provenance: MarinaResolutionProvenance? = nil
    ) -> MarinaSemanticRequest {
        var request = baseRequest
        guard request.constraints.indices.contains(index) else { return request }
        let oldConstraint = request.constraints[index]
        let sourceID = isExpenseTextMatch(match)
            ? nil
            : match.sourceID.flatMap(UUID.init(uuidString:))
        let reference = MarinaResolvedEntityReference(
            entity: match.entity,
            id: sourceID,
            displayName: match.displayName,
            provenance: provenance ?? resolutionProvenance(for: match)
        )
        request.constraints[index] = MarinaSemanticConstraint(
            dimension: oldConstraint.dimension,
            value: match.displayName,
            resolvedReference: reference,
            kindSource: oldConstraint.kindSource
        )
        if oldConstraint.dimension == .budget, let sourceID {
            request.resolvedScope = .budget(sourceID)
            if request.dateRangeSource == .defaulted {
                request.dateRangeToken = .allTime
            }
        } else if request.resolvedScope == nil {
            request.resolvedScope = .workspace(workspaceID)
        }
        return request
    }

    private func applyingMerchantAggregateConstraint(
        at index: Int,
        target: String,
        to baseRequest: MarinaSemanticRequest,
        workspaceID: UUID
    ) -> MarinaSemanticRequest {
        var request = baseRequest
        guard request.constraints.indices.contains(index) else { return request }
        let oldConstraint = request.constraints[index]
        request.constraints[index] = MarinaSemanticConstraint(
            dimension: .merchantText,
            value: target,
            resolvedReference: MarinaResolvedEntityReference(
                entity: .variableExpense,
                id: nil,
                displayName: target,
                provenance: oldConstraint.kindSource == .explicit ? .explicitTargetType : .candidateResolver
            ),
            kindSource: oldConstraint.kindSource
        )
        if request.resolvedScope == nil {
            request.resolvedScope = .workspace(workspaceID)
        }
        return request
    }

    private func isExplicitMerchantAggregate(_ request: MarinaSemanticRequest) -> Bool {
        request.targetKindSource == .explicit
            && request.dimensions.contains(.merchantText)
            && request.textQuery?.isEmpty == false
    }

    private func applyingExplicitMerchantAggregate(
        _ target: String,
        to baseRequest: MarinaSemanticRequest,
        workspaceID: UUID
    ) -> MarinaSemanticRequest {
        var request = baseRequest
        request.targetName = target
        request.textQuery = target
        request.targetDisplayName = target
        request.resolvedTarget = MarinaResolvedEntityReference(
            entity: .variableExpense,
            id: nil,
            displayName: target,
            provenance: .explicitTargetType
        )
        if request.resolvedScope == nil {
            request.resolvedScope = .workspace(workspaceID)
        }
        return request
    }

    private func constraintChoices(
        from matches: [MarinaCandidateMatch],
        constraintIndex: Int,
        baseRequest: MarinaSemanticRequest,
        workspaceID: UUID
    ) -> [MarinaClarificationChoice] {
        let duplicateNames = Dictionary(grouping: matches) { canonical($0.displayName) }
        return deduped(matches.map { match in
            let request = applyingConstraintMatch(
                match,
                at: constraintIndex,
                to: baseRequest,
                workspaceID: workspaceID,
                provenance: .clarificationChoice
            )
            let shortID = match.sourceID.map { String($0.suffix(6)) }
            let hasDuplicateName = (duplicateNames[canonical(match.displayName)]?.count ?? 0) > 1
            let baseSubtitle = subtitle(for: match)
            let choiceSubtitle = hasDuplicateName && shortID != nil
                ? "\(baseSubtitle) ID …\(shortID!)."
                : baseSubtitle
            let source = match.sourceID ?? "\(match.fieldName):\(canonical(match.displayName))"
            return MarinaClarificationChoice(
                meaningKey: "constraint|\(constraintIndex)|\(match.entity.rawValue)|\(source)",
                title: match.displayName,
                kindLabel: kindLabel(for: match),
                subtitle: choiceSubtitle,
                aliases: aliases(for: match.displayName),
                request: request
            )
        })
    }

    private func terminalInterpretedRequest(
        searchResult: MarinaCandidateSearchResult,
        target: String,
        slot: TargetSlot,
        request: MarinaSemanticRequest,
        interpreted: MarinaInterpretedSemanticRequest,
        notes: [String],
        workspaceID: UUID
    ) -> MarinaInterpretedSemanticRequest? {
        if explicitDimensionMatch(in: searchResult, request: request, slot: slot) != nil {
            return nil
        }
        let exactMatches = searchResult.matches.filter(\.isStrongEnoughForAutomaticResolution)
        let suggestionMatches = searchResult.matches.filter {
            $0.semanticHintFit != .conflicting && $0.matchStrength.isExactEquivalent == false
        }
        let usefulMatches = exactMatches.count > 1
            ? exactMatches
            : (exactMatches.isEmpty ? suggestionMatches : [])
        guard usefulMatches.isEmpty == false else { return nil }

        let choices = candidateChoices(
            from: usefulMatches,
            target: target,
            slot: slot,
            baseRequest: request,
            workspaceID: workspaceID
        )
        guard choices.isEmpty == false else { return nil }

        let question = MarinaL10n.format("marina.clarification.targetMeaningFormat", defaultValue: "What should Marina use for \"%@\"?", comment: "Clarification question for resolving an ambiguous target.", target)
        var clarificationRequest = request
        clarificationRequest.expectedAnswerShape = .clarification
        clarificationRequest.clarificationQuestion = question
        clarificationRequest.unsupportedReason = .ambiguousEntity
        switch slot {
        case .primary:
            clarificationRequest.targetName = target
            clarificationRequest.resolvedTarget = nil
        case .comparison:
            clarificationRequest.comparisonTargetName = target
            clarificationRequest.resolvedComparisonTarget = nil
        }
        var notes = notes
        notes.append("Candidate resolver found \(choices.count) possible meanings for \"\(target)\".")
        return interpretedWith(
            request: clarificationRequest,
            interpreted: interpreted,
            notes: notes,
            choices: MarinaClarificationChoices(question: question, choices: choices)
        )
    }

    private func candidateSearchResult(
        target: String,
        request: MarinaSemanticRequest,
        snapshot: MarinaWorkspaceSnapshot,
        dateRange: HomeQueryDateRange? = nil
    ) -> MarinaCandidateSearchResult {
        candidateSearchService.search(
            MarinaCandidateSearchRequest(
                rawTargetText: target,
                semanticRequest: request,
                snapshot: snapshot,
                dateRange: dateRange
            )
        )
    }

    private func candidateChoices(
        from matches: [MarinaCandidateMatch],
        target: String,
        slot: TargetSlot,
        baseRequest: MarinaSemanticRequest,
        workspaceID: UUID
    ) -> [MarinaClarificationChoice] {
        let expenseMatches = matches.filter(isExpenseTextMatch)
        let hasMultipleExpenseTextMatches = expenseMatches.count > 1
        var choices = matches.map {
            clarificationChoice(
                for: $0,
                target: target,
                slot: slot,
                baseRequest: baseRequest,
                includeGenericExpenseAliases: hasMultipleExpenseTextMatches == false,
                workspaceID: workspaceID
            )
        }

        if slot == .primary, hasMultipleExpenseTextMatches {
            choices.append(
                aggregateExpenseTextChoice(
                    for: target,
                    baseRequest: baseRequest,
                    workspaceID: workspaceID
                )
            )
        }

        return deduped(choices)
    }

    private func semanticRequest(
        applying match: MarinaCandidateMatch,
        to slot: TargetSlot,
        target: String,
        baseRequest request: MarinaSemanticRequest,
        provenance: MarinaResolutionProvenance? = nil,
        workspaceID: UUID
    ) -> MarinaSemanticRequest {
        let shapedRequest: MarinaSemanticRequest
        if slot == .comparison {
            var repaired = request
            repaired.comparisonTargetName = match.displayName
            shapedRequest = repaired
        } else if let repaired = requestPreservingExplicitShape(applying: match, to: request) {
            shapedRequest = repaired
        } else {
            switch match.entity {
            case .category:
                shapedRequest = categoryRequest(categoryName: match.displayName, baseRequest: request)
            case .income:
                shapedRequest = incomeSourceRequest(source: match.displayName, baseRequest: request)
            case .incomeSeries:
                shapedRequest = incomeSeriesRequest(source: match.displayName, baseRequest: request)
            case .variableExpense, .plannedExpense:
                shapedRequest = expenseTextRequest(textQuery: match.displayName, displayName: match.displayName, baseRequest: request)
            case .card:
                shapedRequest = cardRequest(cardName: match.displayName, baseRequest: request)
            case .budget:
                shapedRequest = budgetRequest(budgetName: match.displayName, baseRequest: request)
            case .preset:
                shapedRequest = presetRequest(presetName: match.displayName, baseRequest: request)
            case .savingsAccount:
                shapedRequest = savingsAccountRequest(accountName: match.displayName, baseRequest: request)
            case .reconciliationAccount:
                shapedRequest = reconciliationAccountRequest(accountName: match.displayName, baseRequest: request)
            case .workspace:
                var repaired = request
                repaired.targetName = target
                repaired.targetDisplayName = match.displayName
                shapedRequest = repaired
            }
        }

        return applyingResolution(
            for: match,
            to: slot,
            request: shapedRequest,
            baseRequest: request,
            provenance: provenance ?? resolutionProvenance(for: match),
            workspaceID: workspaceID
        )
    }

    private func applyingResolution(
        for match: MarinaCandidateMatch,
        to slot: TargetSlot,
        request: MarinaSemanticRequest,
        baseRequest: MarinaSemanticRequest,
        provenance: MarinaResolutionProvenance,
        workspaceID: UUID
    ) -> MarinaSemanticRequest {
        let patch = targetPatch(
            for: match,
            slot: slot,
            baseRequest: baseRequest,
            provenance: provenance,
            workspaceID: workspaceID
        )
        var resolved = patch.applying(to: request)
        if match.entity == .budget, resolved.dateRangeSource == .defaulted {
            resolved.dateRangeToken = .allTime
        }
        return resolved
    }

    private func targetPatch(
        for match: MarinaCandidateMatch,
        slot: TargetSlot,
        baseRequest: MarinaSemanticRequest,
        provenance: MarinaResolutionProvenance,
        workspaceID: UUID
    ) -> MarinaClarificationTargetPatch {
        let sourceID = isExpenseTextMatch(match)
            ? nil
            : match.sourceID.flatMap { UUID(uuidString: $0) }
        let reference = MarinaResolvedEntityReference(
            entity: match.entity,
            id: sourceID,
            displayName: match.displayName,
            provenance: provenance
        )
        let scope: MarinaResolvedScope
        if match.entity == .budget, let sourceID {
            scope = .budget(sourceID)
        } else {
            scope = baseRequest.resolvedScope ?? .workspace(workspaceID)
        }
        return MarinaClarificationTargetPatch(
            slot: slot.clarificationSlot,
            reference: reference,
            scope: scope
        )
    }

    private func resolutionProvenance(for match: MarinaCandidateMatch) -> MarinaResolutionProvenance {
        switch match.evidence {
        case .liveRecord:
            return .candidateResolver
        case .assistantAlias:
            return .assistantAlias
        case .importMerchantRule:
            return .importMerchantRule
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
        case .incomeSeries where request.entity == .incomeSeries || request.dimensions.contains(.incomeSeries):
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
        includeGenericExpenseAliases: Bool,
        workspaceID: UUID
    ) -> MarinaClarificationChoice {
        let patch = targetPatch(
            for: match,
            slot: slot,
            baseRequest: baseRequest,
            provenance: .clarificationChoice,
            workspaceID: workspaceID
        )
        return MarinaClarificationChoice(
            meaningKey: meaningKey(for: match, slot: slot),
            title: match.displayName,
            kindLabel: kindLabel(for: match),
            subtitle: subtitle(for: match),
            aliases: aliases(for: match.displayName)
                + aliases(for: match, includeGenericExpenseAliases: includeGenericExpenseAliases),
            targetPatch: patch,
            request: semanticRequest(
                applying: match,
                to: slot,
                target: target,
                baseRequest: baseRequest,
                provenance: .clarificationChoice,
                workspaceID: workspaceID
            )
        )
    }

    private func aggregateExpenseTextChoice(
        for target: String,
        baseRequest: MarinaSemanticRequest,
        workspaceID: UUID
    ) -> MarinaClarificationChoice {
        let displayName = MarinaL10n.format("marina.clarification.allExpenseMatchesFormat", defaultValue: "All expense matches for \"%@\"", comment: "Clarification choice title for all expense matches.", displayTarget(target))
        let scope = baseRequest.resolvedScope ?? .workspace(workspaceID)
        let patch = MarinaClarificationTargetPatch(
            slot: .primary,
            reference: MarinaResolvedEntityReference(
                entity: .variableExpense,
                id: nil,
                displayName: displayName,
                provenance: .clarificationChoice
            ),
            scope: scope
        )
        let request = patch.applying(
            to: expenseTextRequest(
                textQuery: target,
                displayName: displayName,
                baseRequest: baseRequest
            )
        )
        return MarinaClarificationChoice(
            meaningKey: "primary|expenseSearch|\(canonical(target))",
            title: displayName,
            kindLabel: MarinaL10n.string("marina.clarification.kind.expenseSearch", defaultValue: "Expense search", comment: "Kind label for expense search."),
            subtitle: MarinaL10n.format("marina.clarification.searchEveryExpenseTextFormat", defaultValue: "Search every expense title and description matching %@.", comment: "Clarification choice subtitle for searching every matching expense title and description.", displayTarget(target)),
            aliases: aliases(for: target) + ["merchant", "store", "vendor", "expense", "expenses", "title", "description", "search"],
            targetPatch: patch,
            request: request
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

    private func incomeSeriesRequest(source: String, baseRequest: MarinaSemanticRequest) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .incomeSeries,
            operation: baseRequest.operation,
            measure: baseRequest.measure ?? .incomeAmount,
            projection: baseRequest.projection,
            dimensions: [.incomeSeries],
            constraints: baseRequest.constraints,
            dateRangeToken: baseRequest.dateRangeToken,
            dateRangeSource: baseRequest.dateRangeSource,
            targetName: source,
            targetDisplayName: source,
            targetKindSource: baseRequest.targetKindSource,
            resultLimit: baseRequest.resultLimit,
            resultOffset: baseRequest.resultOffset,
            sort: baseRequest.sort,
            expectedAnswerShape: baseRequest.expectedAnswerShape
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
        if request.constraints.contains(where: {
            $0.dimension != .date && $0.resolvedReference == nil && $0.value.isEmpty == false
        }) {
            return true
        }
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
        MarinaCanonicalTextNormalizer.canonical(value)
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

    private func meaningKey(
        for match: MarinaCandidateMatch,
        slot: TargetSlot
    ) -> String {
        let source = match.sourceID
            ?? "\(match.fieldName):\(canonical(match.displayName))"
        return "\(slot.clarificationSlot.rawValue)|\(match.entity.rawValue)|\(source)"
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
        case .incomeSeries:
            return ["income series", "recurring income", "schedule"]
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
        case .incomeSeries:
            return MarinaL10n.string("marina.clarification.kind.incomeSeries", defaultValue: "Income series", comment: "Kind label for an income series clarification choice.")
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
        case .incomeSeries:
            return MarinaL10n.format("marina.clarification.useIncomeSeriesFormat", defaultValue: "Use %@ as the recurring income series.", comment: "Clarification choice subtitle for using an income series.", match.displayName)
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
            let key = choice.meaningKey
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
