//
//  ICloudPreferenceSyncService.swift
//  OffshoreBudgeting
//
//  Created by Codex on 5/28/26.
//

import Foundation

protocol ICloudKeyValueStoring: AnyObject {
    func data(forKey aKey: String) -> Data?
    func set(_ anObject: Any?, forKey aKey: String)

    @discardableResult
    func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: ICloudKeyValueStoring {}

struct HomeLayoutSyncEnvelope: Codable, Equatable {
    var schemaVersion: Int
    var workspaceID: UUID
    var updatedAt: Double
    var deviceID: String
    var pinnedItems: [HomePinnedItem]
}

struct WhatIfGlobalScenariosSyncEnvelope: Codable, Equatable {
    var schemaVersion: Int
    var workspaceID: UUID
    var updatedAt: Double
    var deviceID: String
    var payload: WhatIfGlobalScenariosSyncPayload
}

struct ICloudPreferenceSyncService {
    enum SyncResolution: Equatable {
        case skipped
        case uploadedLocal
        case appliedRemote
        case keptLocal
    }

    static let activeICloudKey = "icloud_activeUseCloud"
    static let homeLayoutSyncEnabledKey = "icloud_sync_homeLayout"
    static let whatIfScenariosSyncEnabledKey = "icloud_sync_whatIfScenarios"

    private static let schemaVersion = 1
    private static let deviceIDKey = "icloud_sync_deviceID"

    private let keyValueStore: ICloudKeyValueStoring
    private let defaults: UserDefaults
    private let now: () -> Date
    private let deviceIDProvider: (() -> String)?

    init(
        keyValueStore: ICloudKeyValueStoring = NSUbiquitousKeyValueStore.default,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        deviceIDProvider: (() -> String)? = nil
    ) {
        self.keyValueStore = keyValueStore
        self.defaults = defaults
        self.now = now
        self.deviceIDProvider = deviceIDProvider
    }

    // MARK: - Notification Helpers

    static func changedKeys(from notification: Notification) -> [String]? {
        notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
    }

    // MARK: - Enable-Time Reconciliation

    @discardableResult
    func synchronizeHomeLayoutOnEnable(workspaceID: UUID) -> SyncResolution {
        guard isICloudPreferenceSyncAvailable else { return .skipped }
        keyValueStore.synchronize()

        guard let remote = loadRemoteHomeLayout(workspaceID: workspaceID) else {
            pushHomeLayout(workspaceID: workspaceID)
            return .uploadedLocal
        }

        let localUpdatedAt = localUpdatedAt(for: localHomeLayoutUpdatedAtKey(workspaceID: workspaceID))
        if remote.updatedAt > localUpdatedAt {
            applyRemoteHomeLayout(remote)
            return .appliedRemote
        }

        if localUpdatedAt > remote.updatedAt {
            pushHomeLayout(workspaceID: workspaceID)
            return .uploadedLocal
        }

        return .keptLocal
    }

    func synchronizeHomeLayoutOnEnable(workspaceIDs: [UUID]) {
        for workspaceID in workspaceIDs {
            _ = synchronizeHomeLayoutOnEnable(workspaceID: workspaceID)
        }
    }

    @discardableResult
    func synchronizeWhatIfScenariosOnEnable(workspaceID: UUID) -> SyncResolution {
        guard isICloudPreferenceSyncAvailable else { return .skipped }
        keyValueStore.synchronize()

        guard let remote = loadRemoteWhatIfScenarios(workspaceID: workspaceID) else {
            pushWhatIfScenarios(workspaceID: workspaceID)
            return .uploadedLocal
        }

        let localUpdatedAt = localUpdatedAt(for: localWhatIfUpdatedAtKey(workspaceID: workspaceID))
        if remote.updatedAt > localUpdatedAt {
            applyRemoteWhatIfScenarios(remote)
            return .appliedRemote
        }

        if localUpdatedAt > remote.updatedAt {
            pushWhatIfScenarios(workspaceID: workspaceID)
            return .uploadedLocal
        }

        return .keptLocal
    }

    func synchronizeWhatIfScenariosOnEnable(workspaceIDs: [UUID]) {
        for workspaceID in workspaceIDs {
            _ = synchronizeWhatIfScenariosOnEnable(workspaceID: workspaceID)
        }
    }

