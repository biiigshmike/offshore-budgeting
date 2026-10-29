import Foundation

/// A small set of authoritative propositions, not a second financial calculator.
/// Subjects, direction, values and scope are inseparable when narrated by the model.
struct MarinaNarrationEvidence: Codable, Equatable, Sendable {
    var id: String
    var subject: String
    var relation: String
    var value: String
    var scope: String
    /// Required answer facts in the primary result; the first is the leading answer.
    var isFocus: Bool

    var statement: String { "\(subject) \(relation) \(value) for \(scope)." }

    /// A total describes the amount within a ranking, extreme or comparison; it
    /// must not replace that operation's answer with the full population total.
    /// Other explicit metrics, such as count and average, remain standalone answers.
    static func standaloneMetricFocus(request: MarinaDataRequest, result: MarinaDataResult) -> MarinaDataRequest.MetricFocus? {
        guard request.metric == .total else { return request.metric }
        let comparesAmounts = request.operation == .comparison || result.presentation?.operation == .comparison
            || result.report?.leaders?.isEmpty == false
        let ranksAmounts = [.ranking, .share].contains(request.operation)
        let selectsExtreme = request.operation == .transactions && request.limit == 1
            && [.largest, .smallest].contains(request.sort)
        return comparesAmounts || ranksAmounts || selectsExtreme ? nil : request.metric
    }

