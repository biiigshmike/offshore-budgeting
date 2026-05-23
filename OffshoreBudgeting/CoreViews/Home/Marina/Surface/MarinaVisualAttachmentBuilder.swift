//
//  MarinaVisualAttachmentBuilder.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 5/22/26.
//

import Foundation

@MainActor
struct MarinaVisualAttachmentBuilder {
    func attachingVisualAttachmentIfNeeded(
        to answer: HomeAnswer,
        workspace: Workspace,
        cards: [Card],
        allocationAccounts: [AllocationAccount],
        savingsAccounts: [SavingsAccount],
        categories: [Category],
        presets: [Preset],
        variableExpenses: [VariableExpense],
        plannedExpenses: [PlannedExpense],
        savingsEntries: [SavingsLedgerEntry],
        dateRange: HomeQueryDateRange,
        excludeFuturePlannedExpenses: Bool,
        excludeFutureVariableExpenses: Bool
    ) -> HomeAnswer {
        guard answer.attachment == nil else { return answer }

        let cardAnswer = MarinaCardSummaryAttachmentBuilder().attachingCardSummaryIfNeeded(
            to: answer,
            cards: cards,
            dateRange: dateRange,
            excludeFuturePlannedExpenses: excludeFuturePlannedExpenses,
            excludeFutureVariableExpenses: excludeFutureVariableExpenses
        )
        if cardAnswer.attachment != nil { return cardAnswer }

        if let summary = entitySummary(
            for: answer,
            workspace: workspace,
            cards: cards,
            allocationAccounts: allocationAccounts,
            savingsAccounts: savingsAccounts,
            categories: categories,
            presets: presets,
            variableExpenses: variableExpenses,
            plannedExpenses: plannedExpenses,
            savingsEntries: savingsEntries
        ) {
            return applying(
                .entitySummary(summary),
                to: answer,
                subtitle: fallbackSubtitle(for: summary)
            )
        }

        if let rowList = rowList(
            for: answer,
            allocationAccounts: allocationAccounts,
            variableExpenses: variableExpenses,
            plannedExpenses: plannedExpenses,
            savingsEntries: savingsEntries
        ) {
            return applying(
                .rowList(rowList),
                to: answer,
                subtitle: fallbackSubtitle(for: rowList)
            )
        }

        if let contract = formulaContract(for: answer) {
            return applying(
                .formulaContract(contract),
                to: answer,
                subtitle: answer.subtitle ?? fallbackSubtitle(for: contract)
            )
        }

        if let comparison = comparisonSummary(for: answer) {
            return applying(
                .comparisonSummary(comparison),
                to: answer,
                subtitle: answer.subtitle ?? fallbackSubtitle(for: comparison)
            )
        }

        if let trend = trendChart(for: answer) {
            return applying(
                .trendChart(trend),
                to: answer,
                subtitle: answer.subtitle ?? "Here's the trend from your deterministic rows."
            )
        }

        if let breakdown = breakdownList(for: answer) {
            return applying(
                .breakdownList(breakdown),
                to: answer,
                subtitle: answer.subtitle ?? fallbackSubtitle(for: breakdown)
            )
        }

        if let metric = metricSummary(for: answer) {
            return applying(
                .metricSummary(metric),
                to: answer,
                subtitle: answer.subtitle ?? fallbackSubtitle(for: metric)
            )
        }

        if let generic = genericSummary(for: answer) {
            return applying(
                .genericSummary(generic),
                to: answer,
                subtitle: answer.subtitle ?? "Here are the details I found."
            )
        }

        return answer
    }

