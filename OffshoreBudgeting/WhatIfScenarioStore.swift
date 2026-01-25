//
//  WhatIfScenarioStore.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/25/26.
//

import Foundation

struct WhatIfScenarioStore {
    
    // MARK: - Notifications

    /// Posted whenever pinned global scenario IDs change for a workspace.
    /// Views can observe this to refresh UI without requiring an app restart.
    static func pinnedGlobalScenariosDidChangeName(workspaceID: UUID) -> Notification.Name {
        Notification.Name("whatIfPinnedGlobalScenariosDidChange_\(workspaceID.uuidString)")
    }

    // MARK: - Config

    private let workspaceID: UUID
    private let calendar: Calendar
    private let maxScenariosPerRange: Int

    init(workspaceID: UUID, calendar: Calendar = .current, maxScenariosPerRange: Int = 12) {
        self.workspaceID = workspaceID
        self.calendar = calendar
        self.maxScenariosPerRange = max(1, maxScenariosPerRange)
    }

    // MARK: - Public Models

    struct ScenarioInfo: Codable, Identifiable, Equatable {
        var id: UUID
        var name: String
        var lastAccessed: Double
        var createdAt: Double
    }

    // MARK: - Keys (range-based)

    private func rangeKey(startDate: Date, endDate: Date) -> String {
        let s = calendar.startOfDay(for: startDate)
        let e = calendar.startOfDay(for: endDate)

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyyMMdd"

        return "\(formatter.string(from: s))_\(formatter.string(from: e))"
    }

    private func scenariosIndexKey(rangeKey: String) -> String {
        "home_whatIfScenarioIndex_\(workspaceID.uuidString)_\(rangeKey)"
    }

    private func selectedScenarioKey(rangeKey: String) -> String {
        "home_whatIfScenarioSelected_\(workspaceID.uuidString)_\(rangeKey)"
    }

    private func payloadKey(rangeKey: String, scenarioID: UUID) -> String {
        "home_whatIfScenario_\(workspaceID.uuidString)_\(rangeKey)_\(scenarioID.uuidString)"
    }

    // MARK: - Index (range-based)

    func listScenarios(startDate: Date, endDate: Date) -> [ScenarioInfo] {
        let rk = rangeKey(startDate: startDate, endDate: endDate)
        var items = loadIndex(rangeKey: rk)
        items.sort { $0.lastAccessed > $1.lastAccessed }
        return items
    }

    func loadSelectedScenarioID(startDate: Date, endDate: Date) -> UUID? {
        let rk = rangeKey(startDate: startDate, endDate: endDate)
        guard let raw = UserDefaults.standard.string(forKey: selectedScenarioKey(rangeKey: rk)) else { return nil }
        return UUID(uuidString: raw)
    }

    func setSelectedScenarioID(_ scenarioID: UUID, startDate: Date, endDate: Date) {
        let rk = rangeKey(startDate: startDate, endDate: endDate)
        UserDefaults.standard.set(scenarioID.uuidString, forKey: selectedScenarioKey(rangeKey: rk))
        bumpLastAccessed(scenarioID: scenarioID, rangeKey: rk)
    }

    // MARK: - CRUD (range-based)

    func createScenario(name: String, seed: [UUID: Double], startDate: Date, endDate: Date) -> ScenarioInfo {
        let rk = rangeKey(startDate: startDate, endDate: endDate)
        let now = Date().timeIntervalSince1970

        let info = ScenarioInfo(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Scenario" : name,
            lastAccessed: now,
            createdAt: now
        )

        savePayload(seed, scenarioID: info.id, rangeKey: rk)
        upsertIndex(info, rangeKey: rk)
        pruneIfNeeded(rangeKey: rk)

        UserDefaults.standard.set(info.id.uuidString, forKey: selectedScenarioKey(rangeKey: rk))
        return info
    }

    func renameScenario(scenarioID: UUID, newName: String, startDate: Date, endDate: Date) {
        let rk = rangeKey(startDate: startDate, endDate: endDate)
        var items = loadIndex(rangeKey: rk)
        guard let idx = items.firstIndex(where: { $0.id == scenarioID }) else { return }

        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        items[idx].name = trimmed.isEmpty ? items[idx].name : trimmed
        saveIndex(items, rangeKey: rk)
    }

