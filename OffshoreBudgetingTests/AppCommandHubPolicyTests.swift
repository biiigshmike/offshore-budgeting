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

        hub.activate(.savings)
        #expect(hub.surface == .savings)

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
        #expect(hub.surface == .savings)

        hub.deactivate(.savings)
        #expect(hub.surface == .none)
    }

    // MARK: - Disabled Policy

    @MainActor
    @Test func disabledPolicy_ignoresSurfaceAndAvailabilityUpdates_butAllowsDispatch() {
        let hub = AppCommandHub(policy: .disabled)
        let initialAvailability = hub.availability
        let initialSequence = hub.sequence

        hub.activate(.cardDetail)
        hub.activate(.savings)
        hub.setBudgetDetailCanCreateTransaction(true)
        hub.setIncomeDeletionAvailability(canDeleteActual: true, canDeletePlanned: true)
        hub.setCardsSortContext(.sharedBalances)
        hub.setActiveSectionRaw(AppSection.settings.rawValue)
        hub.deactivate(.savings)
        hub.deactivate(.cardDetail)

        #expect(hub.surface == .none)
        #expect(hub.availability == initialAvailability)
        #expect(hub.activeSectionRaw == AppSection.home.rawValue)

        hub.dispatch(AppCommandID.Help.openHelp)
        #expect(hub.sequence == initialSequence + 1)
        #expect(hub.latestCommandID == AppCommandID.Help.openHelp)
    }

    @Test func accountsSegments_mapToExpectedCommandRouting() {
        let cardsConfiguration = AccountsView.Segment.cards.commandConfiguration
        switch cardsConfiguration.surface {
        case .cards:
            break
        default:
            Issue.record("Expected Cards segment to route to the cards command surface.")
        }
        #expect(cardsConfiguration.cardsSortContext == .cards)

        let sharedBalancesConfiguration = AccountsView.Segment.sharedBalances.commandConfiguration
        switch sharedBalancesConfiguration.surface {
        case .cards:
            break
        default:
            Issue.record("Expected Shared Balances segment to route to the cards command surface.")
        }
        #expect(sharedBalancesConfiguration.cardsSortContext == .sharedBalances)

        let savingsConfiguration = AccountsView.Segment.savings.commandConfiguration
        switch savingsConfiguration.surface {
        case .savings:
            break
        default:
            Issue.record("Expected Savings segment to route to the savings command surface.")
        }
        #expect(savingsConfiguration.cardsSortContext == nil)
    }

    @Test func accountsPhoneSortTargets_mapToExpectedStorageTargets() {
        let cardsTarget = AccountsPhoneSortTarget.target(for: AppCommandID.Cards.sortZA)
        switch cardsTarget {
        case .cards(let mode):
            #expect(mode == "za")
        default:
            Issue.record("Expected Cards sort target for cards Z-A command.")
        }

        let sharedBalancesTarget = AccountsPhoneSortTarget.target(for: AppCommandID.SharedBalances.sortAmountDesc)
        switch sharedBalancesTarget {
        case .sharedBalances(let mode):
            #expect(mode == "amountDesc")
        default:
            Issue.record("Expected Shared Balances sort target for amount descending command.")
        }

        let savingsTarget = AccountsPhoneSortTarget.target(for: AppCommandID.Savings.sortDateAsc)
        switch savingsTarget {
        case .savings(let mode):
            #expect(mode == SavingsLedgerSortMode.dateAsc.rawValue)
        default:
            Issue.record("Expected Savings sort target for date ascending command.")
        }
    }
}
