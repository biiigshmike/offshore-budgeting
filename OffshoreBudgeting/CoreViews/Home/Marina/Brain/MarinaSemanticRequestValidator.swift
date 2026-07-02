import Foundation

struct MarinaSemanticValidationTrace: Equatable, Sendable {
    let interpreted: MarinaInterpretedSemanticRequest
    let resolverOutput: MarinaInterpretedSemanticRequest
    let candidateSearches: [MarinaCandidateSearchTrace]
    let explicitPromptTargets: [String]
}

struct MarinaSemanticRequestValidator {
    private let candidateResolver: MarinaSemanticCandidateResolver
    private let capabilityRegistry: MarinaQueryCapabilityRegistry
    private let formulaRepair: MarinaSemanticFormulaRepair

    init(
        candidateResolver: MarinaSemanticCandidateResolver = MarinaSemanticCandidateResolver(),
        capabilityRegistry: MarinaQueryCapabilityRegistry = MarinaQueryCapabilityRegistry(),
        formulaRepair: MarinaSemanticFormulaRepair = MarinaSemanticFormulaRepair()
    ) {
        self.candidateResolver = candidateResolver
        self.capabilityRegistry = capabilityRegistry
        self.formulaRepair = formulaRepair
    }

    func validate(
        interpreted: MarinaInterpretedSemanticRequest,
        snapshot: MarinaWorkspaceSnapshot,
        originalPrompt: String? = nil
    ) -> MarinaInterpretedSemanticRequest {
        validateWithTrace(
            interpreted: interpreted,
            snapshot: snapshot,
            originalPrompt: originalPrompt
        )
        .interpreted
    }

