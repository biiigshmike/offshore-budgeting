//
//  ExpenseCSVImportModels.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/25/26.
//

import Foundation

enum ExpenseCSVImportBucket: String, Hashable {
    case ready
    case possibleMatch
    case payment
    case possibleDuplicate
    case needsMoreData
}

enum ExpenseCSVImportKind: String, Hashable {
    case expense
    case income
}

struct ExpenseCSVImportRow: Identifiable {
    let id: UUID = UUID()

    // Original
    let sourceLine: Int
    let originalDateText: String
    let originalDescriptionText: String
    let originalMerchantText: String?
    let originalAmountText: String
    let originalCategoryText: String?

    // Matching keys (stable, noise-stripped)
    let sourceMerchantKey: String
    let descriptionMerchantKey: String

    // Parsed / proposed
    var finalDate: Date
    var finalMerchant: String
    var finalAmount: Double
    var kind: ExpenseCSVImportKind

    // Matching
    var suggestedCategory: Category?
    var suggestedConfidence: Double
    var matchReason: String

    // Category selection (expenses only)
    var selectedCategory: Category?
    var selectedAllocationAccount: AllocationAccount? = nil
    var allocationAmountText: String = ""

    // Learning
    var rememberMapping: Bool = false

    // Import mode enforcement
    var blockedReason: String? = nil

    // Flags
    var includeInImport: Bool
    var isDuplicateHint: Bool
    var bucket: ExpenseCSVImportBucket

    var isBlocked: Bool {
        guard let blockedReason else { return false }
        return !blockedReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isMissingRequiredData: Bool {
        if finalMerchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if kind == .expense, selectedCategory == nil { return true }
        return false
    }

    func parsedAllocationAmount(cappedTo total: Double) -> Double? {
        let trimmed = allocationAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let parsed = CurrencyFormatter.parseAmount(trimmed), parsed > 0 else { return nil }
        return AllocationLedgerService.cappedAllocationAmount(parsed, expenseAmount: total)
    }

    mutating func recomputeBucket() {
        if isBlocked {
            includeInImport = false
            return
        }

        // Keep bucket stable while the user edits fields to avoid list shuffling.
        // Use `isMissingRequiredData` + `includeInImport` to control what can be imported.
        if finalMerchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            includeInImport = false
            return
        }

        if kind == .expense {
            if selectedCategory == nil {
                includeInImport = false
                return
            }
        }

        if isDuplicateHint {
            bucket = .possibleDuplicate
            includeInImport = false
            return
        }

        // Do not auto-change bucket or include flags here beyond duplicate/missing-required-data behavior.
    }
}
