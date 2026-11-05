import Foundation

/// Transient notification context, never a financial record or proof of a purchase.
struct ExcursionSuggestion: Codable, Equatable, Identifiable, Sendable {
    struct Candidate: Codable, Equatable, Identifiable, Sendable {
        let id: String
        let name: String
    }

    let id: String
    let candidates: [Candidate]
    let workspaceID: UUID
    let sessionID: String

    init(id: String = UUID().uuidString, candidates: [Candidate], workspaceID: UUID, sessionID: String) {
        self.id = id
        self.candidates = Array(candidates.prefix(5))
        self.workspaceID = workspaceID
        self.sessionID = sessionID
    }

    var encoded: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ string: String) -> Self? {
        guard let data = string.data(using: .utf8),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              !value.id.isEmpty, !value.sessionID.isEmpty,
              !value.candidates.isEmpty, value.candidates.count <= 5,
              Set(value.candidates.map(\.id)).count == value.candidates.count,
              value.candidates.allSatisfy({ !$0.id.isEmpty && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return nil }
        return value
    }
}