    func validateWithTrace(
        interpreted: MarinaInterpretedSemanticRequest,
        snapshot: MarinaWorkspaceSnapshot,
        originalPrompt: String? = nil
    ) -> MarinaSemanticValidationTrace {
        var request = interpreted.request
        var notes = interpreted.diagnosticNotes
        var source = interpreted.source
        let explicitTargets = explicitPromptTargets(in: originalPrompt, snapshot: snapshot)

        if request.expectedAnswerShape == .unsupported && request.unsupportedReason == nil {
            request.unsupportedReason = .unsupportedCombination
            notes.append("Validation added missing unsupported reason.")
        }

        if request.expectedAnswerShape == .clarification || request.expectedAnswerShape == .unsupported {
            notes.append("Validation skipped for terminal semantic shape.")
            let terminal = interpretedWith(request: request, interpreted: interpreted, source: source, notes: notes)
            return MarinaSemanticValidationTrace(
                interpreted: terminal,
                resolverOutput: terminal,
                candidateSearches: [],
                explicitPromptTargets: explicitTargets
            )
        }

        let resolution = candidateResolver.resolveWithTrace(interpreted: interpreted, snapshot: snapshot)
        var resolved = resolution.interpreted
        var resolverOutput = resolved
        var candidateSearches = resolution.candidateSearches
        request = resolved.request
        notes = resolved.diagnosticNotes
        source = resolved.source

        if request.expectedAnswerShape == .clarification || request.expectedAnswerShape == .unsupported {
            notes.append("Validation accepted resolver terminal semantic shape.")
            let terminal = interpretedWith(
                request: request,
                interpreted: resolved,
                source: source,
                notes: notes,
                clarificationChoices: resolved.clarificationChoices
            )
            return MarinaSemanticValidationTrace(
                interpreted: terminal,
                resolverOutput: resolverOutput,
                candidateSearches: candidateSearches,
                explicitPromptTargets: explicitTargets
            )
        }

        if let restored = restoreExplicitCategoryTargetIfNeeded(
            request,
            originalRequest: interpreted.request,
            snapshot: snapshot
        ) {
            request = restored
            notes.append("Validation restored explicit category target after candidate resolution.")
        }

        if let normalized = categoryExpenseListRequestIfNeeded(request) {
            request = normalized
            notes.append("Validation normalized category expense list semantics into an expense row list.")
        }

        if let repaired = repairMerchantSpendIfNeeded(request, snapshot: snapshot) {
            request = repaired
            notes.append("Validation repaired unresolved card target into merchant text spend.")
            if source == .foundationModel {
                source = .repairedFoundationModel
            }
        }

        if shouldAttemptExplicitPromptTargetFallback(
            source: source,
            request: interpreted.request,
            explicitTargets: explicitTargets
        ) {
            let hasExplicitCardComparisonIntent = hasClearCardComparisonIntent(
                in: originalPrompt,
                request: request
            )
            let fallback = candidateResolver.resolveExplicitPromptTargetsWithTrace(
                interpreted: interpretedWith(
                    request: request,
                    interpreted: resolved,
                    source: source,
                    notes: notes,
                    clarificationChoices: resolved.clarificationChoices
                ),
                snapshot: snapshot,
                explicitPromptTargets: explicitTargets,
                hasExplicitCardComparisonIntent: hasExplicitCardComparisonIntent
            )
            candidateSearches.append(contentsOf: fallback.candidateSearches)
            resolved = fallback.interpreted
            resolverOutput = resolved
            request = resolved.request
            notes = resolved.diagnosticNotes
            source = resolved.source

            if request.expectedAnswerShape == .clarification || request.expectedAnswerShape == .unsupported {
                notes.append("Validation accepted explicit prompt target fallback terminal semantic shape.")
                let terminal = interpretedWith(
                    request: request,
                    interpreted: resolved,
                    source: source,
                    notes: notes,
                    clarificationChoices: resolved.clarificationChoices
                )
                return MarinaSemanticValidationTrace(
                    interpreted: terminal,
                    resolverOutput: resolverOutput,
                    candidateSearches: candidateSearches,
                    explicitPromptTargets: explicitTargets
                )
            }

            if let normalized = categoryExpenseListRequestIfNeeded(request) {
                request = normalized
                notes.append("Validation normalized explicit prompt target fallback category list semantics.")
            }
        }

        if shouldAttemptKnownFormulaRepair(source: source),
           let repaired = formulaRepair.repairedRequest(
            request,
            originalPrompt: originalPrompt,
            explicitPromptTargets: explicitTargets
           ) {
            request = repaired
            notes.append("Validation repaired known formula-backed concept semantic shape.")
            if source == .foundationModel {
                source = .repairedFoundationModel
            }
        }

        if shouldEnforcePromptTargetRetention(source: source),
           let targetLoss = targetLossRejection(for: request, explicitTargets: explicitTargets) {
            notes.append("Validation rejected semantic request because prompt target(s) were not retained: \(targetLoss.joined(separator: ", ")).")
            let rejected = interpretedWith(
                request: unsupported(.unresolvedEntity),
                interpreted: resolved,
                source: source,
                notes: notes,
                clarificationChoices: resolved.clarificationChoices
            )
            return MarinaSemanticValidationTrace(
                interpreted: rejected,
                resolverOutput: resolverOutput,
                candidateSearches: candidateSearches,
                explicitPromptTargets: explicitTargets
            )
        }

        guard capabilityRegistry.supports(entity: request.entity, operation: request.operation) else {
            request = unsupported(.unsupportedCombination)
            notes.append("Validation rejected unsupported entity/operation capability.")
            let rejected = interpretedWith(request: request, interpreted: resolved, source: source, notes: notes)
            return MarinaSemanticValidationTrace(
                interpreted: rejected,
                resolverOutput: resolverOutput,
                candidateSearches: candidateSearches,
                explicitPromptTargets: explicitTargets
            )
        }

        if let rejected = rejectedRequest(for: request, snapshot: snapshot) {
            notes.append("Validation rejected semantic request: \(rejected.unsupportedReason?.rawValue ?? rejected.expectedAnswerShape.rawValue).")
            let rejectedInterpreted = interpretedWith(request: rejected, interpreted: resolved, source: source, notes: notes)
            return MarinaSemanticValidationTrace(
                interpreted: rejectedInterpreted,
                resolverOutput: resolverOutput,
                candidateSearches: candidateSearches,
                explicitPromptTargets: explicitTargets
            )
        }

        notes.append("Validation accepted semantic request.")
        let accepted = interpretedWith(request: request, interpreted: resolved, source: source, notes: notes)
        return MarinaSemanticValidationTrace(
            interpreted: accepted,
            resolverOutput: resolverOutput,
            candidateSearches: candidateSearches,
            explicitPromptTargets: explicitTargets
        )
    }

