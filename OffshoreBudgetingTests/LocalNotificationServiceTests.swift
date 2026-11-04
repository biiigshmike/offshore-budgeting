import Foundation
import SwiftData
import Testing
import UserNotifications
@testable import Offshore

@MainActor
struct LocalNotificationServiceTests {
    private enum TestError: Error { case requestFailed, addFailed }

    @MainActor
    private final class Center: LocalNotificationCenter {
        var snapshot = NotificationSettingsSnapshot(authorization: .authorized, alerts: .enabled, sounds: .enabled)
        var authorizationAfterRequest: UNAuthorizationStatus = .authorized
        var requestError: Error?
        var addError: Error?
        var requestCount = 0
        var settingsReadCount = 0
        var requests: [String: UNNotificationRequest] = [:]
        var pauseNextAdd = false
        var resumeAdd: CheckedContinuation<Void, Never>?
        var addStarted: CheckedContinuation<Void, Never>?

        func settings() async -> NotificationSettingsSnapshot {
            settingsReadCount += 1
            return snapshot
        }
        func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
            requestCount += 1
            if let requestError { throw requestError }
            snapshot = NotificationSettingsSnapshot(
                authorization: authorizationAfterRequest, alerts: .enabled, sounds: .enabled
            )
            return authorizationAfterRequest == .authorized
        }
        func pendingRequests() async -> [UNNotificationRequest] { Array(requests.values) }
        func add(_ request: UNNotificationRequest) async throws {
            if pauseNextAdd {
                pauseNextAdd = false
                await withCheckedContinuation { continuation in
                    resumeAdd = continuation
                    addStarted?.resume()
                    addStarted = nil
                }
            }
            if let addError { throw addError }
            requests[request.identifier] = request
        }
        func remove(identifiers: [String]) {
            for id in identifiers { requests.removeValue(forKey: id) }
        }
        func removeAll() { requests.removeAll() }
        func waitForPausedAdd() async {
            if resumeAdd != nil { return }
            await withCheckedContinuation { addStarted = $0 }
        }
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Workspace.self, Budget.self, BudgetCategoryLimit.self, Card.self,
            BudgetCardLink.self, BudgetPresetLink.self, Category.self, Preset.self,
            PlannedExpense.self, VariableExpense.self, AllocationAccount.self,
            ExpenseAllocation.self, AllocationSettlement.self, SavingsAccount.self,
            SavingsLedgerEntry.self, ImportMerchantRule.self, AssistantAliasRule.self,
            MarinaChatSession.self, IncomeSeries.self, Income.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: config))
    }

    private func withDefaults(_ operation: (UserDefaults) async throws -> Void) async throws {
        let name = "ReminderPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try await operation(defaults)
    }

    @Test func firstSetupDefaultsAreDraftOnly() async throws {
        try await withDefaults { defaults in
            let before = defaults.dictionaryRepresentation()
            let draft = ReminderPreferences.setupDraft(from: defaults)
            #expect(draft.daily && draft.income && draft.preset)
            #expect(draft.hour == 20 && draft.minute == 0)
            #expect(!ReminderPreferences.load(from: defaults).enabled)
            #expect(!ReminderPreferences.load(from: defaults).hasSelectedReminders)
            #expect(defaults.dictionaryRepresentation().keys.sorted() == before.keys.sorted())
        }
    }

    @Test func existingOffChoicesAreNotOverwritten() async throws {
        try await withDefaults { defaults in
            defaults.set(false, forKey: ReminderPreferences.Key.daily)
            defaults.set(false, forKey: ReminderPreferences.Key.income)
            defaults.set(false, forKey: ReminderPreferences.Key.preset)
            #expect(!ReminderPreferences.setupDraft(from: defaults).hasSelectedReminders)
            #expect(!ReminderPreferences.load(from: defaults).enabled)
        }
    }

    @Test func explicitAllOffAndTimeSurviveReload() async throws {
        try await withDefaults { defaults in
            let choices = ReminderPreferences(hour: 9, minute: 15)
            choices.save(to: defaults)
            #expect(ReminderPreferences.setupDraft(from: defaults) == choices)
            #expect(ReminderPreferences.load(from: defaults) == choices)
        }
    }

    @Test func allowPersistsChoicesAndSchedulesDaily() async throws {
        try await withDefaults { defaults in
            let center = Center()
            center.snapshot = .init(authorization: .notDetermined, alerts: .disabled, sounds: .disabled)
            let service = LocalNotificationService(center: center)
            let choices = ReminderPreferences(daily: true, income: true, preset: true, hour: 19, minute: 25)
            try await service.configureReminders(
                choices, defaults: defaults, modelContext: makeContext(), workspaceID: UUID()
            )
            let saved = ReminderPreferences.load(from: defaults)
            #expect(saved.enabled && saved.daily && saved.income && saved.preset)
            #expect(saved.hour == 19 && saved.minute == 25)
            #expect(center.requestCount == 1)
            let request = try #require(center.requests[LocalNotificationService.NotificationID.dailyExpenseReminder])
            let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
            #expect(trigger.repeats)
            #expect(trigger.dateComponents.hour == 19 && trigger.dateComponents.minute == 25)
            #expect(center.requests.count == 1) // No income or preset days exist.
        }
    }

    @Test func denialSavesCategoriesAndLeavesMasterOff() async throws {
        try await withDefaults { defaults in
            let center = Center()
            center.snapshot = .init(authorization: .notDetermined, alerts: .disabled, sounds: .disabled)
            center.authorizationAfterRequest = .denied
            let service = LocalNotificationService(center: center)
            try await service.configureReminders(
                ReminderPreferences(daily: true, income: true, hour: 18, minute: 10),
                defaults: defaults, modelContext: makeContext(), workspaceID: UUID()
            )
            let saved = ReminderPreferences.load(from: defaults)
            #expect(!saved.enabled && saved.daily && saved.income && !saved.preset)
            #expect(saved.hour == 18 && saved.minute == 10)
            #expect(center.requests.isEmpty)
            #expect(service.authorizationState == .denied)
        }
    }

    @Test func allOffSkipsPermissionPrompt() async throws {
        try await withDefaults { defaults in
            let center = Center()
            center.snapshot = .init(authorization: .notDetermined, alerts: .disabled, sounds: .disabled)
            try await LocalNotificationService(center: center).configureReminders(
                ReminderPreferences(), defaults: defaults, modelContext: makeContext(), workspaceID: UUID()
            )
            #expect(center.requestCount == 0)
            #expect(!ReminderPreferences.load(from: defaults).enabled)
            #expect(center.requests.isEmpty)
        }
    }

    @Test func permissionRequestFailureKeepsChoicesAndReportsError() async throws {
        try await withDefaults { defaults in
            let center = Center()
            center.snapshot = .init(authorization: .notDetermined, alerts: .disabled, sounds: .disabled)
            center.requestError = TestError.requestFailed
            do {
                try await LocalNotificationService(center: center).configureReminders(
                    ReminderPreferences(daily: true), defaults: defaults,
                    modelContext: makeContext(), workspaceID: UUID()
                )
                Issue.record("Expected an authorization error")
            } catch TestError.requestFailed { }
            let saved = ReminderPreferences.load(from: defaults)
            #expect(!saved.enabled && saved.daily)
            #expect(center.requests.isEmpty)
        }
    }

    @Test(arguments: [UNAuthorizationStatus.authorized, .provisional, .ephemeral, .denied, .notDetermined])
    func authorizationStatesRemainDistinct(_ status: UNAuthorizationStatus) async {
        let center = Center()
        center.snapshot = .init(authorization: status, alerts: .disabled, sounds: .disabled)
        let service = LocalNotificationService(center: center)
        #expect(service.authorizationState == .unknown)
        await service.refreshAuthorizationStatus()
        switch status {
        case .authorized: #expect(service.authorizationState == .authorized)
        case .provisional: #expect(service.authorizationState == .provisional)
        case .ephemeral: #expect(service.authorizationState == .ephemeral)
        case .denied: #expect(service.authorizationState == .denied)
        case .notDetermined: #expect(service.authorizationState == .notDetermined)
        @unknown default: Issue.record("Unexpected status")
        }
        #expect(service.isAuthorized == [.authorized, .provisional, .ephemeral].contains(status))
    }

    @Test func systemRefreshPreservesIntentAndRemovesOnlyReminders() async throws {
        try await withDefaults { defaults in
            let center = Center()
            let service = LocalNotificationService(center: center)
            let context = try makeContext()
            let id = UUID()
            let preferences = ReminderPreferences(enabled: true, daily: true)
            preferences.save(to: defaults)
            try await service.syncReminders(modelContext: context, workspaceID: id, preferences: preferences)
            let excursionID = LocalNotificationService.NotificationID.shoppingModeSuggestion + "_test"
            center.requests[excursionID] = UNNotificationRequest(
                identifier: excursionID, content: UNMutableNotificationContent(), trigger: nil
            )
            center.snapshot = .init(authorization: .denied, alerts: .disabled, sounds: .disabled)
            try await service.syncReminders(modelContext: context, workspaceID: id, preferences: preferences)
            #expect(Set(center.requests.keys) == [excursionID])
            #expect(ReminderPreferences.load(from: defaults) == preferences)
            center.snapshot = .init(authorization: .authorized, alerts: .enabled, sounds: .disabled)
            try await service.syncReminders(modelContext: context, workspaceID: id, preferences: preferences)
            #expect(center.requests[LocalNotificationService.NotificationID.dailyExpenseReminder] != nil)
            #expect(service.deliveryDescription.contains("sounds are off"))
            #expect(center.requestCount == 0)
        }
    }

    @Test func dailyCategoryAndMasterIndependentlyCancelAndRestore() async throws {
        let center = Center()
        let service = LocalNotificationService(center: center)
        let context = try makeContext()
        let id = UUID()
        var preferences = ReminderPreferences(enabled: true, daily: true)
        try await service.syncReminders(modelContext: context, workspaceID: id, preferences: preferences)
        #expect(center.requests.count == 1)
        preferences.daily = false
        try await service.syncReminders(modelContext: context, workspaceID: id, preferences: preferences)
        #expect(center.requests.isEmpty)
        preferences.daily = true
        preferences.enabled = false
        try await service.syncReminders(modelContext: context, workspaceID: id, preferences: preferences)
        #expect(center.requests.isEmpty)
        preferences.enabled = true
        preferences.hour = 7
        preferences.minute = 30
        try await service.syncReminders(modelContext: context, workspaceID: id, preferences: preferences)
        let trigger = try #require(center.requests.values.first?.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.dateComponents.hour == 7 && trigger.dateComponents.minute == 30)
    }

    @Test func latestOffWinsAcrossOverlappingServiceInstances() async throws {
        let center = Center()
        let firstService = LocalNotificationService(center: center)
        let secondService = LocalNotificationService(center: center)
        let context = try makeContext()
        let id = UUID()
        center.pauseNextAdd = true
        let first = Task {
            try await firstService.syncReminders(
                modelContext: context, workspaceID: id,
                preferences: ReminderPreferences(enabled: true, daily: true)
            )
        }
        await center.waitForPausedAdd()
        let second = Task {
            try await secondService.syncReminders(
                modelContext: context, workspaceID: id, preferences: ReminderPreferences()
            )
        }
        // Give the second call a chance to overlap the suspended add operation.
        await Task.yield()
        center.resumeAdd?.resume()
        center.resumeAdd = nil
        try await first.value
        try await second.value
        #expect(center.requests.isEmpty)
    }

    @Test func dueRemindersAreScopedDatedAndIndependentlyControlled() async throws {
        let center = Center()
        let service = LocalNotificationService(center: center)
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        let otherWorkspace = Workspace(name: "Other", hexColor: "#654321")
        context.insert(workspace)
        context.insert(otherWorkspace)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let later = calendar.date(byAdding: .day, value: 31, to: today)!
        for (day, planned, owner) in [
            (tomorrow, true, workspace), (tomorrow, true, workspace), // One alert per day.
            (today, true, workspace), (later, true, workspace),
            (tomorrow, false, workspace), (tomorrow, true, otherWorkspace)
        ] {
            context.insert(Income(source: "Pay", amount: 100, date: day, isPlanned: planned, workspace: owner))
        }
        context.insert(PlannedExpense(
            title: "Rent", plannedAmount: 100, expenseDate: tomorrow,
            workspace: workspace, sourcePresetID: UUID()
        ))
        context.insert(PlannedExpense(
            title: "Other Workspace", plannedAmount: 100, expenseDate: tomorrow,
            workspace: otherWorkspace, sourcePresetID: UUID()
        ))
        context.insert(PlannedExpense(
            title: "Not a Preset", plannedAmount: 100, expenseDate: tomorrow, workspace: workspace
        ))
        try context.save()
        var preferences = ReminderPreferences(enabled: true, income: true, preset: true, hour: 0)
        try await service.syncReminders(modelContext: context, workspaceID: workspace.id, preferences: preferences)
        #expect(center.requests.count == 2) // Today's midnight is past; day 31 is outside the horizon.
        for request in center.requests.values {
            let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
            #expect(!trigger.repeats)
            let fireDate = try #require(trigger.nextTriggerDate())
            #expect(calendar.isDate(fireDate, inSameDayAs: tomorrow))
            #expect(fireDate > Date())
            #expect(!request.content.body.contains("Other Workspace"))
            #expect(!request.content.body.contains("Not a Preset"))
        }
        preferences.income = false
        try await service.syncReminders(modelContext: context, workspaceID: workspace.id, preferences: preferences)
        #expect(center.requests.count == 1)
        #expect(center.requests.values.first?.identifier.hasPrefix(LocalNotificationService.NotificationID.presetDueReminder) == true)
        preferences.preset = false
        preferences.income = true
        try await service.syncReminders(modelContext: context, workspaceID: workspace.id, preferences: preferences)
        #expect(center.requests.count == 1)
        #expect(center.requests.values.first?.identifier.hasPrefix(LocalNotificationService.NotificationID.plannedIncomeReminder) == true)
    }

    @MainActor
    private final class DeliveryGate {
        var allowed = true
    }

    @Test func excursionDeliveryIsRemovedIfLocationAccessChangesDuringAdd() async throws {
        let center = Center()
        let service = LocalNotificationService(center: center)
        let gate = DeliveryGate()
        center.pauseNextAdd = true
        let delivery = Task {
            try await service.scheduleShoppingModeSuggestionNotification(
                merchantName: "Nearby Shop", isStillValid: { gate.allowed }
            )
        }
        await center.waitForPausedAdd()
        gate.allowed = false
        center.resumeAdd?.resume()
        center.resumeAdd = nil
        do {
            _ = try await delivery.value
            Issue.record("Expected canceled delivery")
        } catch is CancellationError { }
        #expect(center.requests.isEmpty)
    }

    @Test func schedulingFailureIsReportedAndCanBeRetried() async throws {
        let center = Center()
        let service = LocalNotificationService(center: center)
        let context = try makeContext()
        let id = UUID()
        let preferences = ReminderPreferences(enabled: true, daily: true)
        center.addError = TestError.addFailed
        do {
            try await service.syncReminders(modelContext: context, workspaceID: id, preferences: preferences)
            Issue.record("Expected scheduling failure")
        } catch TestError.addFailed { }
        center.addError = nil
        try await service.syncReminders(modelContext: context, workspaceID: id, preferences: preferences)
        #expect(center.requests.count == 1)
    }
}
