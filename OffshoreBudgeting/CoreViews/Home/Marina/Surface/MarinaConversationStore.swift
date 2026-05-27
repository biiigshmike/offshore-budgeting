//
//  MarinaConversationStore.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/8/26.
//

import Foundation

enum MarinaConversationDisplayRole: Equatable {
    case user
    case assistant
}

struct MarinaConversationDisplayMessage: Identifiable, Equatable {
    let id: String
    let role: MarinaConversationDisplayRole
    let prompt: String?
    let answer: HomeAnswer?
    let generatedAt: Date
}

enum MarinaConversationDisplayAdapter {
    static func messages(from answers: [HomeAnswer]) -> [MarinaConversationDisplayMessage] {
        answers.flatMap { answer -> [MarinaConversationDisplayMessage] in
            let trimmedPrompt = answer.userPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let assistantMessage = MarinaConversationDisplayMessage(
                id: "assistant-\(answer.id.uuidString)",
                role: .assistant,
                prompt: nil,
                answer: answer,
                generatedAt: answer.generatedAt
            )

            guard trimmedPrompt.isEmpty == false else {
                return [assistantMessage]
            }

            return [
                MarinaConversationDisplayMessage(
                    id: "user-\(answer.id.uuidString)",
                    role: .user,
                    prompt: trimmedPrompt,
                    answer: nil,
                    generatedAt: answer.generatedAt
                ),
                assistantMessage
            ]
        }
    }
}

// MARK: - Conversation Store

final class MarinaConversationStore {
    static let maxStoredAnswers = 50

    private let userDefaults: UserDefaults
    private let storageKeyPrefix: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        storageKeyPrefix: String = "home.assistant.answers"
    ) {
        self.userDefaults = userDefaults
        self.storageKeyPrefix = storageKeyPrefix
    }

    func loadAnswers(workspaceID: UUID) -> [HomeAnswer] {
        let key = storageKey(for: workspaceID)
        guard let data = userDefaults.data(forKey: key) else { return [] }

        do {
            return try decoder.decode([HomeAnswer].self, from: data)
        } catch {
            return []
        }
    }

    func saveAnswers(_ answers: [HomeAnswer], workspaceID: UUID) {
        let trimmedAnswers = trimmed(answers)
        let key = storageKey(for: workspaceID)

        do {
            let data = try encoder.encode(trimmedAnswers)
            userDefaults.set(data, forKey: key)
        } catch {
            return
        }
    }

    func loadLastCheckIn(workspaceID: UUID) -> Date? {
        userDefaults.object(forKey: checkInStorageKey(for: workspaceID)) as? Date
    }

    func saveLastCheckIn(_ date: Date, workspaceID: UUID) {
        userDefaults.set(date, forKey: checkInStorageKey(for: workspaceID))
    }

    // MARK: - Helpers

    private func storageKey(for workspaceID: UUID) -> String {
        "\(storageKeyPrefix).\(workspaceID.uuidString)"
    }

    private func checkInStorageKey(for workspaceID: UUID) -> String {
        "\(storageKeyPrefix).checkIn.\(workspaceID.uuidString)"
    }

    private func trimmed(_ answers: [HomeAnswer]) -> [HomeAnswer] {
        guard answers.count > Self.maxStoredAnswers else { return answers }
        return Array(answers.suffix(Self.maxStoredAnswers))
    }
}
