//
//  CurrencyFormatter.swift
//  OffshoreBudgeting
//
//  Centralized currency formatting using:
//  - User-selected currency code (Settings > General)
//  - User locale (comma vs dot separators, symbol placement, spacing, etc.)
//  - Currency minor units (JPY = 0, USD/EUR = 2, etc.)
//

import Foundation
import SwiftUI

enum CurrencyFormatter {

    // MARK: - Settings Keys

    private static let currencyCodeKey: String = "general_currencyCode"
    private static let systemCurrencyTag: String = "SYSTEM"
    private static let fallbackCurrencyCode: String = "USD"

    // MARK: - Public: Currency Code

    static var currencyCode: String {
        let stored = UserDefaults.standard.string(forKey: currencyCodeKey)

        // Settings can store a sentinel value meaning "use system currency".
        if stored == systemCurrencyTag {
            return Locale.current.currency?.identifier ?? fallbackCurrencyCode
        }

        if let stored, !stored.isEmpty {
            return stored
        }

        return fallbackCurrencyCode
    }

    // MARK: - Public: SwiftUI Display Style

    /// SwiftUI-friendly style for `Text(amount, format: ...)`.
    /// Respects Locale.current and currency minor units.
    static func currencyStyle() -> FloatingPointFormatStyle<Double>.Currency {
        let digits = currencyFractionDigits()
        return .currency(code: currencyCode)
            .precision(.fractionLength(digits))
    }

    // MARK: - Public: Display String

    /// String output for places you need a preformatted string (alerts, accessibility, concatenation, etc.)
    /// Uses Locale.current, respects minor units.
    static func string(from value: Double) -> String {
        let formatter = makeCurrencyFormatter()
        if let formatted = formatter.string(from: NSNumber(value: value)) {
            return formatted
        }

        // Extremely defensive fallback; avoids `String(Double)` which can yield "0.0".
        return value.formatted(currencyStyle())
    }

    // MARK: - Public: Editing String

    /// Produces a locale-correct string for seeding an amount TextField.
    /// Example:
    /// - en_US + USD -> "1.00"
    /// - fr_FR + EUR -> "1,00"
    /// - ja_JP + JPY -> "1"
    ///
    /// This is intentionally *decimal style* (no currency symbol) so it works well in input fields.
    static func editingString(from value: Double) -> String {
        let digits = currencyFractionDigits()

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits

        if let formatted = formatter.string(from: NSNumber(value: value)) {
            return formatted
        }

        // Extremely defensive fallback; avoids `String(Double)` which can yield "0.0".
        return value.formatted(.number.precision(.fractionLength(digits)))
    }

    // MARK: - Public: Parse Amount

    /// Parses a user-typed amount in a locale-aware way.
    /// Accepts both:
    /// - decimal input ("1.25" or "1,25" depending on locale)
    /// - currency input with symbols ("$1.25", "1,25 €", etc.)
    ///
    /// Returns nil if the value cannot be parsed.
    static func parseAmount(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1) Try decimal parsing first (best for text fields)
        let decimalFormatter = NumberFormatter()
        decimalFormatter.numberStyle = .decimal
        decimalFormatter.locale = .current

        if let number = decimalFormatter.number(from: trimmed) {
            return number.doubleValue
        }

        // 2) Try currency parsing (handles symbols and trailing/leading currency markers)
        let currencyFormatter = makeCurrencyFormatter()
        if let number = currencyFormatter.number(from: trimmed) {
            return number.doubleValue
        }

        return nil
    }

    // MARK: - Internals

    private static func makeCurrencyFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .current
        formatter.currencyCode = currencyCode
        return formatter
    }

    /// Determine the correct number of fraction digits for the selected currency.
    /// Falls back to NumberFormatter defaults if needed.
    private static func currencyFractionDigits() -> Int {
        // Use NumberFormatter defaults for the currency code (this respects minor units)
        let formatter = makeCurrencyFormatter()

        // In practice, this returns 2 for USD/EUR, 0 for JPY, etc.
        // We pick maxFractionDigits because currency formatters are typically fixed-width per currency.
        let digits = formatter.maximumFractionDigits

        // Safety clamp
        return max(0, min(digits, 6))
    }
}