    private func interpretedWith(
        request: MarinaSemanticRequest,
        interpreted: MarinaInterpretedSemanticRequest,
        source: MarinaSemanticSource,
        notes: [String],
        clarificationChoices: MarinaClarificationChoices? = nil
    ) -> MarinaInterpretedSemanticRequest {
        MarinaInterpretedSemanticRequest(
            request: request,
            confidence: interpreted.confidence,
            source: source,
            diagnosticNotes: notes,
            clarificationChoices: clarificationChoices ?? interpreted.clarificationChoices
        )
    }

    private func restoreExplicitCategoryTargetIfNeeded(
        _ request: MarinaSemanticRequest,
        originalRequest: MarinaSemanticRequest,
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaSemanticRequest? {
        guard originalRequest.dimensions.contains(.category),
              let originalTarget = originalRequest.targetName?.trimmingCharacters(in: .whitespacesAndNewlines),
              originalTarget.isEmpty == false,
              let categoryName = resolvedCategoryName(named: originalTarget, snapshot: snapshot),
              request.targetName != categoryName || request.dimensions.contains(.category) == false || request.textQuery != nil else {
            return nil
        }

        var restored = originalRequest
        restored.targetName = categoryName
        restored.targetDisplayName = originalRequest.targetDisplayName ?? categoryName
        restored.textQuery = nil
        restored.dimensions = unique(restored.dimensions + [.category])
        restored.unsupportedReason = nil
        return restored
    }

    private func resolvedCategoryName(
        named name: String,
        snapshot: MarinaWorkspaceSnapshot
    ) -> String? {
        let normalized = normalize(name)
        let exactMatches = snapshot.categories.filter { normalize($0.name) == normalized }
        if exactMatches.count == 1 {
            return exactMatches[0].name
        }

        let containingMatches = snapshot.categories.filter { normalize($0.name).contains(normalized) }
        return containingMatches.count == 1 ? containingMatches[0].name : nil
    }

    private func categoryExpenseListRequestIfNeeded(
        _ request: MarinaSemanticRequest
    ) -> MarinaSemanticRequest? {
        guard request.entity == .category,
              request.operation == .list,
              request.measure == .budgetImpact,
              request.expectedAnswerShape == .list,
              request.dimensions.contains(.category),
              let targetName = request.targetName?.trimmingCharacters(in: .whitespacesAndNewlines),
              targetName.isEmpty == false else {
            return nil
        }

        var normalized = request
        normalized.entity = .variableExpense
        normalized.operation = .list
        normalized.measure = .budgetImpact
        normalized.dimensions = [.category]
        normalized.targetName = targetName
        normalized.targetDisplayName = request.targetDisplayName ?? targetName
        normalized.textQuery = nil
        normalized.resultLimit = request.resultLimit
        normalized.sort = request.sort ?? .dateDescending
        normalized.expenseScope = .unified
        normalized.expectedAnswerShape = .list
        normalized.unsupportedReason = nil
        return normalized
    }

    private func repairMerchantSpendIfNeeded(
        _ request: MarinaSemanticRequest,
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaSemanticRequest? {
        guard request.operation == .sum,
              let targetName = request.targetName,
              merchantExists(targetName, snapshot: snapshot) else {
            return nil
        }

        if request.entity == .card,
           resolutionStatus(named: targetName, in: snapshot.cards, keyPath: \.name) == .missing {
            var repaired = request
            repaired.entity = .variableExpense
            repaired.dimensions = unique(repaired.dimensions.filter { $0 != .card } + [.merchantText])
            repaired.targetName = nil
            repaired.textQuery = request.textQuery ?? targetName
            repaired.expenseScope = .variable
            repaired.expectedAnswerShape = .metric
            return repaired
        }

        if (request.entity == .variableExpense || request.entity == .plannedExpense),
           request.dimensions.contains(.card) == false,
           request.textQuery == nil {
            var repaired = request
            repaired.dimensions = unique(repaired.dimensions + [.merchantText])
            repaired.targetName = nil
            repaired.textQuery = targetName
            repaired.expenseScope = request.entity == .plannedExpense ? .planned : .variable
            repaired.expectedAnswerShape = .metric
            return repaired
        }

        return nil
    }

    private func rejectedRequest(
        for request: MarinaSemanticRequest,
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaSemanticRequest? {
        switch request.entity {
        case .workspace:
            return nil
        case .budget:
            if request.dimensions.contains(.category), let targetName = request.targetName {
                return rejectedIfNeeded(resolutionStatus(named: targetName, in: snapshot.categories, keyPath: \.name))
            }
            return nil
        case .card:
            if request.operation == .count && request.targetName == nil && request.comparisonTargetName == nil {
                return nil
            }
            if let targetName = request.targetName,
               let rejected = rejectedIfNeeded(resolutionStatus(named: targetName, in: snapshot.cards, keyPath: \.name)) {
                return rejected
            }
            if let comparisonTargetName = request.comparisonTargetName,
               let rejected = rejectedIfNeeded(resolutionStatus(named: comparisonTargetName, in: snapshot.cards, keyPath: \.name)) {
                return rejected
            }
            return nil
        case .plannedExpense, .variableExpense:
            if request.dimensions.contains(.card), let targetName = request.targetName {
                return rejectedIfNeeded(resolutionStatus(named: targetName, in: snapshot.cards, keyPath: \.name))
            }
            return nil
        case .reconciliationAccount:
            guard let targetName = request.targetName else {
                return unsupported(.unresolvedEntity)
            }
            if let rejected = rejectedIfNeeded(resolutionStatus(named: targetName, in: snapshot.reconciliationAccounts, keyPath: \.name)) {
                return rejected
            }
            if request.dimensions.contains(.category), let categoryName = request.textQuery {
                return rejectedIfNeeded(resolutionStatus(named: categoryName, in: snapshot.categories, keyPath: \.name))
            }
            return nil
        case .savingsAccount:
            if let targetName = request.targetName {
                return rejectedIfNeeded(resolutionStatus(named: targetName, in: snapshot.savingsAccounts, keyPath: \.name))
            }
            return nil
        case .income:
            if let targetName = request.targetName {
                return rejectedIfNeeded(resolutionStatus(named: targetName, in: incomeSources(snapshot), keyPath: \.self))
            }
            return nil
        case .category:
            if request.operation == .group && request.targetName == nil && request.comparisonTargetName == nil {
                return nil
            }
            if let targetName = request.targetName,
               let rejected = rejectedIfNeeded(resolutionStatus(named: targetName, in: snapshot.categories, keyPath: \.name)) {
                return rejected
            }
            if let comparisonTargetName = request.comparisonTargetName,
               let rejected = rejectedIfNeeded(resolutionStatus(named: comparisonTargetName, in: snapshot.categories, keyPath: \.name)) {
                return rejected
            }
            return nil
        case .preset:
            if request.operation == .list || request.operation == .next || request.operation == .group {
                return nil
            }
            if let targetName = request.targetName {
                return rejectedIfNeeded(resolutionStatus(named: targetName, in: snapshot.presets, keyPath: \.title))
            }
            return nil
        }
    }

    private func rejectedIfNeeded(_ status: ResolutionStatus) -> MarinaSemanticRequest? {
        switch status {
        case .resolved:
            return nil
        case .missing:
            return unsupported(.unresolvedEntity)
        case .ambiguous:
            return clarification("Which matching record should Marina use?")
        }
    }

    private func unsupported(_ reason: MarinaSemanticUnsupportedReason) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .workspace,
            operation: .list,
            expectedAnswerShape: .unsupported,
            unsupportedReason: reason
        )
    }

    private func clarification(_ question: String) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .workspace,
            operation: .list,
            expectedAnswerShape: .clarification,
            clarificationQuestion: question,
            unsupportedReason: .ambiguousEntity
        )
    }

    private enum ResolutionStatus {
        case resolved
        case missing
        case ambiguous
    }

    private struct ExplicitPromptTargetSpan {
        let displayName: String
        let normalizedName: String
        let start: Int
        let end: Int
    }

    private func resolutionStatus<T>(
        named name: String,
        in values: [T],
        keyPath: KeyPath<T, String>
    ) -> ResolutionStatus {
        let normalized = normalize(name)
        let exactMatches = values.filter { normalize($0[keyPath: keyPath]) == normalized }
        if exactMatches.count > 1 {
            return .ambiguous
        }
        if exactMatches.count == 1 {
            return .resolved
        }
        return values.contains { normalize($0[keyPath: keyPath]).contains(normalized) } ? .resolved : .missing
    }

    private func merchantExists(_ text: String, snapshot: MarinaWorkspaceSnapshot) -> Bool {
        let normalized = normalize(text)
        return snapshot.variableExpenses.contains { normalize($0.descriptionText).contains(normalized) }
            || snapshot.plannedExpenses.contains { normalize($0.title).contains(normalized) }
    }

    private func incomeSources(_ snapshot: MarinaWorkspaceSnapshot) -> [String] {
        Array(Set(snapshot.incomes.map(\.source)))
    }

    private func explicitPromptTargets(
        in prompt: String?,
        snapshot: MarinaWorkspaceSnapshot
    ) -> [String] {
        guard let prompt, prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return []
        }

        let normalizedPrompt = targetNormalized(prompt)
        let names = snapshot.cards.map(\.name)
            + snapshot.categories.map(\.name)
            + snapshot.presets.map(\.title)
            + Array(Set(snapshot.incomes.map(\.source)))
            + snapshot.savingsAccounts.map(\.name)
            + snapshot.reconciliationAccounts.map(\.name)
            + snapshot.budgets.map(\.name)
            + snapshot.variableExpenses.map(\.descriptionText)
            + snapshot.plannedExpenses.map(\.title)

        var seenNames: Set<String> = []
        let candidates = names.flatMap { name -> [ExplicitPromptTargetSpan] in
            let normalizedName = targetNormalized(name)
            guard normalizedName.isEmpty == false,
                  seenNames.contains(normalizedName) == false else {
                return []
            }
            seenNames.insert(normalizedName)
            return targetSpans(
                displayName: name,
                normalizedName: normalizedName,
                normalizedPrompt: normalizedPrompt
            )
        }

        var accepted: [ExplicitPromptTargetSpan] = []
        for candidate in candidates.sorted(by: isBetterExplicitPromptTargetSpan) {
            guard accepted.contains(where: { spansOverlap(candidate, $0) }) == false else {
                continue
            }
            accepted.append(candidate)
        }

        return accepted
            .sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
            .map(\.displayName)
    }

    private func targetSpans(
        displayName: String,
        normalizedName: String,
        normalizedPrompt: String
    ) -> [ExplicitPromptTargetSpan] {
        var spans: [ExplicitPromptTargetSpan] = []
        var searchRange = normalizedPrompt.startIndex..<normalizedPrompt.endIndex

        while let range = normalizedPrompt.range(of: normalizedName, range: searchRange) {
            let start = normalizedPrompt.distance(from: normalizedPrompt.startIndex, to: range.lowerBound)
            let end = normalizedPrompt.distance(from: normalizedPrompt.startIndex, to: range.upperBound)
            spans.append(ExplicitPromptTargetSpan(
                displayName: displayName,
                normalizedName: normalizedName,
                start: start,
                end: end
            ))

            guard range.upperBound < normalizedPrompt.endIndex else {
                break
            }
            searchRange = range.upperBound..<normalizedPrompt.endIndex
        }

        return spans
    }

    private func isBetterExplicitPromptTargetSpan(
        _ left: ExplicitPromptTargetSpan,
        _ right: ExplicitPromptTargetSpan
    ) -> Bool {
        let leftLength = left.end - left.start
        let rightLength = right.end - right.start
        if leftLength != rightLength {
            return leftLength > rightLength
        }
        if left.start != right.start {
            return left.start < right.start
        }
        return left.normalizedName < right.normalizedName
    }

    private func spansOverlap(
        _ left: ExplicitPromptTargetSpan,
        _ right: ExplicitPromptTargetSpan
    ) -> Bool {
        left.start < right.end && right.start < left.end
    }

    private func targetLossRejection(
        for request: MarinaSemanticRequest,
        explicitTargets: [String]
    ) -> [String]? {
        guard explicitTargets.isEmpty == false,
              request.expectedAnswerShape != .clarification,
              request.expectedAnswerShape != .unsupported else {
            return nil
        }

        let retainedText = [
            request.targetName,
            request.comparisonTargetName,
            request.textQuery,
            request.targetDisplayName
        ]
        .compactMap { $0 }
        .map(targetNormalized)
        .joined(separator: " ")

        let missing = explicitTargets.filter { target in
            let normalizedTarget = targetNormalized(target)
            guard normalizedTarget.isEmpty == false else { return false }
            return retainedText.contains(normalizedTarget) == false
        }

        return missing.isEmpty ? nil : missing
    }

    private func shouldEnforcePromptTargetRetention(source: MarinaSemanticSource) -> Bool {
        source == .foundationModel || source == .repairedFoundationModel
    }

    private func shouldAttemptKnownFormulaRepair(source: MarinaSemanticSource) -> Bool {
        source == .foundationModel || source == .repairedFoundationModel
    }

    private func shouldAttemptExplicitPromptTargetFallback(
        source: MarinaSemanticSource,
        request: MarinaSemanticRequest,
        explicitTargets: [String]
    ) -> Bool {
        guard shouldEnforcePromptTargetRetention(source: source),
              explicitTargets.isEmpty == false,
              request.targetName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
              request.textQuery?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
              request.comparisonTargetName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else {
            return false
        }
        return true
    }

    private func hasClearCardComparisonIntent(
        in prompt: String?,
        request: MarinaSemanticRequest
    ) -> Bool {
        guard request.entity == .card || request.dimensions.contains(.card),
              let prompt,
              prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return false
        }

        let normalized = targetNormalized(prompt)
        let tokens = Set(normalized.split(separator: " ").map(String.init))
        if tokens.contains("compare")
            || tokens.contains("comparison")
            || tokens.contains("versus")
            || tokens.contains("vs")
            || tokens.contains("higher")
            || tokens.contains("lower") {
            return true
        }

        let comparisonPhrases = [
            "which card had more",
            "which card had less",
            "which had more",
            "which had less",
            "which was higher",
            "which was lower",
            "had more spend",
            "had less spend",
            "spent more",
            "spent less",
            "more spend",
            "less spend"
        ]
        return comparisonPhrases.contains { normalized.contains($0) }
    }

    private func unique(_ dimensions: [MarinaSemanticDimension]) -> [MarinaSemanticDimension] {
        var result: [MarinaSemanticDimension] = []
        for dimension in dimensions where result.contains(dimension) == false {
            result.append(dimension)
        }
        return result
    }

    private func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .uppercased()
    }

    private func targetNormalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "’", with: "'")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[^A-Za-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }
}