    func duplicateScenario(scenarioID: UUID, newName: String, startDate: Date, endDate: Date) -> ScenarioInfo? {
        _ = rangeKey(startDate: startDate, endDate: endDate)
        guard let existing = loadScenario(scenarioID: scenarioID, startDate: startDate, endDate: endDate) else { return nil }

        let baseName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = baseName.isEmpty ? "Copy" : baseName
        return createScenario(name: name, seed: existing, startDate: startDate, endDate: endDate)
    }

    func deleteScenario(scenarioID: UUID, startDate: Date, endDate: Date) {
        let rk = rangeKey(startDate: startDate, endDate: endDate)

        UserDefaults.standard.removeObject(forKey: payloadKey(rangeKey: rk, scenarioID: scenarioID))

        var items = loadIndex(rangeKey: rk)
        items.removeAll { $0.id == scenarioID }
        saveIndex(items, rangeKey: rk)

        if loadSelectedScenarioID(startDate: startDate, endDate: endDate) == scenarioID {
            let next = items.sorted { $0.lastAccessed > $1.lastAccessed }.first?.id
            if let next {
                UserDefaults.standard.set(next.uuidString, forKey: selectedScenarioKey(rangeKey: rk))
            } else {
                UserDefaults.standard.removeObject(forKey: selectedScenarioKey(rangeKey: rk))
            }
        }
    }

    // MARK: - Payload (range-based)

    func loadScenario(scenarioID: UUID, startDate: Date, endDate: Date) -> [UUID: Double]? {
        let rk = rangeKey(startDate: startDate, endDate: endDate)
        bumpLastAccessed(scenarioID: scenarioID, rangeKey: rk)

        guard let data = UserDefaults.standard.data(forKey: payloadKey(rangeKey: rk, scenarioID: scenarioID)) else { return nil }
        let decoded = try? JSONDecoder().decode(ScenarioPayload.self, from: data)
        return decoded?.scenarioByCategoryID
    }

    func saveScenario(_ scenarioByCategoryID: [UUID: Double], scenarioID: UUID, startDate: Date, endDate: Date) {
        let rk = rangeKey(startDate: startDate, endDate: endDate)
        savePayload(scenarioByCategoryID, scenarioID: scenarioID, rangeKey: rk)
        bumpLastAccessed(scenarioID: scenarioID, rangeKey: rk)
        pruneIfNeeded(rangeKey: rk)
    }

    // MARK: - Private (range-based)

    private func loadIndex(rangeKey: String) -> [ScenarioInfo] {
        guard let data = UserDefaults.standard.data(forKey: scenariosIndexKey(rangeKey: rangeKey)) else { return [] }
        return (try? JSONDecoder().decode([ScenarioInfo].self, from: data)) ?? []
    }

    private func saveIndex(_ items: [ScenarioInfo], rangeKey: String) {
        let data = (try? JSONEncoder().encode(items)) ?? Data()
        UserDefaults.standard.set(data, forKey: scenariosIndexKey(rangeKey: rangeKey))
    }

    private func upsertIndex(_ info: ScenarioInfo, rangeKey: String) {
        var items = loadIndex(rangeKey: rangeKey)
        if let idx = items.firstIndex(where: { $0.id == info.id }) {
            items[idx] = info
        } else {
            items.append(info)
        }
        saveIndex(items, rangeKey: rangeKey)
    }

    private func bumpLastAccessed(scenarioID: UUID, rangeKey: String) {
        var items = loadIndex(rangeKey: rangeKey)
        guard let idx = items.firstIndex(where: { $0.id == scenarioID }) else { return }
        items[idx].lastAccessed = Date().timeIntervalSince1970
        saveIndex(items, rangeKey: rangeKey)
    }

    private func pruneIfNeeded(rangeKey: String) {
        var items = loadIndex(rangeKey: rangeKey)
        guard items.count > maxScenariosPerRange else { return }

        items.sort { $0.lastAccessed > $1.lastAccessed }
        let keep = Array(items.prefix(maxScenariosPerRange))
        let drop = Array(items.dropFirst(maxScenariosPerRange))

        for item in drop {
            UserDefaults.standard.removeObject(forKey: payloadKey(rangeKey: rangeKey, scenarioID: item.id))
        }

        saveIndex(keep, rangeKey: rangeKey)
    }

    private func savePayload(_ scenarioByCategoryID: [UUID: Double], scenarioID: UUID, rangeKey: String) {
        let payload = ScenarioPayload(
            scenarioID: scenarioID,
            rangeKey: rangeKey,
            scenarioByCategoryID: scenarioByCategoryID
        )

        let data = (try? JSONEncoder().encode(payload)) ?? Data()
        UserDefaults.standard.set(data, forKey: payloadKey(rangeKey: rangeKey, scenarioID: scenarioID))
    }

