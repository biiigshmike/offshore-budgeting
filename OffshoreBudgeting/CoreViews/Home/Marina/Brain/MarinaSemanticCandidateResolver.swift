import Foundation

struct MarinaSemanticCandidateResolver {
    private struct ExpenseTextCandidate {
        let title: String
        let kindLabel: String
    }

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
                question: MarinaL10n.format("marina.clarification.targetMeaningFormat", defaultValue: "What should Marina use for \"%@\"?", comment: "Clarification question for resolving an ambiguous target.", target),
                target: target,
                dateRangeToken: request.dateRangeToken
            )
            notes.append("Candidate resolver found \(candidates.count) possible meanings for \"\(target)\".")
            let choices = MarinaClarificationChoices(
                question: MarinaL10n.format("marina.clarification.targetMeaningFormat", defaultValue: "What should Marina use for \"%@\"?", comment: "Clarification question for resolving an ambiguous target.", target),
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

        notes.append("Candidate resolver found no valid meanings for \"\(target)\".")
        return interpretedWith(
            request: unsupportedRequest(.unresolvedEntity),
            interpreted: interpreted,
            notes: notes,
            choices: interpreted.clarificationChoices
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
                    title: category.name,
                    kindLabel: MarinaL10n.common("category", defaultValue: "Category", comment: "Common label for category."),
                    subtitle: MarinaL10n.format("marina.clarification.useCategoryFormat", defaultValue: "Use the %@ category.", comment: "Clarification choice subtitle for using a category.", category.name),
                    aliases: aliases(for: category.name) + ["category"],
                    request: categoryRequest(categoryName: category.name, baseRequest: baseRequest)
                )
            )
        }

        for incomeSource in matchingIncomeSources(target, snapshot: snapshot) {
            choices.append(
                MarinaClarificationChoice(
                    title: incomeSource,
                    kindLabel: MarinaL10n.string("marina.clarification.kind.incomeSource", defaultValue: "Income source", comment: "Kind label for an income source clarification choice."),
                    subtitle: MarinaL10n.format("marina.clarification.useIncomeSourceFormat", defaultValue: "Use %@ as the income source.", comment: "Clarification choice subtitle for using an income source.", incomeSource),
                    aliases: aliases(for: incomeSource) + ["income", "income source"],
                    request: incomeSourceRequest(source: incomeSource, baseRequest: baseRequest)
                )
            )
        }

        choices.append(contentsOf: expenseTextChoices(for: target, baseRequest: baseRequest, snapshot: snapshot))

        for card in matchingCards(target, snapshot: snapshot) {
            choices.append(
                MarinaClarificationChoice(
                    title: card.name,
                    kindLabel: MarinaL10n.common("card", defaultValue: "Card", comment: "Common label for card."),
                    subtitle: MarinaL10n.format("marina.clarification.useAsCardFormat", defaultValue: "Use %@ as the card.", comment: "Clarification choice subtitle for using a card.", card.name),
                    aliases: aliases(for: card.name) + ["card"],
                    request: cardRequest(cardName: card.name, baseRequest: baseRequest)
                )
            )
        }

        for budget in matchingBudgets(target, snapshot: snapshot) {
            choices.append(
                MarinaClarificationChoice(
                    title: budget.name,
                    kindLabel: MarinaL10n.common("budget", defaultValue: "Budget", comment: "Common label for budget."),
                    subtitle: MarinaL10n.format("marina.clarification.useBudgetFormat", defaultValue: "Use the %@ budget.", comment: "Clarification choice subtitle for using a budget.", budget.name),
                    aliases: aliases(for: budget.name) + ["budget"],
                    request: budgetRequest(budgetName: budget.name, baseRequest: baseRequest)
                )
            )
        }

        for preset in matchingPresets(target, snapshot: snapshot) {
            choices.append(
                MarinaClarificationChoice(
                    title: preset.title,
                    kindLabel: MarinaL10n.common("preset", defaultValue: "Preset", comment: "Common label for preset."),
                    subtitle: MarinaL10n.format("marina.clarification.usePresetFormat", defaultValue: "Use the %@ preset.", comment: "Clarification choice subtitle for using a preset.", preset.title),
                    aliases: aliases(for: preset.title) + ["preset"],
                    request: presetRequest(presetName: preset.title, baseRequest: baseRequest)
                )
            )
        }

        for account in matchingSavingsAccounts(target, snapshot: snapshot) {
            choices.append(
                MarinaClarificationChoice(
                    title: account.name,
                    kindLabel: MarinaL10n.string("marina.clarification.kind.savingsAccount", defaultValue: "Savings account", comment: "Kind label for savings account clarification choice."),
                    subtitle: MarinaL10n.format("marina.clarification.useSavingsAccountFormat", defaultValue: "Use %@ as the savings account.", comment: "Clarification choice subtitle for using a savings account.", account.name),
                    aliases: aliases(for: account.name) + ["savings", "savings account"],
                    request: savingsAccountRequest(accountName: account.name, baseRequest: baseRequest)
                )
            )
        }

        for account in matchingReconciliationAccounts(target, snapshot: snapshot) {
            choices.append(
                MarinaClarificationChoice(
                    title: account.name,
                    kindLabel: MarinaL10n.string("marina.clarification.kind.reconciliationAccount", defaultValue: "Reconciliation account", comment: "Kind label for reconciliation account clarification choice."),
                    subtitle: MarinaL10n.format("marina.clarification.useReconciliationAccountFormat", defaultValue: "Use %@ as the reconciliation account.", comment: "Clarification choice subtitle for using a reconciliation account.", account.name),
                    aliases: aliases(for: account.name) + ["balance", "reconciliation", "shared balance"],
                    request: reconciliationAccountRequest(accountName: account.name, baseRequest: baseRequest)
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

    private func expenseTextChoices(
        for target: String,
        baseRequest: MarinaSemanticRequest,
        snapshot: MarinaWorkspaceSnapshot
    ) -> [MarinaClarificationChoice] {
        let candidates = matchingExpenseTextCandidates(target, snapshot: snapshot)
        guard candidates.isEmpty == false else { return [] }

        let maxSpecificChoices = 3
        let genericAliases = ["merchant", "store", "vendor", "expense", "expenses", "title", "description", "search"]
        var choices = candidates.prefix(maxSpecificChoices).map { candidate in
            let aliases = aliases(for: candidate.title) + (candidates.count == 1 ? genericAliases : ["expense match"])
            return MarinaClarificationChoice(
                title: candidate.title,
                kindLabel: candidate.kindLabel,
                subtitle: MarinaL10n.format("marina.clarification.searchExpenseTextFormat", defaultValue: "Search expense titles and descriptions for %@.", comment: "Clarification choice subtitle for searching expense text.", candidate.title),
                aliases: aliases,
                request: expenseTextRequest(
                    textQuery: candidate.title,
                    displayName: candidate.title,
                    baseRequest: baseRequest
                )
            )
        }

        if candidates.count > 1 {
            let displayName = MarinaL10n.format("marina.clarification.allExpenseMatchesFormat", defaultValue: "All expense matches for \"%@\"", comment: "Clarification choice title for all expense matches.", displayTarget(target))
            choices.append(
                MarinaClarificationChoice(
                    title: displayName,
                    kindLabel: MarinaL10n.string("marina.clarification.kind.expenseSearch", defaultValue: "Expense search", comment: "Kind label for expense search."),
                    subtitle: MarinaL10n.format("marina.clarification.searchEveryExpenseTextFormat", defaultValue: "Search every expense title and description matching %@.", comment: "Clarification choice subtitle for searching every matching expense title and description.", displayTarget(target)),
                    aliases: aliases(for: target) + genericAliases,
                    request: expenseTextRequest(
                        textQuery: target,
                        displayName: displayName,
                        baseRequest: baseRequest
                    )
                )
            )
        }

        return choices
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

    private func unsupportedRequest(_ reason: MarinaSemanticUnsupportedReason) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .workspace,
            operation: .list,
            expectedAnswerShape: .unsupported,
            unsupportedReason: reason
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
        Array(Set(snapshot.incomes.map(\.source)))
            .filter { matches($0, target: target) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func matchingExpenseTextCandidates(
        _ target: String,
        snapshot: MarinaWorkspaceSnapshot
    ) -> [ExpenseTextCandidate] {
        var candidates: [ExpenseTextCandidate] = []
        var seen: Set<String> = []

        func append(_ title: String, kindLabel: String) {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false, matches(trimmed, target: target) else { return }
            let key = canonical(trimmed)
            guard seen.contains(key) == false else { return }
            seen.insert(key)
            candidates.append(ExpenseTextCandidate(title: trimmed, kindLabel: kindLabel))
        }

        for expense in snapshot.variableExpenses {
            append(expense.descriptionText, kindLabel: MarinaL10n.string("marina.clarification.kind.expenseMatch", defaultValue: "Expense match", comment: "Kind label for a matching expense."))
        }
        for expense in snapshot.plannedExpenses {
            append(expense.title, kindLabel: MarinaL10n.string("marina.clarification.kind.plannedExpenseMatch", defaultValue: "Planned expense match", comment: "Kind label for a matching planned expense."))
        }

        return candidates.sorted { left, right in
            let leftRank = matchRank(left.title, target: target)
            let rightRank = matchRank(right.title, target: target)
            if leftRank != rightRank { return leftRank < rightRank }
            return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
        }
    }

    private func matches(_ candidate: String, target: String) -> Bool {
        let candidate = canonical(candidate)
        let target = canonical(target)
        return candidate == target || candidate.contains(target) || target.contains(candidate)
    }

    private func matchRank(_ candidate: String, target: String) -> Int {
        let candidate = canonical(candidate)
        let target = canonical(target)
        if candidate == target { return 0 }
        if candidate.hasPrefix(target) { return 1 }
        if candidate.contains(target) { return 2 }
        if target.contains(candidate) { return 3 }
        return 4
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
            let key = "\(canonical(choice.title))|\(choice.kindLabel ?? "")"
            guard seen.contains(key) == false else { continue }
            seen.insert(key)
            result.append(choice)
        }
        return result
    }
}