struct MarinaSemanticFormulaRepair {
    func repairedRequest(
        _ request: MarinaSemanticRequest,
        originalPrompt: String?,
        explicitPromptTargets: [String]
    ) -> MarinaSemanticRequest? {
        guard let prompt = originalPrompt,
              hasConcreteTarget(in: request) == false,
              explicitPromptTargets.isEmpty,
              isWhatIf(prompt, request: request) == false,
              let concept = concept(in: prompt),
              shouldRepair(request, for: concept) else {
            return nil
        }

        var repaired = request
        repaired.entity = concept.entity
        repaired.operation = concept.operation
        repaired.measure = concept.measure
        repaired.dimensions = concept.dimensions
        repaired.targetName = nil
        repaired.comparisonTargetName = nil
        repaired.textQuery = nil
        repaired.targetDisplayName = nil
        repaired.resultLimit = nil
        repaired.sort = nil
        repaired.expenseScope = concept.expenseScope
        repaired.incomeState = nil
        repaired.whatIfAmount = nil
        repaired.categoryAvailabilityFilter = nil
        repaired.expectedAnswerShape = concept.answerShape
        repaired.clarificationQuestion = nil
        repaired.unsupportedReason = nil
        return repaired
    }

    private func hasConcreteTarget(in request: MarinaSemanticRequest) -> Bool {
        trimmed(request.targetName).isEmpty == false
            || trimmed(request.comparisonTargetName).isEmpty == false
            || trimmed(request.textQuery).isEmpty == false
    }

