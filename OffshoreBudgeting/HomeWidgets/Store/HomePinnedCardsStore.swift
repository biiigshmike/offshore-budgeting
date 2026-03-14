//
//  HomePinnedCardsStore.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/24/26.
//

import Foundation
import SwiftUI

struct HomePinnedCardsStore {

    private let storageKey: String
    private let defaults: UserDefaults

    init(workspaceID: UUID, defaults: UserDefaults = .standard) {
        self.storageKey = "home_pinnedCardIDs_\(workspaceID.uuidString)"
        self.defaults = defaults
    }

    func load() -> [UUID] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
    }

    func save(_ ids: [UUID]) {
        let data = (try? JSONEncoder().encode(ids)) ?? Data()
        defaults.set(data, forKey: storageKey)
    }
}

// MARK: - Mutations

extension HomePinnedCardsStore {
    func removePinnedCardID(_ id: UUID) {
        let updated = load().filter { $0 != id }
        save(updated)
    }
}
