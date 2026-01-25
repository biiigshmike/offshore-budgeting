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

    init(workspaceID: UUID) {
        self.storageKey = "home_pinnedCardIDs_\(workspaceID.uuidString)"
    }

    func load() -> [UUID] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
    }

    func save(_ ids: [UUID]) {
        let data = (try? JSONEncoder().encode(ids)) ?? Data()
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
