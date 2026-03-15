import Testing
@testable import Offshore

struct AppRootLaunchSectionResolverTests {

    @Test func resolve_prefersInitialSectionOverride() {
        let section = AppRootLaunchSectionResolver.resolve(
            initialSectionOverride: .settings,
            pendingShortcutSectionRaw: AppSection.cards.rawValue
        )

        #expect(section == .settings)
    }

    @Test func resolve_usesPendingShortcutSectionWhenNoOverrideExists() {
        let section = AppRootLaunchSectionResolver.resolve(
            initialSectionOverride: nil,
            pendingShortcutSectionRaw: AppSection.income.rawValue
        )

        #expect(section == .income)
    }

    @Test func resolve_supportsLegacyAccountsRawValue() {
        let section = AppRootLaunchSectionResolver.resolve(
            initialSectionOverride: nil,
            pendingShortcutSectionRaw: "Accounts"
        )

        #expect(section == .cards)
    }

    @Test func resolve_defaultsToHomeForMissingOrInvalidPendingSection() {
        let emptySection = AppRootLaunchSectionResolver.resolve(
            initialSectionOverride: nil,
            pendingShortcutSectionRaw: ""
        )
        let invalidSection = AppRootLaunchSectionResolver.resolve(
            initialSectionOverride: nil,
            pendingShortcutSectionRaw: "NotASection"
        )

        #expect(emptySection == .home)
        #expect(invalidSection == .home)
    }
}
