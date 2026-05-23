import Foundation

struct MarinaDatabaseLookupResponseBuilder {
    func responseCompatibleAnswer(from response: MarinaDatabaseLookupResponse) -> HomeAnswer {
        let request = response.request
        let queryID = UUID()

        if response.needsClarification {
            return HomeAnswer(
                queryID: queryID,
                kind: .message,
                userPrompt: request.rawPrompt,
                title: "Which \(request.searchText) do you mean?",
                subtitle: "I found more than one kind of Offshore data with that name. Pick the object type and I can show the details.",
                rows: response.ambiguityChoices.map { result in
                    row(from: result)
                }
            )
        }

        guard response.results.isEmpty == false else {
            return HomeAnswer(
                queryID: queryID,
                kind: .message,
                userPrompt: request.rawPrompt,
                title: "No Matching Offshore Data",
                subtitle: "I couldn't find anything matching \"\(request.searchText)\". Try searching by merchant, card, amount, category, budget, or a shorter name.",
                rows: [
                    HomeAnswerRow(title: "Search", value: request.searchText),
                    HomeAnswerRow(title: "Try", value: "Search by merchant, card, amount, category, budget, or a shorter name.")
                ]
            )
        }

        if response.results.count == 1, let result = response.results.first {
            return singleResultAnswer(result, request: request, queryID: queryID)
        }

        return HomeAnswer(
            queryID: queryID,
            kind: .list,
            userPrompt: request.rawPrompt,
            title: listTitle(for: request),
            subtitle: nil,
            rows: response.results.map { result in
                row(from: result)
            }
        )
    }

    private func singleResultAnswer(
        _ result: MarinaDatabaseLookupResult,
        request: MarinaDatabaseLookupRequest,
        queryID: UUID
    ) -> HomeAnswer {
        HomeAnswer(
            queryID: queryID,
            kind: .message,
            userPrompt: request.rawPrompt,
            title: title(for: result, request: request),
            subtitle: result.subtitle,
            primaryValue: primaryValue(for: result, requestedDetail: request.requestedDetail),
            rows: result.detailRows.map {
                HomeAnswerRow(
                    title: $0.label,
                    value: $0.value,
                    sourceID: result.id,
                    objectType: result.objectType,
                    amount: result.amount,
                    date: result.date
                )
            }
        )
    }

    private func row(from result: MarinaDatabaseLookupResult) -> HomeAnswerRow {
        HomeAnswerRow(
            title: result.title,
            value: compactValue(for: result),
            sourceID: result.id,
            objectType: result.objectType,
            amount: result.amount,
            date: result.date
        )
    }

    private func title(
        for result: MarinaDatabaseLookupResult,
        request: MarinaDatabaseLookupRequest
    ) -> String {
        if result.objectType == .workspace {
            return "You are in \(result.title)."
        }

        switch request.requestedDetail {
        case .date:
            if let date = result.date {
                return "\(purchaseVerb(for: result)) \(result.title) on \(formatDate(date))."
            }
        case .amount:
            if let amount = result.amount {
                return "\(result.title) was \(CurrencyFormatter.string(from: amount))."
            }
        case .card:
            if let cardName = result.cardName {
                return "\(result.title) used \(cardName)."
            }
        case .category:
            if let categoryName = result.categoryName {
                return "\(result.title) was categorized as \(categoryName)."
            }
        case .balance:
            if let amount = result.amount {
                return "\(result.title) balance is \(CurrencyFormatter.string(from: amount))."
            }
        case .general, .status, .schedule, .recurrence, .account, .linkedObjects:
            break
        }
        return "I found \(result.title)."
    }

    private func primaryValue(
        for result: MarinaDatabaseLookupResult,
        requestedDetail: MarinaDatabaseLookupRequest.RequestedDetail
    ) -> String? {
        switch requestedDetail {
        case .date:
            return result.date.map(formatDate)
        case .amount, .balance:
            return result.amount.map { CurrencyFormatter.string(from: $0) }
        case .card:
            return result.cardName
        case .category:
            return result.categoryName
        case .account:
            return result.accountName
        case .general, .status, .schedule, .recurrence, .linkedObjects:
            return nil
        }
    }

    private func compactValue(for result: MarinaDatabaseLookupResult) -> String {
        [
            result.objectType.readableName,
            result.date.map(formatDate),
            result.amount.map { CurrencyFormatter.string(from: $0) },
            result.cardName,
            result.categoryName
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    private func listTitle(for request: MarinaDatabaseLookupRequest) -> String {
        if request.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           request.objectTypes.count == 1,
           let objectType = request.objectTypes.first {
            return "Your \(objectType.readablePluralName)"
        }
        return "I found a few matches for \"\(request.searchText)\"."
    }

    private func purchaseVerb(for result: MarinaDatabaseLookupResult) -> String {
        switch result.objectType {
        case .variableExpense:
            return "You purchased"
        case .plannedExpense:
            return "I found the planned expense"
        default:
            return "I found"
        }
    }

    private func formatDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

private extension MarinaLookupObjectType {
    var readableName: String {
        switch self {
        case .budget:
            return "Budget"
        case .income:
            return "Income"
        case .incomeSeries:
            return "Income series"
        case .variableExpense:
            return "Expense"
        case .plannedExpense:
            return "Planned expense"
        case .category:
            return "Category"
        case .preset:
            return "Preset"
        case .card:
            return "Card"
        case .savingsAccount:
            return "Savings account"
        case .savingsLedgerEntry:
            return "Savings ledger entry"
        case .reconciliationAccount:
            return "Reconciliation account"
        case .reconciliationItem:
            return "Reconciliation item"
        case .expenseAllocation:
            return "Expense allocation"
        case .importMerchantRule:
            return "Import merchant rule"
        case .assistantAliasRule:
            return "Assistant alias"
        case .workspace:
            return "Workspace"
        case .unknown:
            return "Item"
        }
    }

    var readablePluralName: String {
        switch self {
        case .budget:
            return "Budgets"
        case .income:
            return "Income"
        case .incomeSeries:
            return "Recurring Income"
        case .variableExpense:
            return "Expenses"
        case .plannedExpense:
            return "Planned Expenses"
        case .category:
            return "Categories"
        case .preset:
            return "Presets"
        case .card:
            return "Cards"
        case .savingsAccount:
            return "Savings Accounts"
        case .savingsLedgerEntry:
            return "Savings Activity"
        case .reconciliationAccount:
            return "Reconciliation Accounts"
        case .reconciliationItem:
            return "Settlements"
        case .expenseAllocation:
            return "Allocations"
        case .importMerchantRule:
            return "Import Merchant Rules"
        case .assistantAliasRule:
            return "Marina Aliases"
        case .workspace:
            return "Workspaces"
        case .unknown:
            return "Items"
        }
    }
}