    private func entitySummary(
        for answer: HomeAnswer,
        workspace: Workspace,
        cards: [Card],
        allocationAccounts: [AllocationAccount],
        savingsAccounts: [SavingsAccount],
        categories: [Category],
        presets: [Preset],
        variableExpenses: [VariableExpense],
        plannedExpenses: [PlannedExpense],
        savingsEntries: [SavingsLedgerEntry]
    ) -> MarinaEntitySummaryPresentationModel? {
        guard answer.kind == .message else { return nil }

        let typedRows = answer.rows.compactMap { row -> (MarinaLookupObjectType, UUID?)? in
            guard let objectType = row.objectType else { return nil }
            return (objectType, row.sourceID)
        }
        guard typedRows.isEmpty == false else { return nil }

        let objectTypes = Set(typedRows.map(\.0))
        guard objectTypes.count == 1, let objectType = objectTypes.first else { return nil }

        let sourceIDs = Set(typedRows.compactMap(\.1))
        let sourceID = sourceIDs.count == 1 ? sourceIDs.first : nil

        switch objectType {
        case .reconciliationAccount:
            guard let sourceID,
                  let account = allocationAccounts.first(where: { $0.id == sourceID }) else {
                return nil
            }
            let balance = CurrencyFormatter.normalizedCurrencyDisplayValue(AllocationLedgerService.balance(for: account))
            return MarinaEntitySummaryPresentationModel(
                sourceID: account.id,
                objectType: .reconciliationAccount,
                title: account.name,
                subtitle: "Reconciliation account",
                primaryValue: CurrencyFormatter.string(from: balance),
                systemImage: "person.2.fill",
                tintHex: account.hexColor,
                rows: [
                    .init(title: "Status", value: account.isArchived ? "Archived" : "Active"),
                    .init(title: "Ledger rows", value: integer((account.expenseAllocations ?? []).count + (account.settlements ?? []).count))
                ]
            )

        case .savingsAccount:
            guard let sourceID,
                  let account = savingsAccounts.first(where: { $0.id == sourceID }) else {
                return nil
            }
            let entries = savingsEntries.filter { $0.account?.id == account.id }
            var rows: [MarinaEntitySummaryPresentationModel.DetailRow] = [
                .init(title: "Ledger entries", value: integer(entries.count))
            ]
            if let latest = entries.max(by: { $0.date < $1.date }) {
                rows.append(.init(title: "Last activity", value: AppDateFormat.abbreviatedDate(latest.date)))
            }
            return MarinaEntitySummaryPresentationModel(
                sourceID: account.id,
                objectType: .savingsAccount,
                title: account.name,
                subtitle: "Savings account",
                primaryValue: CurrencyFormatter.string(from: account.total),
                systemImage: "banknote.fill",
                tintHex: "#22C55E",
                rows: rows
            )

        case .category:
            guard let sourceID,
                  let category = categories.first(where: { $0.id == sourceID }) else {
                return nil
            }
            let variableCount = variableExpenses.filter { $0.category?.id == category.id }.count
            let plannedCount = plannedExpenses.filter { $0.category?.id == category.id }.count
            return MarinaEntitySummaryPresentationModel(
                sourceID: category.id,
                objectType: .category,
                title: category.name,
                subtitle: "Category",
                primaryValue: nil,
                systemImage: "tag.fill",
                tintHex: category.hexColor,
                rows: [
                    .init(title: "Variable rows", value: integer(variableCount)),
                    .init(title: "Planned rows", value: integer(plannedCount))
                ]
            )

        case .preset:
            guard let sourceID,
                  let preset = presets.first(where: { $0.id == sourceID }) else {
                return nil
            }
            return MarinaEntitySummaryPresentationModel(
                sourceID: preset.id,
                objectType: .preset,
                title: preset.title,
                subtitle: "Preset",
                primaryValue: CurrencyFormatter.string(from: preset.plannedAmount),
                systemImage: "list.bullet.rectangle.fill",
                tintHex: preset.defaultCategory?.hexColor ?? "#3B82F6",
                rows: [
                    .init(title: "Frequency", value: presetScheduleText(preset)),
                    .init(title: "Card", value: preset.defaultCard?.name ?? "None"),
                    .init(title: "Category", value: preset.defaultCategory?.name ?? "Uncategorized"),
                    .init(title: "Status", value: preset.isArchived ? "Archived" : "Active")
                ]
            )

        case .workspace:
            let isCurrentWorkspace = sourceID == nil || sourceID == workspace.id
            guard isCurrentWorkspace else { return nil }
            return MarinaEntitySummaryPresentationModel(
                sourceID: workspace.id,
                objectType: .workspace,
                title: workspace.name,
                subtitle: "Workspace",
                primaryValue: "Current",
                systemImage: "person.crop.circle.fill",
                tintHex: workspace.hexColor,
                rows: [
                    .init(title: "Cards", value: integer(cards.count)),
                    .init(title: "Categories", value: integer(categories.count)),
                    .init(title: "Presets", value: integer(presets.count))
                ]
            )

        default:
            return nil
        }
    }

