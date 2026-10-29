import Foundation

/// A conversational fallback from the same validated facts as the visual. A generated
/// explanation may replace this only after its evidence references have been validated.
enum MarinaVerifiedNarration {
    static func text(request: MarinaDataRequest, result: MarinaDataResult) -> String? {
        if ["needsPeriodChoice", "needsBudgetChoice"].contains(result.status) {
            let names = result.records.prefix(5).map { "“\($0.title)”" }.joined(separator: ", ")
            return names.isEmpty ? "Which budget would you like me to use?"
                : "There’s more than one budget that could apply: \(names). Which one should I use?"
        }
        if request.tool == .findRecords, result.status == "empty", let name = request.search {
            return "I couldn’t find “\(name)” in this workspace. Please specify the name and type."
        }
        if request.tool == .findRecords, result.status == "candidates" {
            let candidates = result.records.prefix(5).map { record in
                let kind: String
                switch record.kind {
                case "incomeSource": kind = "income source"
                case "savingsAccount": kind = "savings account"
                case "reconciliationAccount": kind = "reconciliation account"
                default: kind = record.kind
                }
                return "“\(record.title)” (\(kind))"
            }
            guard !candidates.isEmpty else { return nil }
            let more = result.totalCount > candidates.count ? " There are more matches; please specify the name and type." : ""
            return "Which did you mean: \(candidates.joined(separator: ", "))?\(more)"
        }
        guard request.tool != .findRecords, ["success", "empty"].contains(result.status) else { return nil }
        let scope = result.presentation?.scopeLabel ?? result.scope
        func metric(_ label: String) -> MarinaDataResult.Metric? { result.metrics.first { $0.label == label } }
        func value(_ label: String) -> String? { metric(label)?.formatted }
        let qualifier = result.presentation?.qualifier.flatMap { $0.isEmpty ? nil : $0 }
        func qualified(_ text: String) -> String { qualifier.map { text + " " + $0 } ?? text }

        if request.tool == .accounts {
            if request.accountID != nil,
               let balance = result.metrics.first(where: { $0.label.hasSuffix("current balance") || $0.label.hasSuffix("current reconciliation balance") }) {
                let label = balance.label.replacingOccurrences(of: " current reconciliation balance", with: "")
                    .replacingOccurrences(of: " current balance", with: "")
                var text: String
                if balance.label.hasSuffix("current reconciliation balance") {
                    let amount = CurrencyFormatter.string(from: abs(balance.value))
                    text = balance.value > 0 ? "\(label) owes you \(amount)."
                        : balance.value < 0 ? "You owe \(label) \(amount)." : "Your balance with \(label) is settled."
                } else { text = "Your current balance in \(label) is \(balance.formatted)." }
                if let count = value("Selected period activity count"), let activity = value("Selected period activity total") {
                    text += " For \(scope), there are \(count) entries with a net change of \(activity)."
                }
                return text
            }
            let kind = request.scope == .savings ? "savings" : request.scope == .reconciliation ? "reconciliation" : "savings and reconciliation"
            return "Here are your \(result.totalCount) \(kind) accounts and their current balances. Dates filter the activity, while balances include all ledger history."
        }
        if request.purpose == .nextPlannedExpense, result.records.isEmpty {
            return "There aren’t any planned expenses coming up in \(scope)."
        }
        if let focus = MarinaNarrationEvidence.standaloneMetricFocus(request: request, result: result) {
            let facts = MarinaNarrationEvidence.facts(request: request, result: result, prefix: "fallback")
            if metric(focus.metricLabel) == nil {
                let verb = [MarinaDataRequest.MetricFocus.actualSavings, .projectedSavings].contains(focus) ? "aren’t" : "isn’t"
                return "\(focus.metricLabel) \(verb) available for \(scope)."
            }
            if let first = facts.first {
                let subject: String
                switch focus {
                case .count:
                    let noun = request.purpose == .categoryAvailability ? "matching categories"
                        : request.purpose == .budgetCards ? "linked cards" : request.purpose == .budgetPresets ? "linked presets" : "matching records"
                    subject = "There are \(first.value) \(noun) for \(scope)."
                case .average: subject = "The average per matching record is \(first.value) for \(scope)."
                case .share: subject = "That makes up \(first.value) of the total for \(scope)."
                default: subject = "\(first.subject) \(first.relation) \(first.value) for \(scope)."
                }
                return qualified(subject)
            }
        }
        if request.purpose == .categoryAvailability, let categories = result.report?.categories {
            if categories.isEmpty { return "No categories match that availability status for \(scope)." }
            let budget = result.report?.budgetName.map { " in \($0)" } ?? ""
            let lines = categories.prefix(3).map { category -> String in
                let spent = CurrencyFormatter.string(from: category.planned + category.variable)
                guard let maximum = category.maximum, let available = category.available else {
                    return "\(category.name) has no maximum limit and \(spent) in spending."
                }
                let amount = CurrencyFormatter.string(from: abs(available))
                let limit = CurrencyFormatter.string(from: maximum)
                let text = available < 0 ? "\(category.name) is \(amount) over its \(limit) limit."
                    : "\(category.name) has \(amount) left of its \(limit) limit."
                return text + (category.minimum.map { " Its minimum goal is \(CurrencyFormatter.string(from: $0))." } ?? "")
            }
            let counts = [value("Categories over limit").map { "\($0) over their limit" },
                          value("Categories near limit").map { "\($0) nearing their limit" }].compactMap { $0 }
            let overview = counts.isEmpty ? "" : "There are " + counts.joined(separator: " and ") + ". "
            return "Here’s category availability for \(scope)\(budget). " + overview + lines.joined(separator: " ")
        }
        if let leaders = result.report?.leaders, !leaders.isEmpty {
            let sentences = leaders.prefix(2).map { leader -> String in
                guard let name = leader.title, let amount = leader.amount else { return "There are no matching expenses for \(leader.scope)." }
                return "\(name) \(leader.tiedCount > 1 ? "is tied for the top" : "is the top") \(request.grouping.rawValue) for \(leader.scope) at \(CurrencyFormatter.string(from: amount))."
            }
            let comparable = leaders.prefix(2).count == 2 && leaders.prefix(2).allSatisfy { $0.amount != nil }
            return qualified(sentences.joined(separator: " ") + (comparable ? comparisonDifference(result) : ""))
        }
        if request.operation == .comparison || result.presentation?.operation == .comparison {
            guard let first = value("Total"), let second = value("Comparison total") else { return nil }
            let compared = result.presentation?.chartPoints.last?.label ?? "the compared period"
            return qualified("The total for \(scope) is \(first), compared with \(second) for \(compared)." + comparisonDifference(result))
        }
        if [.ranking, .share].contains(request.operation), let row = result.records.first, let amount = row.amount {
            let direction = request.sort == .smallest ? "lowest" : "highest"
            let leading = (metric("Tied leading groups")?.value ?? 1) > 1 ? "is tied for the" : "has the"
            var text = request.offset > 0
                ? "\(row.title) totals \(CurrencyFormatter.string(from: amount)) for \(scope)."
                : "\(row.title) \(leading) \(direction) \(request.grouping.rawValue) total for \(scope) at \(CurrencyFormatter.string(from: amount))."
            if let share = result.report?.groups?.first?.sharePercent {
                text += " That’s \((share / 100).formatted(.percent.precision(.fractionLength(0...1)))) of the total."
            }
            return qualified(text)
        }
        if request.operation == .transactions, request.limit == 1, [.largest, .smallest].contains(request.sort),
           let row = result.records.first, let amount = row.amount {
            if request.offset > 0 {
                return qualified("\(row.title) is an expense of \(CurrencyFormatter.string(from: amount)) for \(scope).")
            }
            let tied = (metric("Tied expenses")?.value ?? 1) > 1
            return qualified("\(row.title) is \(tied ? "tied for " : "")your \(request.sort == .largest ? "highest" : "lowest") expense for \(scope) at \(CurrencyFormatter.string(from: amount)).")
        }
        if request.purpose == .cardSummary, let total = value("Total") {
            var text = "Your card spending for \(scope) totals \(total)."
            if let planned = value("Planned card spending"), let variable = value("Variable card spending") {
                text += " That’s \(planned) in planned expenses and \(variable) in variable expenses."
            }
            return qualified(text)
        }
        if request.purpose == .incomeProgress || request.purpose == .incomeTimeline,
           let actual = value("Actual income"), let planned = value("Planned income") {
            var text = "You’ve received \(actual) against \(planned) in planned income for \(scope)."
            if let percent = value("Income progress percent") { text += " That’s \(percent) of the planned amount." }
            return text
        }
        if request.purpose == .savingsOutlook || request.purpose == .savingsTimeline,
           let actual = value("Actual savings"), let projected = value("Projected savings") {
            var text = "Your actual savings for \(scope) are \(actual), against a projection of \(projected)."
            if let progress = value("Savings progress percent") {
                text += " You’re at \(progress) \(result.report?.progressMode == "breakEven" ? "of the way to break-even" : "of the projection")."
            }
            return text
        }
        if request.purpose == .budgetPace,
           let actual = value("Pace actual spending"), let expected = value("Expected spending by now") {
            return qualified("Your spending so far for \(scope) is \(actual), compared with \(expected) expected by now.")
        }
        let facts = MarinaNarrationEvidence.facts(request: request, result: result, prefix: "fallback")
        if request.purpose == .spendingPatterns || request.purpose == .budgetDetails || request.purpose == .nextPlannedExpense
            || (request.operation == .transactions && result.records.count == 1 && result.report?.transactions?.isEmpty == false) {
            return qualified(facts.prefix(request.purpose == .budgetDetails ? 6 : 4).enumerated().map { index, fact in
                index == 0 ? fact.statement : "\(fact.subject) \(fact.relation) \(fact.value)."
            }.joined(separator: " "))
        }
        if request.purpose == .budgetCards || request.purpose == .budgetPresets {
            let kind = request.purpose == .budgetCards ? "cards" : "presets"
            let names = result.records.prefix(5).map(\.title).joined(separator: ", ")
            return "There are \(result.totalCount) linked \(kind) for \(scope)." + (names.isEmpty ? "" : " \(names).")
        }
        if request.tool == .budgetSummary {
            if let extra = value("Hypothetical additional spending"), let projected = value("Projected savings after hypothetical spending") {
                return "With another \(extra) in spending, projected savings for \(scope) would be \(projected)."
            }
            if let room = value("Remaining room"), let safe = value("Safe spend today"), let projected = value("Projected savings") {
                return "You have \(room) of room left for \(scope), with \(safe) safe to spend today. Projected savings are \(projected)."
            }
        }
        if let total = value("Total") {
            let subject = request.tool == .income ? "Your income" : "Your spending"
            return qualified("\(subject) for \(scope) totals \(total).")
        }
        return "There are \(result.totalCount) matching records for \(scope)."
    }

    private static func comparisonDifference(_ result: MarinaDataResult) -> String {
        guard let difference = result.metrics.first(where: { $0.label == "Difference" }) else { return "" }
        if difference.value == 0 { return " The amounts are the same." }
        let percent = result.metrics.first(where: { $0.label == "Change percent" }).map { " (\((abs($0.value) / 100).formatted(.percent.precision(.fractionLength(0...1)))))" } ?? ""
        return " That’s \(CurrencyFormatter.string(from: abs(difference.value))) \(difference.value > 0 ? "higher" : "lower")\(percent)."
    }

}
