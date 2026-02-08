//
//  HomeAssistantConversationStore.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/8/26.
//

import Foundation

// MARK: - Conversation Store

final class HomeAssistantConversationStore {
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

    // MARK: - Helpers

    private func storageKey(for workspaceID: UUID) -> String {
        "\(storageKeyPrefix).\(workspaceID.uuidString)"
    }

    private func trimmed(_ answers: [HomeAnswer]) -> [HomeAnswer] {
        guard answers.count > Self.maxStoredAnswers else { return answers }
        return Array(answers.suffix(Self.maxStoredAnswers))
    }
}