    // MARK: - Local Change Pushes

    func pushHomeLayoutIfEnabled(workspaceID: UUID) {
        guard isICloudPreferenceSyncAvailable,
              defaults.bool(forKey: Self.homeLayoutSyncEnabledKey)
        else { return }

        pushHomeLayout(workspaceID: workspaceID)
    }

    func pushWhatIfScenariosIfEnabled(workspaceID: UUID) {
        guard isICloudPreferenceSyncAvailable,
              defaults.bool(forKey: Self.whatIfScenariosSyncEnabledKey)
        else { return }

        pushWhatIfScenarios(workspaceID: workspaceID)
    }

    // MARK: - Remote Pulls

    func pullEnabledSnapshots(workspaceIDs: [UUID], changedKeys: [String]? = nil) {
        guard isICloudPreferenceSyncAvailable else { return }
        keyValueStore.synchronize()

        for workspaceID in workspaceIDs {
            if defaults.bool(forKey: Self.homeLayoutSyncEnabledKey) {
                pullHomeLayoutIfNewer(workspaceID: workspaceID, changedKeys: changedKeys)
            }

            if defaults.bool(forKey: Self.whatIfScenariosSyncEnabledKey) {
                pullWhatIfScenariosIfNewer(workspaceID: workspaceID, changedKeys: changedKeys)
            }
        }
    }

    // MARK: - Home Layout

    private func pushHomeLayout(workspaceID: UUID) {
        let updatedAt = now().timeIntervalSince1970
        let envelope = HomeLayoutSyncEnvelope(
            schemaVersion: Self.schemaVersion,
            workspaceID: workspaceID,
            updatedAt: updatedAt,
            deviceID: deviceID(),
            pinnedItems: HomePinnedItemsStore(
                workspaceID: workspaceID,
                defaults: defaults
            ).exportSyncSnapshot()
        )

        saveRemoteEnvelope(envelope, key: Self.homeLayoutKey(workspaceID: workspaceID))
        setLocalUpdatedAt(updatedAt, for: localHomeLayoutUpdatedAtKey(workspaceID: workspaceID))
    }

    private func pullHomeLayoutIfNewer(workspaceID: UUID, changedKeys: [String]?) {
        let key = Self.homeLayoutKey(workspaceID: workspaceID)
        guard shouldConsider(key: key, changedKeys: changedKeys),
              let remote = loadRemoteHomeLayout(workspaceID: workspaceID)
        else { return }

        let localUpdatedAt = localUpdatedAt(for: localHomeLayoutUpdatedAtKey(workspaceID: workspaceID))
        guard remote.updatedAt > localUpdatedAt else { return }
        applyRemoteHomeLayout(remote)
    }

    private func applyRemoteHomeLayout(_ envelope: HomeLayoutSyncEnvelope) {
        HomePinnedItemsStore(
            workspaceID: envelope.workspaceID,
            defaults: defaults
        ).importSyncSnapshot(envelope.pinnedItems)
        setLocalUpdatedAt(envelope.updatedAt, for: localHomeLayoutUpdatedAtKey(workspaceID: envelope.workspaceID))
    }

    private func loadRemoteHomeLayout(workspaceID: UUID) -> HomeLayoutSyncEnvelope? {
        loadRemoteEnvelope(
            HomeLayoutSyncEnvelope.self,
            key: Self.homeLayoutKey(workspaceID: workspaceID),
            workspaceID: workspaceID
        )
    }

    // MARK: - What-if Scenarios

    private func pushWhatIfScenarios(workspaceID: UUID) {
        let updatedAt = now().timeIntervalSince1970
        let envelope = WhatIfGlobalScenariosSyncEnvelope(
            schemaVersion: Self.schemaVersion,
            workspaceID: workspaceID,
            updatedAt: updatedAt,
            deviceID: deviceID(),
            payload: WhatIfScenarioStore(
                workspaceID: workspaceID,
                defaults: defaults,
                syncOnMutation: false
            ).exportGlobalSyncSnapshot()
        )

        saveRemoteEnvelope(envelope, key: Self.whatIfScenariosKey(workspaceID: workspaceID))
        setLocalUpdatedAt(updatedAt, for: localWhatIfUpdatedAtKey(workspaceID: workspaceID))
    }

