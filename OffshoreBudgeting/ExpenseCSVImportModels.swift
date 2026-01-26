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
    let originalAmountText: String
    let originalCategoryText: String?

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

    // Learning
    var rememberMapping: Bool = false

    // Flags
    var includeInImport: Bool
    var isDuplicateHint: Bool
    var bucket: ExpenseCSVImportBucket

    mutating func recomputeBucket() {
        if finalMerchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bucket = .needsMoreData
            includeInImport = false
            return
        }

        if kind == .expense {
            if selectedCategory == nil {
                bucket = .needsMoreData
                includeInImport = false
                return
            }
        }

        if isDuplicateHint {
            bucket = .possibleDuplicate
            includeInImport = false
            return
        }

        if kind == .income {
            bucket = .payment
            includeInImport = true
            return
        }

        // Expense with a category and not duplicate
        // The mapper sets ready vs possibleMatch based on confidence.
    }
}