    private func rowList(
        for answer: HomeAnswer,
        allocationAccounts: [AllocationAccount],
        variableExpenses: [VariableExpense],
        plannedExpenses: [PlannedExpense],
        savingsEntries: [SavingsLedgerEntry]
    ) -> MarinaRowListPresentationModel? {
        let sourceRows = visibleRows(from: answer)
        guard answer.kind == .list, sourceRows.isEmpty == false else { return nil }
        let rowTypes = sourceRows.compactMap(\.objectType)
        guard rowTypes.count == sourceRows.count else { return nil }

        let family: MarinaRowListPresentationModel.Family?
        if rowTypes.allSatisfy({ $0 == .variableExpense || $0 == .plannedExpense }) {
            family = .expenses
        } else if rowTypes.allSatisfy({ $0 == .reconciliationItem || $0 == .expenseAllocation }) {
            family = .reconciliation
        } else if rowTypes.allSatisfy({ $0 == .savingsLedgerEntry }) {
            family = .savings
        } else {
            family = nil
        }
        guard let family else { return nil }

        let rows = sourceRows.compactMap { row -> MarinaRowListPresentationModel.Row? in
            guard let objectType = row.objectType else { return nil }
            switch objectType {
            case .variableExpense:
                return variableRow(from: row, expenses: variableExpenses)
            case .plannedExpense:
                return plannedRow(from: row, expenses: plannedExpenses)
            case .expenseAllocation:
                return allocationRow(from: row, allocationAccounts: allocationAccounts)
            case .reconciliationItem:
                return settlementRow(from: row, allocationAccounts: allocationAccounts)
            case .savingsLedgerEntry:
                return savingsRow(from: row, savingsEntries: savingsEntries)
            default:
                return nil
            }
        }
        guard rows.count == sourceRows.count else { return nil }

        return MarinaRowListPresentationModel(
            title: answer.title,
            subtitle: answer.subtitle ?? "\(integer(rows.count)) rows",
            family: family,
            rows: rows
        )
    }

    private func formulaContract(for answer: HomeAnswer) -> MarinaFormulaContractPresentationModel? {
        let contractRows = answer.rows.filter { $0.role == .contract }
        let visibleRows = visibleRows(from: answer)
        let textLooksContractBacked = answer.rows.contains { row in
            normalized(row.title) == "metric contract" || normalized(row.title) == "contract status"
        }
        let title = normalized(answer.title)
        let contractAnswerTitle = title.contains("formula contract")
            || title.contains("cannot run")
            || title.contains("needs one setup")
            || title.contains("knows this metric")
        guard (contractRows.isEmpty == false || textLooksContractBacked),
              contractAnswerTitle || visibleRows.isEmpty else { return nil }
        let rows = (contractRows.isEmpty ? answer.rows : contractRows).map(displayRow)
        return MarinaFormulaContractPresentationModel(
            title: answer.title,
            subtitle: answer.subtitle,
            status: answer.primaryValue,
            rows: rows
        )
    }

    private func comparisonSummary(for answer: HomeAnswer) -> MarinaComparisonSummaryPresentationModel? {
        let rows = visibleRows(from: answer)
        let title = normalized(answer.title)
        guard answer.kind == .comparison
            || title.contains(" vs ")
            || title.contains("versus")
            || rows.contains(where: { normalized($0.title).contains("previous") }) else {
            return nil
        }
        guard rows.count >= 2 else { return nil }
        let primary = rows[0]
        let comparison = rows[1]
        let delta = rows.dropFirst(2).first { row in
            let title = normalized(row.title)
            return title.contains("change") || title.contains("delta") || title.contains("gap")
        }
        return MarinaComparisonSummaryPresentationModel(
            title: answer.title,
            subtitle: answer.subtitle,
            primaryLabel: primary.title,
            primaryValue: primary.value,
            comparisonLabel: comparison.title,
            comparisonValue: comparison.value,
            deltaLabel: delta?.title,
            deltaValue: delta?.value,
            rows: rows.dropFirst(2).map(displayRow)
        )
    }