    private func shouldRepair(
        _ request: MarinaSemanticRequest,
        for concept: Concept
    ) -> Bool {
        if request.entity == concept.entity,
           request.operation == concept.operation,
           request.measure == concept.measure,
           request.expectedAnswerShape == concept.answerShape {
            return false
        }

        return true
    }

    private func concept(in prompt: String) -> Concept? {
        let normalized = normalize(prompt)

        if containsAny(normalized, [
            "safe spend",
            "what can i spend today",
            "safe daily spend",
            "safe per day",
            "daily allowance",
            "what can i spend per day"
        ]) {
            return .safeSpend
        }

        if containsAny(normalized, [
            "room left",
            "left in my budget",
            "remaining room",
            "how much room"
        ]) {
            return .remainingRoom
        }

        if containsAny(normalized, [
            "projected spend",
            "where will i end up",
            "on track to spend"
        ]) {
            return .projectedSpend
        }

        if containsAny(normalized, [
            "spending too fast",
            "am i on track",
            "ahead or behind",
            "pace"
        ]) {
            return .pace
        }

        if containsAny(normalized, [
            "eating my budget",
            "biggest share",
            "taking the biggest share",
            "biggest spending categories",
            "top spending categories"
        ]) {
            return .categoryConcentration
        }

        return nil
    }

