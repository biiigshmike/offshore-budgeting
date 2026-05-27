import Foundation

struct MarinaSemanticCandidateResolver {
    func resolve(
        interpreted: MarinaInterpretedSemanticRequest,
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaInterpretedSemanticRequest {
        var request = interpreted.request
        var notes = interpreted.diagnosticNotes

        guard request.expectedAnswerShape != .clarification,
              request.expectedAnswerShape != .unsupported,
              let target = targetText(from: request),
              target.isEmpty == false else {
            return interpreted
        }

        if let repaired = repairExplicitTarget(request, target: target, snapshot: snapshot) {
            notes.append("Candidate resolver normalized explicit target \"\(target)\".")
            return interpretedWith(
                request: repaired,
                interpreted: interpreted,
                notes: notes,
                choices: interpreted.clarificationChoices
            )
        }

        guard shouldResolveUntypedTarget(request) else {
            return interpreted
        }

        let candidates = candidateChoices(for: target, baseRequest: request, snapshot: snapshot)
        if candidates.count > 1 {
            request = clarificationRequest(
                question: "What should Marina use for \"\(target)\"?",
                target: target,
                dateRangeToken: request.dateRangeToken
            )
            notes.append("Candidate resolver found \(candidates.count) possible meanings for \"\(target)\".")
            let choices = MarinaClarificationChoices(
                question: "What should Marina use for \"\(target)\"?",
                choices: candidates
            )
            return interpretedWith(request: request, interpreted: interpreted, notes: notes, choices: choices)
        }

        if let candidate = candidates.first {
            notes.append("Candidate resolver selected \(candidate.title) for \"\(target)\".")
            return interpretedWith(
                request: candidate.request,
                interpreted: interpreted,
                notes: notes,
                choices: interpreted.clarificationChoices
            )
        }

        return interpreted
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

    private func candidateChoices(
        for target: String,
        baseRequest: MarinaSemanticRequest,
        snapshot: MarinaWorkspaceSnapshot
    ) -> [MarinaClarificationChoice] {
        var choices: [MarinaClarificationChoice] = []

        for category in matchingCategories(target, snapshot: snapshot) {
            choices.append(
                MarinaClarificationChoice(
                    title: "\(category.name) Category",
                    subtitle: "Use the \(category.name) category.",
                    aliases: aliases(for: category.name) + ["category"],
                    request: categoryRequest(categoryName: category.name, baseRequest: baseRequest)
                )
            )
        }

        if shouldOfferExpenseText(for: target, baseRequest: baseRequest, snapshot: snapshot) {
            choices.append(
                MarinaClarificationChoice(
                    title: "\(displayTarget(target)) Text",
                    subtitle: "Search expense titles and descriptions for \(displayTarget(target)).",
                    aliases: aliases(for: target) + ["merchant", "store", "vendor", "text", "title", "description", "expense"],
                    request: expenseTextRequest(textQuery: target, baseRequest: baseRequest)
                )
            )
        }

        for card in matchingCards(target, snapshot: snapshot) {
            choices.append(
                MarinaClarificationChoice(
                    title: card.name,
                    subtitle: "Use \(card.name) as the card.",
                    aliases: aliases(for: card.name) + ["card"],
                    request: cardRequest(cardName: card.name, baseRequest: baseRequest)
                )
            )
        }

        return deduped(choices)
    }

    private func repairExplicitTarget(
        _ request: MarinaSemanticRequest,
        target: String,
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaSemanticRequest? {
        var repaired = request

        if request.dimensions.contains(.category) || request.entity == .category {
            guard let category = matchingCategories(target, snapshot: snapshot).first else { return nil }
            repaired.targetName = category.name
            if request.entity == .reconciliationAccount {
                repaired.textQuery = category.name
            }
            return repaired
        }

        if request.dimensions.contains(.card) || request.entity == .card {
            guard let card = matchingCards(target, snapshot: snapshot).first else { return nil }
            repaired.targetName = card.name
            return repaired
        }

        if request.dimensions.contains(.incomeSource) || request.entity == .income {
            guard let source = matchingIncomeSources(target, snapshot: snapshot).first else { return nil }
            repaired.targetName = source
            return repaired
        }

        if request.dimensions.contains(.preset) || request.entity == .preset {
            guard let preset = matchingPresets(target, snapshot: snapshot).first else { return nil }
            repaired.targetName = preset.title
            return repaired
        }

        if request.dimensions.contains(.savingsAccount) || request.entity == .savingsAccount {
            guard let account = matchingSavingsAccounts(target, snapshot: snapshot).first else { return nil }
            repaired.targetName = account.name
            return repaired
        }

        if request.dimensions.contains(.reconciliationAccount) || request.entity == .reconciliationAccount {
            guard let account = matchingReconciliationAccounts(target, snapshot: snapshot).first else { return nil }
            repaired.targetName = account.name
            return repaired
        }

        if request.dimensions.contains(.budget) || request.entity == .budget {
            guard let budget = matchingBudgets(target, snapshot: snapshot).first else { return nil }
            repaired.targetName = budget.name
            return repaired
        }

        return nil
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
            expenseScope: .unified,
            expectedAnswerShape: .metric
        )
    }

    private func expenseTextRequest(textQuery: String, baseRequest: MarinaSemanticRequest) -> MarinaSemanticRequest {
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
            expenseScope: .unified,
            expectedAnswerShape: .metric
        )
    }

    private func shouldOfferExpenseText(
        for target: String,
        baseRequest: MarinaSemanticRequest,
        snapshot: MarinaWorkspaceSnapshot
    ) -> Bool {
        if baseRequest.entity == .variableExpense || baseRequest.entity == .plannedExpense {
            return true
        }
        return expenseTextExists(target, snapshot: snapshot)
    }

    private func targetText(from request: MarinaSemanticRequest) -> String? {
        request.targetName ?? request.textQuery
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

    private func matchingCards(_ target: String, snapshot: MarinaWorkspaceSnapshot) -> [Card] {
        snapshot.cards.filter { matches($0.name, target: target) }
    }

    private func matchingCategories(_ target: String, snapshot: MarinaWorkspaceSnapshot) -> [Category] {
        snapshot.categories.filter { matches($0.name, target: target) }
    }

    private func matchingPresets(_ target: String, snapshot: MarinaWorkspaceSnapshot) -> [Preset] {
        snapshot.presets.filter { matches($0.title, target: target) }
    }

    private func matchingBudgets(_ target: String, snapshot: MarinaWorkspaceSnapshot) -> [Budget] {
        snapshot.budgets.filter { matches($0.name, target: target) }
    }

    private func matchingSavingsAccounts(_ target: String, snapshot: MarinaWorkspaceSnapshot) -> [SavingsAccount] {
        snapshot.savingsAccounts.filter { matches($0.name, target: target) }
    }

    private func matchingReconciliationAccounts(_ target: String, snapshot: MarinaWorkspaceSnapshot) -> [AllocationAccount] {
        snapshot.reconciliationAccounts.filter { matches($0.name, target: target) }
    }

    private func matchingIncomeSources(_ target: String, snapshot: MarinaWorkspaceSnapshot) -> [String] {
        Array(Set(snapshot.incomes.map(\.source))).filter { matches($0, target: target) }
    }

    private func expenseTextExists(_ target: String, snapshot: MarinaWorkspaceSnapshot) -> Bool {
        snapshot.variableExpenses.contains { matches($0.descriptionText, target: target) }
            || snapshot.plannedExpenses.contains { matches($0.title, target: target) }
    }

    private func matches(_ candidate: String, target: String) -> Bool {
        let candidate = canonical(candidate)
        let target = canonical(target)
        return candidate == target || candidate.contains(target) || target.contains(candidate)
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

    private func deduped(_ choices: [MarinaClarificationChoice]) -> [MarinaClarificationChoice] {
        var seen: Set<String> = []
        var result: [MarinaClarificationChoice] = []
        for choice in choices {
            let key = canonical(choice.title)
            guard seen.contains(key) == false else { continue }
            seen.insert(key)
            result.append(choice)
        }
        return result
    }
}