    private func trendChart(for answer: HomeAnswer) -> MarinaTrendChartPresentationModel? {
        let rows = visibleRows(from: answer)
        guard normalized(answer.title).contains("trend"), rows.count >= 2 else { return nil }
        let points = rows.compactMap { row -> MarinaTrendChartPresentationModel.Point? in
            guard let amount = row.amount ?? currencyAmount(in: row.value) else { return nil }
            return MarinaTrendChartPresentationModel.Point(
                label: row.title,
                value: amount,
                renderedValue: row.value
            )
        }
        guard points.count >= 2 else { return nil }
        return MarinaTrendChartPresentationModel(
            title: answer.title,
            subtitle: answer.subtitle,
            points: points
        )
    }

    private func breakdownList(for answer: HomeAnswer) -> MarinaBreakdownListPresentationModel? {
        let rows = visibleRows(from: answer)
        guard answer.kind == .list, rows.isEmpty == false else { return nil }
        return MarinaBreakdownListPresentationModel(
            title: answer.title,
            subtitle: answer.subtitle,
            primaryValue: answer.primaryValue,
            rows: rows.map(displayRow)
        )
    }

    private func metricSummary(for answer: HomeAnswer) -> MarinaMetricSummaryPresentationModel? {
        let rows = visibleRows(from: answer)
        guard answer.kind == .metric || (answer.primaryValue != nil && answer.kind != .list) else { return nil }
        return MarinaMetricSummaryPresentationModel(
            title: answer.title,
            subtitle: answer.subtitle,
            primaryValue: answer.primaryValue,
            systemImage: metricSystemImage(for: answer),
            tintHex: metricTintHex(for: answer),
            rows: rows.map(displayRow)
        )
    }

    private func genericSummary(for answer: HomeAnswer) -> MarinaGenericSummaryPresentationModel? {
        let rows = visibleRows(from: answer)
        guard rows.isEmpty == false || answer.primaryValue != nil else { return nil }
        return MarinaGenericSummaryPresentationModel(
            title: answer.title,
            subtitle: answer.subtitle,
            primaryValue: answer.primaryValue,
            rows: rows.map(displayRow)
        )
    }

    private func variableRow(
        from row: HomeAnswerRow,
        expenses: [VariableExpense]
    ) -> MarinaRowListPresentationModel.Row {
        let expense = row.sourceID.flatMap { id in expenses.first(where: { $0.id == id }) }
        let amount = expense?.ledgerSignedAmount() ?? row.amount
        let date = expense?.transactionDate ?? row.date
        return MarinaRowListPresentationModel.Row(
            sourceID: row.sourceID,
            objectType: .variableExpense,
            title: expense?.descriptionText ?? row.title,
            subtitle: expense.map { subtitle(parts: [shortDate($0.transactionDate), $0.kind.displayTitle, $0.card?.name, $0.category?.name]) } ?? row.value,
            value: amount.map { CurrencyFormatter.string(from: $0) } ?? row.value,
            amount: amount,
            date: date,
            systemImage: "creditcard.fill",
            tintHex: expense?.category?.hexColor
        )
    }

    private func plannedRow(
        from row: HomeAnswerRow,
        expenses: [PlannedExpense]
    ) -> MarinaRowListPresentationModel.Row {
        let expense = row.sourceID.flatMap { id in expenses.first(where: { $0.id == id }) }
        let amount = expense.map { SavingsMathService.grossEffectiveAmount(for: $0) } ?? row.amount
        let date = expense?.expenseDate ?? row.date
        return MarinaRowListPresentationModel.Row(
            sourceID: row.sourceID,
            objectType: .plannedExpense,
            title: expense?.title ?? row.title,
            subtitle: expense.map { subtitle(parts: [shortDate($0.expenseDate), $0.card?.name, $0.category?.name]) } ?? row.value,
            value: amount.map { CurrencyFormatter.string(from: $0) } ?? row.value,
            amount: amount,
            date: date,
            systemImage: "calendar.badge.clock",
            tintHex: expense?.category?.hexColor
        )
    }

