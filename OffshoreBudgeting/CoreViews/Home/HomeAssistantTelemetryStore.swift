//
//  HomeAssistantTelemetryStore.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/8/26.
//

import Foundation

// MARK: - Telemetry Models

enum HomeAssistantTelemetryOutcome: String, Codable, Equatable {
    case resolved
    case clarification
    case unresolved
}

struct HomeAssistantTelemetryEvent: Codable, Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let prompt: String
    let normalizedPrompt: String
    let outcome: HomeAssistantTelemetryOutcome
    let source: String?
    let intentRawValue: String?
    let confidenceRawValue: String?
    let targetName: String?
    let notes: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        prompt: String,
        normalizedPrompt: String,
        outcome: HomeAssistantTelemetryOutcome,
        source: String? = nil,
        intentRawValue: String? = nil,
        confidenceRawValue: String? = nil,
        targetName: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.prompt = prompt
        self.normalizedPrompt = normalizedPrompt
        self.outcome = outcome
        self.source = source
        self.intentRawValue = intentRawValue
        self.confidenceRawValue = confidenceRawValue
        self.targetName = targetName
        self.notes = notes
    }
}

// MARK: - Telemetry Store

final class HomeAssistantTelemetryStore {
    static let maxStoredEvents = 300

    private let userDefaults: UserDefaults
    private let storageKeyPrefix: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        storageKeyPrefix: String = "home.assistant.telemetry"
    ) {
        self.userDefaults = userDefaults
        self.storageKeyPrefix = storageKeyPrefix
    }

    func loadEvents(workspaceID: UUID) -> [HomeAssistantTelemetryEvent] {
        let key = storageKey(for: workspaceID)
        guard let data = userDefaults.data(forKey: key) else { return [] }

        do {
            return try decoder.decode([HomeAssistantTelemetryEvent].self, from: data)
        } catch {
            return []
        }
    }

    func appendEvent(_ event: HomeAssistantTelemetryEvent, workspaceID: UUID) {
        var events = loadEvents(workspaceID: workspaceID)
        events.append(event)
        saveEvents(events, workspaceID: workspaceID)
    }

    func clearEvents(workspaceID: UUID) {
        userDefaults.removeObject(forKey: storageKey(for: workspaceID))
    }

    // MARK: - Helpers

    private func saveEvents(_ events: [HomeAssistantTelemetryEvent], workspaceID: UUID) {
        let trimmed = trim(events)
        let key = storageKey(for: workspaceID)

        do {
            let data = try encoder.encode(trimmed)
            userDefaults.set(data, forKey: key)
        } catch {
            return
        }
    }

    private func storageKey(for workspaceID: UUID) -> String {
        "\(storageKeyPrefix).\(workspaceID.uuidString)"
    }

    private func trim(_ events: [HomeAssistantTelemetryEvent]) -> [HomeAssistantTelemetryEvent] {
        guard events.count > Self.maxStoredEvents else { return events }
        return Array(events.suffix(Self.maxStoredEvents))
    }
}
