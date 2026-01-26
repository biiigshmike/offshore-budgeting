//
//  ImportLearningStore.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/25/26.
//

import Foundation
import SwiftData

@MainActor
struct ImportLearningStore {

    static func fetchRules(for workspace: Workspace, modelContext: ModelContext) -> [String: ImportMerchantRule] {
        // Fetch all rules for workspace, build dictionary keyed by merchantKey.
        let wsID = workspace.id

        let descriptor = FetchDescriptor<ImportMerchantRule>(
            predicate: #Predicate { rule in
                rule.workspace?.id == wsID
            }
        )

        let rules = (try? modelContext.fetch(descriptor)) ?? []
        var dict: [String: ImportMerchantRule] = [:]
        for r in rules {
            let key = r.merchantKey
            if !key.isEmpty {
                dict[key] = r
            }
        }
        return dict
    }

    static func upsertRule(
        merchantKey: String,
        preferredName: String?,
        preferredCategory: Category?,
        workspace: Workspace,
        modelContext: ModelContext
    ) {
        let key = merchantKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        let wsID = workspace.id
        let descriptor = FetchDescriptor<ImportMerchantRule>(
            predicate: #Predicate { rule in
                rule.workspace?.id == wsID && rule.merchantKey == key
            }
        )

        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.preferredName = preferredName
            existing.preferredCategory = preferredCategory
            existing.updatedAt = Date.now
        } else {
            let newRule = ImportMerchantRule(
                merchantKey: key,
                preferredName: preferredName,
                preferredCategory: preferredCategory,
                workspace: workspace
            )
            modelContext.insert(newRule)
        }
    }
}
