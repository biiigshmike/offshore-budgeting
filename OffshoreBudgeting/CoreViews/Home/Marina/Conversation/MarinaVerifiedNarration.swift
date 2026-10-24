import Foundation

/// Financial captions use the same validated snapshot as the visible result. Model prose must
/// not relabel a date, reverse a balance direction, or introduce a second calculation.
enum MarinaVerifiedNarration {
    static func text(request: MarinaDataRequest, result: MarinaDataResult) -> String? {
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
        let title = result.presentation?.title ?? "Result"
        func metric(_ label: String) -> MarinaDataResult.Metric? { result.metrics.first { $0.label == label } }
        func facts(_ labels: [String]) -> String {
            labels.compactMap { label in metric(label).map { "\($0.label): \($0.formatted)" } }.joined(separator: "; ")
        }
        let body: String
        if request.tool == .accounts {
            if request.accountID != nil,
               let balance = result.metrics.first(where: { $0.label.hasSuffix("current balance") || $0.label.hasSuffix("current reconciliation balance") }) {
                var caption = "\(balance.label): \(balance.formatted)."
                if balance.label.hasSuffix("current reconciliation balance") {
                    if balance.value > 0 { caption += " Money is owed to you." }
                    else if balance.value < 0 { caption += " You owe money." }
                    else { caption += " This account is settled." }
                }
                if let count = metric("Selected period activity count"), let activity = metric("Selected period activity total") {
                    caption += " Activity for \(scope): \(count.formatted) entries, net \(activity.formatted)."
                }
                return caption
            }
            let kind = request.scope == .savings ? "savings" : request.scope == .reconciliation ? "reconciliation" : "savings and reconciliation"
            return "Current \(kind) balances: \(result.totalCount) accounts. These are all-time ledger balances; dates filter activity only."
        } else if result.presentation?.operation == .comparison || request.operation == .comparison {
            let compared = result.presentation?.chartPoints.last?.label ?? "Compared period"
            let first = metric("Total").map(\.formatted) ?? "—"
            let second = metric("Comparison total").map(\.formatted) ?? "—"
            let change = facts(["Difference", "Change percent"])
            return "\(scope): \(first); \(compared): \(second)." + (change.isEmpty ? "" : " \(change).")
        } else if request.purpose == .incomeProgress {
            body = facts(["Actual income", "Planned income", "Income progress percent"])
        } else if request.purpose == .budgetPace {
            body = facts(["Pace actual spending", "Expected spending by now", "Spending pace difference"])
        } else if request.tool == .budgetSummary {
            body = facts(request.hypotheticalSpending == nil
                ? ["Remaining room", "Safe spend today", "Projected savings"]
                : ["Hypothetical additional spending", "Projected savings after hypothetical spending"])
        } else if request.operation == .transactions, request.limit == 1, request.sort == .largest,
                  let record = result.records.first, let amount = record.amount {
            body = "\(record.title): \(CurrencyFormatter.string(from: amount))" + (record.date.map { " (\($0))" } ?? "")
        } else {
            body = facts(["Total"])
        }
        let qualifier = result.presentation?.qualifier.map { " \($0)" } ?? ""
        let caption = body.isEmpty ? "\(result.totalCount) matching records" : body
        return "\(title) — \(scope). \(caption).\(qualifier)"
    }
}
