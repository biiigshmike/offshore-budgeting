import Foundation

/// User-visible lifecycle only; no inferred conversational or query state.
enum MarinaResponseState: String, Codable, Equatable, Sendable {
    case thinking, readingRecords, readingExpenses, readingIncome, readingBudget, readingAccounts
    case responding, complete, cancelled, unavailable, invalidRequest, contextLimit, generationFailed

    var isActive: Bool {
        switch self {
        case .thinking, .readingRecords, .readingExpenses, .readingIncome, .readingBudget, .readingAccounts, .responding: true
        default: false
        }
    }
    var canRetry: Bool {
        switch self {
        case .cancelled, .unavailable, .invalidRequest, .contextLimit, .generationFailed: true
        default: false
        }
    }
    var message: String {
        switch self {
        case .thinking: "Thinking…"
        case .readingRecords: "Finding matching records…"
        case .readingExpenses: "Looking up expenses…"
        case .readingIncome: "Looking up income…"
        case .readingBudget: "Checking your budget…"
        case .readingAccounts: "Looking up account balances…"
        case .responding: "Preparing your answer…"
        case .complete: ""
        case .cancelled: "Response stopped."
        case .unavailable: "Apple Intelligence is unavailable right now."
        case .invalidRequest: "I couldn’t apply the requested filters. Please retry or clarify what you want to include."
        case .contextLimit: "This conversation reached the model’s context limit. Please start a new chat."
        case .generationFailed: "I couldn’t finish the explanation. You can retry this response."
        }
    }
}
