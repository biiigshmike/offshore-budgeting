import Foundation

@available(iOS 26.0, macOS 26.0, *)
struct MarinaMessage: Codable, Identifiable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }

    var id = UUID()
    var role: Role
    var text: String
    var date = Date.now
    var results: [MarinaResult] = []
    var kind: MarinaReplyKind? = nil
}

@available(iOS 26.0, macOS 26.0, *)
struct MarinaHistoryPayload: Codable, Sendable {
    var version = 1
    var messages: [MarinaMessage]

    static func decode(_ data: Data) throws -> Self {
        if data.isEmpty { return Self(messages: []) }
        let payload = try JSONDecoder().decode(Self.self, from: data)
        guard payload.version == 1 else { throw MarinaHistoryError.unsupportedVersion }
        return payload
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct MarinaFollowUpPayload: Codable, Sendable {
    var version = 1
    var summary: String

    static func decode(_ data: Data) throws -> Self {
        if data.isEmpty { return Self(summary: "") }
        let payload = try JSONDecoder().decode(Self.self, from: data)
        guard payload.version == 1 else { throw MarinaHistoryError.unsupportedVersion }
        return payload
    }
}

@available(iOS 26.0, macOS 26.0, *)
enum MarinaHistoryError: LocalizedError {
    case unsupportedVersion

    var errorDescription: String? {
        "This conversation uses an unsupported history format. It has been preserved. Start a new chat to continue."
    }
}
