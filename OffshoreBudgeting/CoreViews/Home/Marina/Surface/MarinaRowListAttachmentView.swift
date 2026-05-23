//
//  MarinaRowListAttachmentView.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 5/22/26.
//

import SwiftUI

struct MarinaRowListAttachmentView: View {
    let model: MarinaRowListPresentationModel
    let variableExpenses: [VariableExpense]
    let plannedExpenses: [PlannedExpense]
    let savingsEntries: [SavingsLedgerEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: model.family.systemImage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(model.family.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    if let subtitle = model.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                Text(AppNumberFormat.integer(model.rows.count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                    rowContent(row)
                        .padding(.vertical, 7)
                        .accessibilityIdentifier("marina.rowList.row.\(index)")

                    if index < model.rows.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.title)
        .accessibilityValue(accessibilitySummary)
        .accessibilityIdentifier("marina.rowList")
    }

    @ViewBuilder
    private func rowContent(_ row: MarinaRowListPresentationModel.Row) -> some View {
        if row.objectType == .variableExpense,
           let id = row.sourceID,
           let expense = variableExpenses.first(where: { $0.id == id }) {
            SharedVariableExpenseRow(expense: expense)
        } else if row.objectType == .plannedExpense,
                  let id = row.sourceID,
                  let expense = plannedExpenses.first(where: { $0.id == id }) {
            SharedPlannedExpenseRow(expense: expense)
        } else if row.objectType == .savingsLedgerEntry,
                  let id = row.sourceID,
                  let entry = savingsEntries.first(where: { $0.id == id }) {
            SavingsLedgerRow(entry: entry)
        } else {
            snapshotRow(row)
        }
    }

    private func snapshotRow(_ row: MarinaRowListPresentationModel.Row) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(rowTint(row).opacity(0.16))

                Image(systemName: row.systemImage ?? model.family.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(rowTint(row))
            }
            .frame(width: 28, height: 28)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(row.value)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(amountTint(row))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                if let secondaryValue = row.secondaryValue {
                    Text(secondaryValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                }
            }
        }
    }

    private func rowTint(_ row: MarinaRowListPresentationModel.Row) -> Color {
        row.tintHex.flatMap { Color(hex: $0) } ?? model.family.tint
    }

    private func amountTint(_ row: MarinaRowListPresentationModel.Row) -> Color {
        switch row.objectType {
        case .savingsLedgerEntry, .reconciliationItem:
            guard let amount = row.amount else { return .primary }
            return amount >= 0 ? .green : .red
        case .variableExpense:
            guard let amount = row.amount else { return .primary }
            return amount < 0 ? .green : .primary
        default:
            return .primary
        }
    }

    private var accessibilitySummary: String {
        model.rows.map { "\($0.title): \($0.value)" }.joined(separator: ", ")
    }
}

private extension MarinaRowListPresentationModel.Family {
    var systemImage: String {
        switch self {
        case .expenses:
            return "creditcard.fill"
        case .reconciliation:
            return "person.2.fill"
        case .savings:
            return "banknote.fill"
        }
    }

    var tint: Color {
        switch self {
        case .expenses:
            return .teal
        case .reconciliation:
            return .indigo
        case .savings:
            return .green
        }
    }
}
