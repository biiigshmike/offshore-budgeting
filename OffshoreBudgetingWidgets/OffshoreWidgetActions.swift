import AppIntents
import Foundation

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst) && !OFFSHORE_WIDGET_EXTENSION
import UIKit
#endif

enum OffshoreWidgetDeepLink {
    static let openSafeSpendTodayURL = URL(string: "offshore://open/safe-spend-today")!
    static let openForecastSavingsURL = URL(string: "offshore://open/forecast-savings")!
}

nonisolated enum OffshoreControlDestination: String, AppEnum {
    case addExpense
    case addIncome
    case reviewToday
    case excursionMode

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Offshore Action")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .addExpense: "Add Expense",
        .addIncome: "Add Income",
        .reviewToday: "Review Today",
        .excursionMode: "Excursion Mode"
    ]
}

struct OpenOffshoreControlIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Offshore Control"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @Parameter(title: "Action")
    var target: OffshoreControlDestination

    init() {}

    init(target: OffshoreControlDestination) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> IntentResultContainer<Never, Never, Never, Never> {
        #if OFFSHORE_WIDGET_EXTENSION
        // Foreground actions require the host app to handle the destination.
        throw CocoaError(.featureUnsupported)
        #else
        await OffshoreDeepLinkHandler.handleControl(target)
        return .result()
        #endif
    }
}

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
struct StartExcursionControlIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Excursion Mode"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> IntentResultContainer<Never, Never, Never, Never> {
        #if OFFSHORE_WIDGET_EXTENSION
        throw CocoaError(.featureUnsupported)
        #else
        ShoppingModeLocationService.shared.setApplicationInForeground(
            UIApplication.shared.applicationState == .active
        )
        if case .blocked(let blockers) = await ShoppingModeManager.shared.start(hours: 2) {
            throw StartError(message: blockers.map(\.message).joined(separator: "\n"))
        }
        return .result()
        #endif
    }

    private struct StartError: LocalizedError {
        let message: String

        var errorDescription: String? { message }
    }
}
#endif
