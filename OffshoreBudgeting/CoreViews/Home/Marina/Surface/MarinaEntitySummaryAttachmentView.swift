//
//  MarinaEntitySummaryAttachmentView.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 5/22/26.
//

import SwiftUI

struct MarinaEntitySummaryAttachmentView: View {
    let workspace: Workspace
    let summary: MarinaEntitySummaryPresentationModel
    let allocationAccount: AllocationAccount?
    let savingsAccount: SavingsAccount?

    var body: some View {
        Group {
            if summary.objectType == .reconciliationAccount, let allocationAccount {
                NavigationLink {
                    AllocationAccountDetailView(workspace: workspace, account: allocationAccount)
                } label: {
                    summaryCard(showsChevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens reconciliation details")

            } else if summary.objectType == .savingsAccount, savingsAccount != nil {
                NavigationLink {
                    SavingsAccountView(workspace: workspace)
                } label: {
                    summaryCard(showsChevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens savings account")

            } else {
                summaryCard(showsChevron: false)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summary.title) \(summary.subtitle)")
        .accessibilityValue(accessibilitySummary)
        .accessibilityIdentifier("marina.entitySummary")
    }

    private func summaryCard(showsChevron: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.16))

                    Image(systemName: summary.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    Text(summary.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    if let primaryValue = summary.primaryValue {
                        Text(primaryValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }

                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if summary.rows.isEmpty == false {
                VStack(spacing: 8) {
                    ForEach(summary.rows) { row in
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.title)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.primary)

                            Spacer(minLength: 12)

                            Text(row.value)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
    }

    private var tint: Color {
        summary.tintHex.flatMap { Color(hex: $0) } ?? Color.accentColor
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        if let primaryValue = summary.primaryValue {
            parts.append(primaryValue)
        }
        parts.append(contentsOf: summary.rows.map { "\($0.title): \($0.value)" })
        return parts.joined(separator: ", ")
    }
}