    private func pullWhatIfScenariosIfNewer(workspaceID: UUID, changedKeys: [String]?) {
        let key = Self.whatIfScenariosKey(workspaceID: workspaceID)
        guard shouldConsider(key: key, changedKeys: changedKeys),
              let remote = loadRemoteWhatIfScenarios(workspaceID: workspaceID)
        else { return }

        let localUpdatedAt = localUpdatedAt(for: localWhatIfUpdatedAtKey(workspaceID: workspaceID))
        guard remote.updatedAt > localUpdatedAt else { return }
        applyRemoteWhatIfScenarios(remote)
    }

    private func applyRemoteWhatIfScenarios(_ envelope: WhatIfGlobalScenariosSyncEnvelope) {
        WhatIfScenarioStore(
            workspaceID: envelope.workspaceID,
            defaults: defaults,
            syncOnMutation: false
        ).importGlobalSyncSnapshot(envelope.payload)
        setLocalUpdatedAt(envelope.updatedAt, for: localWhatIfUpdatedAtKey(workspaceID: envelope.workspaceID))
    }

    private func loadRemoteWhatIfScenarios(workspaceID: UUID) -> WhatIfGlobalScenariosSyncEnvelope? {
        loadRemoteEnvelope(
            WhatIfGlobalScenariosSyncEnvelope.self,
            key: Self.whatIfScenariosKey(workspaceID: workspaceID),
            workspaceID: workspaceID
        )
    }

    // MARK: - Shared Helpers

    static func homeLayoutKey(workspaceID: UUID) -> String {
        "offshore.v1.homeLayout.\(workspaceID.uuidString)"
    }

    static func whatIfScenariosKey(workspaceID: UUID) -> String {
        "offshore.v1.whatIfGlobalScenarios.\(workspaceID.uuidString)"
    }

    private var isICloudPreferenceSyncAvailable: Bool {
        defaults.bool(forKey: Self.activeICloudKey)
    }

    private func shouldConsider(key: String, changedKeys: [String]?) -> Bool {
        guard let changedKeys else { return true }
        return changedKeys.contains(key)
    }

    private func saveRemoteEnvelope<T: Encodable>(_ envelope: T, key: String) {
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        keyValueStore.set(data, forKey: key)
        keyValueStore.synchronize()
    }

    private func loadRemoteEnvelope<T: Decodable & WorkspaceScopedSyncEnvelope>(
        _ type: T.Type,
        key: String,
        workspaceID: UUID
    ) -> T? {
        guard let data = keyValueStore.data(forKey: key),
              let envelope = try? JSONDecoder().decode(type, from: data),
              envelope.schemaVersion == Self.schemaVersion,
              envelope.workspaceID == workspaceID
        else { return nil }

        return envelope
    }

    private func localUpdatedAt(for key: String) -> Double {
        defaults.double(forKey: key)
    }

    private func setLocalUpdatedAt(_ updatedAt: Double, for key: String) {
        defaults.set(updatedAt, forKey: key)
    }

    private func localHomeLayoutUpdatedAtKey(workspaceID: UUID) -> String {
        "offshore.kvs.localUpdated.homeLayout.\(workspaceID.uuidString)"
    }

    private func localWhatIfUpdatedAtKey(workspaceID: UUID) -> String {
        "offshore.kvs.localUpdated.whatIfGlobalScenarios.\(workspaceID.uuidString)"
    }

    private func deviceID() -> String {
        if let deviceIDProvider {
            return deviceIDProvider()
        }

        if let existing = defaults.string(forKey: Self.deviceIDKey), existing.isEmpty == false {
            return existing
        }

        let generated = UUID().uuidString
        defaults.set(generated, forKey: Self.deviceIDKey)
        return generated
    }
}

private protocol WorkspaceScopedSyncEnvelope {
    var schemaVersion: Int { get }
    var workspaceID: UUID { get }
}

extension HomeLayoutSyncEnvelope: WorkspaceScopedSyncEnvelope {}
extension WhatIfGlobalScenariosSyncEnvelope: WorkspaceScopedSyncEnvelope {}
