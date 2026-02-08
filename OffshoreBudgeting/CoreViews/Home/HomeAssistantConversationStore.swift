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
    private let greetedPersonasKeyPrefix: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        storageKeyPrefix: String = "home.assistant.answers",
        greetedPersonasKeyPrefix: String = "home.assistant.greetedPersonas"
    ) {
        self.userDefaults = userDefaults
        self.storageKeyPrefix = storageKeyPrefix
        self.greetedPersonasKeyPrefix = greetedPersonasKeyPrefix
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

    func hasGreetedPersona(_ personaID: HomeAssistantPersonaID, workspaceID: UUID) -> Bool {
        loadGreetedPersonas(workspaceID: workspaceID).contains(personaID)
    }

    func markPersonaAsGreeted(_ personaID: HomeAssistantPersonaID, workspaceID: UUID) {
        var personas = loadGreetedPersonas(workspaceID: workspaceID)
        personas.insert(personaID)
        saveGreetedPersonas(personas, workspaceID: workspaceID)
    }

    // MARK: - Helpers

    private func storageKey(for workspaceID: UUID) -> String {
        "\(storageKeyPrefix).\(workspaceID.uuidString)"
    }

    private func greetedPersonasKey(for workspaceID: UUID) -> String {
        "\(greetedPersonasKeyPrefix).\(workspaceID.uuidString)"
    }

    private func loadGreetedPersonas(workspaceID: UUID) -> Set<HomeAssistantPersonaID> {
        let key = greetedPersonasKey(for: workspaceID)
        guard let rawValues = userDefaults.array(forKey: key) as? [String] else { return [] }

        let personas = rawValues.compactMap(HomeAssistantPersonaID.init(rawValue:))
        return Set(personas)
    }

    private func saveGreetedPersonas(_ personas: Set<HomeAssistantPersonaID>, workspaceID: UUID) {
        let key = greetedPersonasKey(for: workspaceID)
        userDefaults.set(personas.map(\.rawValue).sorted(), forKey: key)
    }

    private func trimmed(_ answers: [HomeAnswer]) -> [HomeAnswer] {
        guard answers.count > Self.maxStoredAnswers else { return answers }
        return Array(answers.suffix(Self.maxStoredAnswers))
    }
}