    private func isWhatIf(_ prompt: String, request: MarinaSemanticRequest) -> Bool {
        guard request.operation != .whatIf,
              request.whatIfAmount == nil else {
            return true
        }

        let normalized = normalize(prompt)
        return normalized.contains("what if")
            || normalized.contains("if i ")
            || normalized.contains("if we ")
            || normalized.contains("happens if")
    }

    private func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains { value.contains($0) }
    }

    private func trimmed(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "’", with: "'")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[^A-Za-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }

    private enum Concept {
        case safeSpend
        case remainingRoom
        case projectedSpend
        case pace
        case categoryConcentration

        var entity: MarinaSemanticEntity {
            switch self {
            case .safeSpend, .remainingRoom, .projectedSpend, .pace:
                return .budget
            case .categoryConcentration:
                return .category
            }
        }

        var operation: MarinaSemanticOperation {
            switch self {
            case .safeSpend, .remainingRoom, .projectedSpend:
                return .forecast
            case .pace:
                return .compare
            case .categoryConcentration:
                return .share
            }
        }

        var measure: MarinaSemanticMeasure {
            switch self {
            case .safeSpend:
                return .safeDailySpend
            case .remainingRoom:
                return .remainingRoom
            case .projectedSpend:
                return .projectedSpend
            case .pace:
                return .paceDifference
            case .categoryConcentration:
                return .concentration
            }
        }

        var dimensions: [MarinaSemanticDimension] {
            switch self {
            case .safeSpend, .remainingRoom, .projectedSpend, .pace:
                return []
            case .categoryConcentration:
                return [.category]
            }
        }

        var expenseScope: MarinaSemanticExpenseScope? {
            switch self {
            case .safeSpend, .remainingRoom, .projectedSpend, .pace:
                return nil
            case .categoryConcentration:
                return nil
            }
        }

        var answerShape: MarinaSemanticAnswerShape {
            switch self {
            case .safeSpend, .remainingRoom, .projectedSpend, .categoryConcentration:
                return .metric
            case .pace:
                return .comparison
            }
        }
    }
}