    private func allocationRow(
        from row: HomeAnswerRow,
        allocationAccounts: [AllocationAccount]
    ) -> MarinaRowListPresentationModel.Row {
        let allocation = row.sourceID.flatMap { id in
            allocationAccounts
                .flatMap { $0.expenseAllocations ?? [] }
                .first(where: { $0.id == id })
        }
        let title = allocation?.expense?.descriptionText
            ?? allocation?.plannedExpense?.title
            ?? row.title
        let rowDate = allocation?.expense?.transactionDate
            ?? allocation?.plannedExpense?.expenseDate
            ?? allocation?.updatedAt
            ?? row.date
        let amount = allocation?.allocatedAmount ?? row.amount
        return MarinaRowListPresentationModel.Row(
            sourceID: row.sourceID,
            objectType: .expenseAllocation,
            title: title,
            subtitle: subtitle(parts: [rowDate.map { shortDate($0) }, allocation?.account?.name, "Allocation"]),
            value: amount.map { CurrencyFormatter.string(from: $0) } ?? row.value,
            amount: amount,
            date: rowDate,
            systemImage: "arrow.trianglehead.branch",
            tintHex: allocation?.account?.hexColor
        )
    }

    private func settlementRow(
        from row: HomeAnswerRow,
        allocationAccounts: [AllocationAccount]
    ) -> MarinaRowListPresentationModel.Row {
        let settlement = row.sourceID.flatMap { id in
            allocationAccounts
                .flatMap { $0.settlements ?? [] }
                .first(where: { $0.id == id })
        }
        let note = settlement?.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = note?.isEmpty == false ? note! : row.title
        let amount = settlement?.amount ?? row.amount
        let date = settlement?.date ?? row.date
        return MarinaRowListPresentationModel.Row(
            sourceID: row.sourceID,
            objectType: .reconciliationItem,
            title: title,
            subtitle: subtitle(parts: [date.map { shortDate($0) }, settlement?.account?.name, "Settlement"]),
            value: amount.map { CurrencyFormatter.string(from: CurrencyFormatter.normalizedCurrencyDisplayValue($0)) } ?? row.value,
            amount: amount,
            date: date,
            systemImage: "arrow.left.arrow.right",
            tintHex: settlement?.account?.hexColor
        )
    }

    private func savingsRow(
        from row: HomeAnswerRow,
        savingsEntries: [SavingsLedgerEntry]
    ) -> MarinaRowListPresentationModel.Row {
        let entry = row.sourceID.flatMap { id in savingsEntries.first(where: { $0.id == id }) }
        let amount = entry?.amount ?? row.amount
        let date = entry?.date ?? row.date
        return MarinaRowListPresentationModel.Row(
            sourceID: row.sourceID,
            objectType: .savingsLedgerEntry,
            title: entry?.ledgerDisplayTitle ?? row.title,
            subtitle: subtitle(parts: [entry?.ledgerKindLabel, date.map { shortDate($0) }, entry?.account?.name]),
            value: amount.map { CurrencyFormatter.string(from: $0) } ?? row.value,
            amount: amount,
            date: date,
            systemImage: "banknote.fill",
            tintHex: "#22C55E"
        )
    }

    private func applying(
        _ attachment: MarinaAttachment,
        to answer: HomeAnswer,
        subtitle: String
    ) -> HomeAnswer {
        HomeAnswer(
            id: answer.id,
            queryID: answer.queryID,
            kind: answer.kind,
            userPrompt: answer.userPrompt,
            title: answer.title,
            subtitle: subtitle,
            primaryValue: answer.primaryValue,
            rows: answer.rows,
            attachment: attachment,
            explanation: answer.explanation,
            generatedAt: answer.generatedAt
        )
    }

    private func fallbackSubtitle(for summary: MarinaEntitySummaryPresentationModel) -> String {
        if let primaryValue = summary.primaryValue {
            return "Here's \(summary.title). \(summary.subtitle) is currently \(primaryValue)."
        }
        return "Here's \(summary.title). I found the \(summary.subtitle.lowercased()) details."
    }

    private func fallbackSubtitle(for rowList: MarinaRowListPresentationModel) -> String {
        "I found \(integer(rowList.rows.count)) \(rowList.family.fallbackNoun) for this lookup."
    }

    private func fallbackSubtitle(for metric: MarinaMetricSummaryPresentationModel) -> String {
        if let primaryValue = metric.primaryValue {
            return "I found \(metric.title.lowercased()): \(primaryValue)."
        }
        return "I found the summary for this lookup."
    }