    static func facts(request: MarinaDataRequest, result: MarinaDataResult, prefix: String) -> [Self] {
        guard ["success", "empty"].contains(result.status) else { return [] }
        // Name resolution identifies a target; it cannot complete the question about it.
        guard request.tool != .findRecords || request.search == nil else { return [] }
        let scope = result.presentation?.scopeLabel ?? result.scope
        var facts: [Self] = []
        func add(_ subject: String, _ relation: String, _ value: String, scope override: String? = nil) {
            guard facts.count < 6 else { return }
            facts.append(.init(id: "\(prefix)f\(facts.count)", subject: subject, relation: relation,
                               value: value, scope: override ?? scope, isFocus: facts.isEmpty))
        }
        func metric(_ label: String) -> MarinaDataResult.Metric? { result.metrics.first { $0.label == label } }
        func amount(_ value: Double) -> String { CurrencyFormatter.string(from: value) }
        func addMetric(_ label: String, subject: String? = nil) {
            guard let item = metric(label) else { return }
            let phrasing: (String, String)
            switch label {
            case "Actual savings": phrasing = ("Your actual savings", "are")
            case "Projected savings": phrasing = ("Your projected savings", "are")
            case "Max savings": phrasing = ("Your Max Savings estimate", "is")
            case "Actual income": phrasing = ("You", "have received")
            case "Planned income": phrasing = ("Your planned income", "is")
            case "Total": phrasing = (request.tool == .income ? "Your income" : "Your spending", "totals")
            case "Count": phrasing = ("Matching records", "number")
            case "Categories over limit", "Categories near limit": phrasing = (label, "number")
            case "Gap to projected savings": phrasing = ("The gap to your projected savings", "is")
            case "Savings progress percent": phrasing = ("Your savings progress", "is")
            default: phrasing = (label, "is")
            }
            add(subject ?? phrasing.0, subject == nil ? phrasing.1 : "is", item.formatted)
        }
        if request.tool == .findRecords {
            add("Matching records", "number", String(result.totalCount))
            for row in result.records.prefix(3) { add(row.title, "is a matching", row.kind) }
            return facts
        }
        if let leaders = result.report?.leaders, !leaders.isEmpty {
            for leader in leaders.prefix(2) {
                if let title = leader.title, let value = leader.amount {
                    add(title, leader.tiedCount > 1 ? "is tied for the highest \(request.grouping.rawValue) total at" : "has the highest \(request.grouping.rawValue) total at",
                        amount(value), scope: leader.scope)
                } else {
                    add("Matching expenses", "number", "0", scope: leader.scope)
                }
            }
            if leaders.prefix(2).count == 2, leaders.prefix(2).allSatisfy({ $0.amount != nil }), let difference = metric("Difference") {
                add("The difference between those leading amounts", difference.value < 0 ? "is a decrease of" : difference.value > 0 ? "is an increase of" : "is",
                    amount(abs(difference.value)))
            }
            for index in facts.indices { facts[index].isFocus = true }
            return facts
        }
        if request.operation == .comparison || result.presentation?.operation == .comparison {
            if let first = metric("Total") { add(request.tool == .income ? "Your income" : "Your spending", "totals", first.formatted) }
            if let second = metric("Comparison total") {
                add("The compared total", "is", second.formatted, scope: result.presentation?.chartPoints.last?.label ?? "the compared period")
            }
            if let difference = metric("Difference") {
                add("The change", difference.value < 0 ? "is a decrease of" : difference.value > 0 ? "is an increase of" : "is",
                    amount(abs(difference.value)))
            }
            for index in facts.indices { facts[index].isFocus = true }
            return facts
        }
        if let focus = standaloneMetricFocus(request: request, result: result) {
            addMetric(focus.metricLabel)
            if facts.isEmpty { add(focus.metricLabel, [.actualSavings, .projectedSavings].contains(focus) ? "are" : "is", "not available for this result") }
            return facts
        }
        if request.purpose == .categoryAvailability, let categories = result.report?.categories {
            if categories.isEmpty { add("Categories matching that status", "number", "0"); return facts }
            for category in categories.prefix(3) {
                let status: String
                switch category.status {
                case "over": status = "is over its limit, with"
                case "near": status = "is nearing its limit, with"
                case "unlimited": status = "has no maximum limit, with"
                default: status = "has"
                }
                var value = category.available.map { amount(abs($0)) + ($0 < 0 ? " over the limit" : " available") }
                    ?? amount(category.planned + category.variable) + " spent"
                if let minimum = category.minimum { value += " and a minimum goal of " + amount(minimum) }
                let limitScope = result.report?.budgetName.map { scope + ", using limits from " + $0 } ?? scope
                add(category.name, status, value, scope: limitScope)
            }
            addMetric("Categories over limit"); addMetric("Categories near limit")
            return facts
        }
        if request.purpose == .nextPlannedExpense, let row = result.records.first, let value = row.amount {
            add(row.title, "is your next scheduled planned expense at", amount(value), scope: row.date.map { scope + ", scheduled " + $0 } ?? scope)
            return facts
        }
        if request.operation == .transactions, request.limit == 1,
           [.largest, .smallest].contains(request.sort), let row = result.records.first, let value = row.amount {
            if request.offset > 0 {
                add(row.title, "is an expense of", amount(value))
                return facts
            }
            let tied = (metric("Tied expenses")?.value ?? 1) > 1
            add(row.title, tied ? "is tied for your \(request.sort == .largest ? "highest" : "lowest") expense at"
                : (request.sort == .largest ? "is your highest expense at" : "is your lowest expense at"), amount(value))
            return facts
        }
        if [.ranking, .share].contains(request.operation), let row = result.records.first, let value = row.amount {
            let tied = (metric("Tied leading groups")?.value ?? 1) > 1
            let direction = request.sort == .smallest ? "lowest" : "highest"
            let relation = request.offset > 0 ? "totals" : tied
                ? "is tied for the \(direction) \(request.grouping.rawValue) total at"
                : "has the \(direction) \(request.grouping.rawValue) total at"
            add(row.title, relation, amount(value))
            if let group = result.report?.groups?.first, let share = group.sharePercent {
                add("Its share of the total", "is", (share / 100).formatted(.percent.precision(.fractionLength(0...1))))
            }
            return facts
        }
        if request.operation == .transactions, result.records.count == 1,
           let row = result.records.first,
           let transaction = result.report?.transactions?.first(where: { $0.id == row.id }) {
            let kind = transaction.transactionKind == "planned" ? "planned expense" : (transaction.transactionKind ?? "expense")
            add(row.title, "is \(["adjustment", "expense"].contains(kind) ? "an" : "a") \(kind) with an original amount of", amount(transaction.grossAmount))
            add("Its budget impact", "is", amount(transaction.budgetImpact))
            if let recorded = transaction.recordedAmount { add("Its recorded amount", "is", amount(recorded)) }
            if transaction.effectiveAmount != transaction.recordedAmount { add("Its effective amount", "is", amount(transaction.effectiveAmount)) }
            if transaction.splitAmount > 0 { add("The allocated share", "is", amount(transaction.splitAmount)) }
            if transaction.reconciliationOffset > 0 { add("The reconciliation offset", "is", amount(transaction.reconciliationOffset)) }
            if transaction.savingsOffset > 0 { add("The savings offset", "is", amount(transaction.savingsOffset)) }
            if let name = transaction.sourcePresetName {
                add(row.title, "comes from the preset", name + (transaction.sourceBudgetName.map { " in budget " + $0 } ?? ""))
            }
            return facts
        }
        switch request.purpose {
        case .cardSummary:
            addMetric("Total", subject: "Your card spending")
            addMetric("Planned card spending"); addMetric("Variable card spending")
        case .budgetDetails:
            if let received = metric("Actual income"), let planned = metric("Planned income") {
                add("You", "have received", "\(received.formatted), with \(planned.formatted) in planned income")
            }
            addMetric("Total", subject: "Your combined spending")
            if let planned = metric("Planned spending"), let recorded = metric("Recorded planned expenses"), let effective = metric("Effective planned spending") {
                add("Planned expenses", "have", "\(planned.formatted) planned, \(recorded.formatted) recorded, and \(effective.formatted) in effective spending")
            }
            addMetric("Variable spending", subject: "Your variable spending")
            if let actual = metric("Actual savings"), let projected = metric("Projected savings") {
                add("Your savings", "are", "\(actual.formatted) actual and \(projected.formatted) projected")
            }
            addMetric("Max savings")
        case .savingsOutlook, .savingsTimeline:
            for label in ["Actual savings", "Projected savings", "Gap to projected savings", "Savings progress percent"] { addMetric(label) }
        case .incomeProgress, .incomeTimeline:
            addMetric("Actual income", subject: "Your received income")
            addMetric("Planned income", subject: "Your planned income")
            addMetric("Income progress percent")
        case .budgetPace:
            for label in ["Pace actual spending", "Expected spending by now", "Spending pace difference"] { addMetric(label) }
        case .spendingPatterns:
            addMetric("Total", subject: "Your spending")
            if let peak = result.report?.peak {
                add("Your highest-spending period", "totals", amount(peak.amount), scope: "\(peak.startDate) through \(peak.endDate)")
                if let category = peak.leadingCategory, let value = peak.leadingCategoryAmount {
                    add(category, "is the largest category in that period at", amount(value), scope: "\(peak.startDate) through \(peak.endDate)")
                }
            }
            if let merchant = result.report?.merchants?.first { add(merchant.title, "has your highest merchant spending at", amount(merchant.amount)) }
            if let merchant = result.report?.frequentMerchants?.first, let count = merchant.count { add(merchant.title, "has the most recorded purchases at", String(count)) }
        case .budgetCards, .budgetPresets:
            add("Linked \(request.purpose == .budgetCards ? "cards" : "presets")", "number", String(result.totalCount))
            for row in result.records.prefix(3) {
                add(row.title, "is linked with these details:", row.detail ?? "linked to this budget")
            }
        default:
            if request.tool == .accounts {
                for item in result.metrics where item.label.hasSuffix("current balance") || item.label.hasSuffix("current reconciliation balance") {
                    let reconciliation = item.label.hasSuffix("current reconciliation balance")
                    let relation = reconciliation
                        ? (item.value > 0 ? "is owed to you, totaling" : item.value < 0 ? "is owed by you, totaling" : "is settled at") : "is"
                    add(item.label, relation, amount(reconciliation ? abs(item.value) : item.value), scope: "all ledger history")
                }
            } else if request.tool == .budgetSummary {
                for label in ["Remaining room", "Safe spend today", "Projected savings"] { addMetric(label) }
            } else {
                addMetric("Total", subject: request.tool == .income ? "Your income" : "Your spending")
            }
        }
        if facts.isEmpty, let total = metric("Total") { add("The matching total", "is", total.formatted) }
        return facts
    }
}