    // MARK: - Global Scenarios (per workspace)

    // Global scenarios store "overrides" by category.
    // When applying to a date range:
    // scenarioAmount = overrideAmount ?? baselineActualAmount
    struct GlobalScenarioInfo: Codable, Identifiable, Equatable {
        var id: UUID
        var name: String
        var lastAccessed: Double
        var createdAt: Double
    }

    private func globalIndexKey() -> String {
        "home_whatIfGlobalScenarioIndex_\(workspaceID.uuidString)"
    }

    private func globalSelectedKey() -> String {
        "home_whatIfGlobalScenarioSelected_\(workspaceID.uuidString)"
    }

    private func globalPinnedKey() -> String {
        "home_whatIfGlobalScenarioPinned_\(workspaceID.uuidString)"
    }

    private func globalPinnedListKey() -> String {
        "home_whatIfGlobalScenarioPinnedList_\(workspaceID.uuidString)"
    }

    private func globalPayloadKey(scenarioID: UUID) -> String {
        "home_whatIfGlobalScenario_\(workspaceID.uuidString)_\(scenarioID.uuidString)"
    }

    func listGlobalScenarios() -> [GlobalScenarioInfo] {
        var items = loadGlobalIndex()
        items.sort { $0.lastAccessed > $1.lastAccessed }
        return items
    }

    func loadSelectedGlobalScenarioID() -> UUID? {
        guard let raw = UserDefaults.standard.string(forKey: globalSelectedKey()) else { return nil }
        return UUID(uuidString: raw)
    }

    func setSelectedGlobalScenarioID(_ scenarioID: UUID) {
        UserDefaults.standard.set(scenarioID.uuidString, forKey: globalSelectedKey())
        bumpGlobalLastAccessed(scenarioID: scenarioID)
    }

    // MARK: - Pinned scenarios (GLOBAL)

    /// New behavior: multiple pinned scenarios.
    /// Migration: if the legacy single pinned ID exists, convert it into a 1-item array.
    func loadPinnedGlobalScenarioIDs() -> [UUID] {
        if let data = UserDefaults.standard.data(forKey: globalPinnedListKey()),
           let raw = try? JSONDecoder().decode([String].self, from: data)
        {
            return raw.compactMap { UUID(uuidString: $0) }
        }

        // Migration path (legacy string)
        if let legacy = UserDefaults.standard.string(forKey: globalPinnedKey()),
           let id = UUID(uuidString: legacy)
        {
            let migrated: [UUID] = [id]
            setPinnedGlobalScenarioIDs(migrated)
            UserDefaults.standard.removeObject(forKey: globalPinnedKey())
            return migrated
        }

        return []
    }

    func setPinnedGlobalScenarioIDs(_ scenarioIDs: [UUID]) {
        let raw = scenarioIDs.map { $0.uuidString }
        let data = (try? JSONEncoder().encode(raw)) ?? Data()
        UserDefaults.standard.set(data, forKey: globalPinnedListKey())

        NotificationCenter.default.post(
            name: Self.pinnedGlobalScenariosDidChangeName(workspaceID: workspaceID),
            object: nil
        )
    }


    func isGlobalScenarioPinned(_ scenarioID: UUID) -> Bool {
        loadPinnedGlobalScenarioIDs().contains(scenarioID)
    }

    func setGlobalScenarioPinned(_ scenarioID: UUID, isPinned: Bool) {
        var current = loadPinnedGlobalScenarioIDs()
        if isPinned {
            if current.contains(scenarioID) == false {
                current.append(scenarioID)
            }
        } else {
            current.removeAll { $0 == scenarioID }
        }
        setPinnedGlobalScenarioIDs(current)
    }

    func createGlobalScenario(name: String, overrides: [UUID: Double] = [:]) -> GlobalScenarioInfo {
        let now = Date().timeIntervalSince1970
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        let info = GlobalScenarioInfo(
            id: UUID(),
            name: trimmed.isEmpty ? "Scenario" : trimmed,
            lastAccessed: now,
            createdAt: now
        )

        saveGlobalPayload(overrides, scenarioID: info.id)
        upsertGlobalIndex(info)
        UserDefaults.standard.set(info.id.uuidString, forKey: globalSelectedKey())
        return info
    }