    private func fallbackSubtitle(for comparison: MarinaComparisonSummaryPresentationModel) -> String {
        if let deltaValue = comparison.deltaValue {
            return "I compared \(comparison.primaryLabel.lowercased()) with \(comparison.comparisonLabel.lowercased()). \(deltaValue)"
        }
        return "I compared the requested periods."
    }

    private func fallbackSubtitle(for breakdown: MarinaBreakdownListPresentationModel) -> String {
        "I found \(integer(breakdown.rows.count)) rows for this breakdown."
    }

    private func fallbackSubtitle(for contract: MarinaFormulaContractPresentationModel) -> String {
        if let status = contract.status {
            return "This formula is known to Marina. Status: \(status)."
        }
        return "This formula is known to Marina."
    }

    private func visibleRows(from answer: HomeAnswer) -> [HomeAnswerRow] {
        answer.rows.filter { row in
            row.role != .trace && row.role != .contract
        }
    }

    private func displayRow(_ row: HomeAnswerRow) -> MarinaDisplayRow {
        MarinaDisplayRow(
            id: row.id,
            title: row.title,
            value: row.value,
            amount: row.amount ?? currencyAmount(in: row.value),
            date: row.date,
            sourceID: row.sourceID,
            objectType: row.objectType,
            role: row.role
        )
    }

    private func metricSystemImage(for answer: HomeAnswer) -> String {
        let title = normalized(answer.title)
        if title.contains("income") { return "arrow.down.circle.fill" }
        if title.contains("saving") { return "banknote.fill" }
        if title.contains("safe spend") { return "shield.lefthalf.filled" }
        if title.contains("reconciliation") || title.contains("shared") { return "person.2.fill" }
        return "chart.bar.fill"
    }

    private func metricTintHex(for answer: HomeAnswer) -> String {
        let title = normalized(answer.title)
        if title.contains("income") { return "#22C55E" }
        if title.contains("saving") { return "#16A34A" }
        if title.contains("safe spend") { return "#0EA5E9" }
        if title.contains("reconciliation") || title.contains("shared") { return "#6366F1" }
        return "#3B82F6"
    }

    private func currencyAmount(in value: String) -> Double? {
        let normalizedValue = value.replacingOccurrences(of: "−", with: "-")
        let patterns = [
            #"\(\s*\$\s*\d[\d,]*(?:\.\d+)?\s*\)"#,
            #"[-+]?\s*\$\s*\d[\d,]*(?:\.\d+)?"#,
            #"\(\s*\d[\d,]*(?:\.\d+)?\s*\)"#,
            #"[-+]?\s*\d[\d,]*(?:\.\d+)?"#
        ]

        for pattern in patterns {
            guard let range = normalizedValue.range(of: pattern, options: .regularExpression) else {
                continue
            }

            let token = String(normalizedValue[range])
            let isParentheticalNegative = token.contains("(") && token.contains(")")
            let cleaned = token
                .replacingOccurrences(of: "[^0-9.\\-]", with: "", options: .regularExpression)

            guard let amount = Double(cleaned) else { continue }
            return isParentheticalNegative ? -amount : amount
        }

        return nil
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func presetScheduleText(_ preset: Preset) -> String {
        let interval = max(1, preset.interval)
        guard interval > 1 else { return preset.frequency.displayName }

        switch preset.frequency {
        case .none:
            return "None"
        case .daily:
            return "Every \(integer(interval)) days"
        case .weekly:
            return "Every \(integer(interval)) weeks"
        case .monthly:
            return "Every \(integer(interval)) months"
        case .yearly:
            return "Every \(integer(interval)) years"
        }
    }

    private func subtitle(parts: [String?]) -> String? {
        let values = parts.compactMap { part -> String? in
            let trimmed = part?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
        return values.isEmpty ? nil : values.joined(separator: " • ")
    }

    private func shortDate(_ date: Date) -> String {
        AppDateFormat.abbreviatedDate(date)
    }

    private func integer(_ value: Int) -> String {
        AppNumberFormat.integer(value)
    }
}

private extension MarinaRowListPresentationModel.Family {
    var fallbackNoun: String {
        switch self {
        case .expenses:
            return "expense rows"
        case .reconciliation:
            return "reconciliation rows"
        case .savings:
            return "savings rows"
        }
    }
}
