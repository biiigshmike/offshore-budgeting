//
//  AppResetService.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/23/26.
//

import Foundation
import SwiftData

enum AppResetService {

    static func eraseAllLocalData(modelContext: ModelContext) throws {

        try deleteAll(VariableExpense.self, modelContext: modelContext)
        try deleteAll(PlannedExpense.self, modelContext: modelContext)
        try deleteAll(Income.self, modelContext: modelContext)
        try deleteAll(Preset.self, modelContext: modelContext)

        try deleteAll(BudgetPresetLink.self, modelContext: modelContext)
        try deleteAll(BudgetCardLink.self, modelContext: modelContext)
        try deleteAll(BudgetCategoryLimit.self, modelContext: modelContext)

        try deleteAll(Budget.self, modelContext: modelContext)
        try deleteAll(Card.self, modelContext: modelContext)
        try deleteAll(Category.self, modelContext: modelContext)
        try deleteAll(Workspace.self, modelContext: modelContext)

        try modelContext.save()
    }

    // MARK: - Private

    private static func deleteAll<T: PersistentModel>(
        _ type: T.Type,
        modelContext: ModelContext
    ) throws {
        let descriptor = FetchDescriptor<T>()
        let items = try modelContext.fetch(descriptor)
        for item in items {
            modelContext.delete(item)
        }
    }
}