    func renameGlobalScenario(scenarioID: UUID, newName: String) {
        var items = loadGlobalIndex()
        guard let idx = items.firstIndex(where: { $0.id == scenarioID }) else { return }

        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        items[idx].name = trimmed.isEmpty ? items[idx].name : trimmed
        saveGlobalIndex(items)
    }

    func duplicateGlobalScenario(scenarioID: UUID, newName: String) -> GlobalScenarioInfo? {
        guard let existing = loadGlobalScenario(scenarioID: scenarioID) else { return nil }

        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Copy" : trimmed
        return createGlobalScenario(name: name, overrides: existing)
    }

    func deleteGlobalScenario(scenarioID: UUID) {
        UserDefaults.standard.removeObject(forKey: globalPayloadKey(scenarioID: scenarioID))

        var items = loadGlobalIndex()
        items.removeAll { $0.id == scenarioID }
        saveGlobalIndex(items)

        // selection
        if loadSelectedGlobalScenarioID() == scenarioID {
            let next = items.sorted { $0.lastAccessed > $1.lastAccessed }.first?.id
            if let next {
                UserDefaults.standard.set(next.uuidString, forKey: globalSelectedKey())
            } else {
                UserDefaults.standard.removeObject(forKey: globalSelectedKey())
            }
        }

        // pinned
        if isGlobalScenarioPinned(scenarioID) {
            setGlobalScenarioPinned(scenarioID, isPinned: false)
        }
    }

    func loadGlobalScenario(scenarioID: UUID) -> [UUID: Double]? {
        bumpGlobalLastAccessed(scenarioID: scenarioID)

        guard let data = UserDefaults.standard.data(forKey: globalPayloadKey(scenarioID: scenarioID)) else { return nil }
        let decoded = try? JSONDecoder().decode(GlobalScenarioPayload.self, from: data)
        return decoded?.overridesByCategoryID
    }

    func saveGlobalScenario(_ overridesByCategoryID: [UUID: Double], scenarioID: UUID) {
        saveGlobalPayload(overridesByCategoryID, scenarioID: scenarioID)
        bumpGlobalLastAccessed(scenarioID: scenarioID)
    }

    // Apply global overrides to a baseline for a specific date range
    func applyGlobalScenario(overrides: [UUID: Double], baselineByCategoryID: [UUID: Double], categories: [UUID]) -> [UUID: Double] {
        var result: [UUID: Double] = [:]
        result.reserveCapacity(categories.count)

        for id in categories {
            let baseline = baselineByCategoryID[id, default: 0]
            let override = overrides[id]
            result[id] = max(0, override ?? baseline)
        }

        return result
    }

    // MARK: - Private (global)

    private func loadGlobalIndex() -> [GlobalScenarioInfo] {
        guard let data = UserDefaults.standard.data(forKey: globalIndexKey()) else { return [] }
        return (try? JSONDecoder().decode([GlobalScenarioInfo].self, from: data)) ?? []
    }

    private func saveGlobalIndex(_ items: [GlobalScenarioInfo]) {
        let data = (try? JSONEncoder().encode(items)) ?? Data()
        UserDefaults.standard.set(data, forKey: globalIndexKey())
    }

    private func upsertGlobalIndex(_ info: GlobalScenarioInfo) {
        var items = loadGlobalIndex()
        if let idx = items.firstIndex(where: { $0.id == info.id }) {
            items[idx] = info
        } else {
            items.append(info)
        }
        saveGlobalIndex(items)
    }

    private func bumpGlobalLastAccessed(scenarioID: UUID) {
        var items = loadGlobalIndex()
        guard let idx = items.firstIndex(where: { $0.id == scenarioID }) else { return }
        items[idx].lastAccessed = Date().timeIntervalSince1970
        saveGlobalIndex(items)
    }

    private func saveGlobalPayload(_ overridesByCategoryID: [UUID: Double], scenarioID: UUID) {
        let payload = GlobalScenarioPayload(
            scenarioID: scenarioID,
            overridesByCategoryID: overridesByCategoryID
        )

        let data = (try? JSONEncoder().encode(payload)) ?? Data()
        UserDefaults.standard.set(data, forKey: globalPayloadKey(scenarioID: scenarioID))
    }
}

// MARK: - Codable Payloads

private struct ScenarioPayload: Codable {
    let scenarioID: UUID
    let rangeKey: String
    let scenarioByCategoryID: [UUID: Double]
}

private struct GlobalScenarioPayload: Codable {
    let scenarioID: UUID
    let overridesByCategoryID: [UUID: Double]
}
