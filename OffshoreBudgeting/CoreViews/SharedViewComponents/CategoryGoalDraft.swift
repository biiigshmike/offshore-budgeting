import Foundation

/// Editable goal values stay outside SwiftData until the enclosing form is saved.
struct CategoryGoalDraft: Equatable {
    var minimumText: String = ""
    var maximumText: String = ""

    init(minimumText: String = "", maximumText: String = "") {
        self.minimumText = minimumText
        self.maximumText = maximumText
    }

    init(minimum: Double?, maximum: Double?) {
        minimumText = minimum.map { CurrencyFormatter.editingString(from: $0) } ?? ""
        maximumText = maximum.map { CurrencyFormatter.editingString(from: $0) } ?? ""
    }

    var minimum: Double? { CurrencyFormatter.parseAmount(minimumText) }
    var maximum: Double? { CurrencyFormatter.parseAmount(maximumText) }

    var hasValues: Bool {
        !minimumText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !maximumText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var validationMessage: String? {
        for text in [minimumText, maximumText] where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let amount = CurrencyFormatter.parseAmount(text), amount.isFinite, amount >= 0 else {
                return String(localized: "Enter a valid goal amount of 0 or greater.")
            }
        }
        if let minimum, let maximum, minimum > maximum {
            return String(localized: "The minimum goal must be less than or equal to the maximum goal.")
        }
        return nil
    }

    var isValid: Bool { validationMessage == nil }
}
