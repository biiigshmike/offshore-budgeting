import Foundation

struct MarinaClarificationDecision: Equatable {
    let reasons: [MarinaClarificationReason]
    let subtitle: String
    let suggestions: [MarinaSuggestion]
    let shouldRunBestEffort: Bool
}

typealias MarinaClarificationPlan = MarinaClarificationDecision

enum MarinaClarificationReason: String, CaseIterable, Hashable {
    case missingDate
    case missingComparisonDate
    case missingCategoryTarget
    case missingCardTarget
    case missingIncomeSourceTarget
    case missingMerchantTarget
    case broadPrompt
    case lowConfidenceLanguage
}
