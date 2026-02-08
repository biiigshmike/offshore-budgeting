//
//  HomeAssistantAliasStore.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/8/26.
//

import Foundation
import SwiftData

// MARK: - Alias Store

@MainActor
struct HomeAssistantAliasStore {

    static func upsertRule(
        aliasKey: String,
        targetValue: String,
        entityType: HomeAssistantAliasEntityType,
        workspace: Workspace,
        modelContext: ModelContext
    ) {
        let trimmedAlias = aliasKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTarget = targetValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedAlias.isEmpty == false, trimmedTarget.isEmpty == false else { return }

        let workspaceID = workspace.id
        let descriptor = FetchDescriptor<AssistantAliasRule>(
            predicate: #Predicate { rule in
                rule.workspace?.id == workspaceID
                    && rule.aliasKey == trimmedAlias
                    && rule.entityTypeRaw == entityType.rawValue
            }
        )

        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.targetValue = trimmedTarget
            existing.updatedAt = Date.now
        } else {
            let newRule = AssistantAliasRule(
                aliasKey: trimmedAlias,
                targetValue: trimmedTarget,
                entityType: entityType,
                workspace: workspace
            )
            modelContext.insert(newRule)
        }
    }
}
