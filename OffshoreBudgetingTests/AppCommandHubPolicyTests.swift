//
//  AppCommandHubPolicyTests.swift
//  OffshoreBudgetingTests
//
//  Created by Michael Brown on 2/25/26.
//

import Testing
@testable import Offshore

struct AppCommandHubPolicyTests {

    // MARK: - Enabled Policy

    @MainActor
    @Test func enabledPolicy_appliesSurfaceAndAvailabilityUpdates() {
        let hub = AppCommandHub(policy: .enabled)

        #expect(hub.surface == .none)
        #expect(hub.activeSectionRaw == AppSection.home.rawValue)

        hub.activate(.budgetDetail)
        #expect(hub.surface == .budgetDetail)

        hub.setBudgetDetailCanCreateTransaction(true)
        #expect(hub.availability.budgetDetailCanCreateTransaction)

        hub.setCardsSortContext(.sharedBalances)
        #expect(hub.availability.cardsSortContext == .sharedBalances)

        hub.setIncomeDeletionAvailability(canDeleteActual: true, canDeletePlanned: true)
        #expect(hub.availability.incomeCanDeleteActual)
        #expect(hub.availability.incomeCanDeletePlanned)

        hub.setActiveSectionRaw(AppSection.settings.rawValue)
        #expect(hub.activeSectionRaw == AppSection.settings.rawValue)

        hub.deactivate(.budgetDetail)
        #expect(hub.surface == .none)
    }

    // MARK: - Disabled Policy

    @MainActor
    @Test func disabledPolicy_ignoresSurfaceAndAvailabilityUpdates_butAllowsDispatch() {
        let hub = AppCommandHub(policy: .disabled)
        let initialAvailability = hub.availability
        let initialSequence = hub.sequence

        hub.activate(.cardDetail)
        hub.setBudgetDetailCanCreateTransaction(true)
        hub.setIncomeDeletionAvailability(canDeleteActual: true, canDeletePlanned: true)
        hub.setCardsSortContext(.sharedBalances)
        hub.setActiveSectionRaw(AppSection.settings.rawValue)
        hub.deactivate(.cardDetail)

        #expect(hub.surface == .none)
        #expect(hub.availability == initialAvailability)
        #expect(hub.activeSectionRaw == AppSection.home.rawValue)

        hub.dispatch(AppCommandID.Help.openHelp)
        #expect(hub.sequence == initialSequence + 1)
        #expect(hub.latestCommandID == AppCommandID.Help.openHelp)
    }
}
