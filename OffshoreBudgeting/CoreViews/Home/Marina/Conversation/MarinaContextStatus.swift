import Foundation

nonisolated enum MarinaContextStatus: String, Codable, Sendable {
    case approaching, reached

    static func measured(tokens: Int, capacity: Int) -> Self? {
        guard capacity > 0 else { return nil }
        if tokens >= capacity { return .reached }
        return Double(tokens) / Double(capacity) >= 0.75 ? .approaching : nil
    }

    static func status(in answers: [HomeAnswer]) -> Self? {
        if answers.contains(where: { $0.contextStatus == .reached || $0.responseState == .contextLimit }) {
            return .reached
        }
        return answers.contains(where: { $0.contextStatus == .approaching }) ? .approaching : nil
    }

    var message: String {
        switch self {
        case .approaching: "This chat is getting close to its limit. Start a new chat soon to keep talking with Marina."
        case .reached: "This chat has reached its limit. Start a new chat to keep talking with Marina. Your conversation is saved."
        }
    }
}
