import Foundation

nonisolated enum MarinaContextStatus: String, Codable, Sendable {
    case approaching, reached

    static func measured(tokens: Int, capacity: Int) -> Self? {
        guard capacity > 0 else { return nil }
        if tokens >= capacity { return .reached }
        return Double(tokens) / Double(capacity) >= 0.75 ? .approaching : nil
    }

    static func status(in answers: [HomeAnswer]) -> Self? {
        // Compatibility-only saved markers describe discarded model sessions.
        // They must never prevent another request in this saved chat.
        nil
    }

    var message: String {
        switch self {
        case .approaching: "Marina can refresh its working context while keeping this chat saved."
        case .reached: "Try a shorter question or a narrower date range. You can keep using this chat."
        }
    }
}
