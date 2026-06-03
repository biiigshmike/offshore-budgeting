//
//  WorkspacePickerView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/20/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct WorkspacePickerView: View {

    let workspaces: [Workspace]
    @Binding var selectedWorkspaceID: String
    let showsCloseButton: Bool

    let onCreate: (String, String) -> Void
    let onDelete: (IndexSet) -> Void

    private enum SheetRoute: Identifiable {
        case restartRequired
        case addWorkspace
        case editWorkspace(Workspace)
        case exportWorkspace(Workspace)
        case importPreview(WorkspaceImportPreview)

        var id: String {
            switch self {
            case .restartRequired:
                return "restartRequired"
            case .addWorkspace:
                return "addWorkspace"
            case .editWorkspace(let workspace):
                return "editWorkspace-\(workspace.id.uuidString)"
            case .exportWorkspace(let workspace):
                return "exportWorkspace-\(workspace.id.uuidString)"
            case .importPreview(let preview):
                return "importPreview-\(preview.id)"
            }
        }
    }

    private struct WorkspaceTransferAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @State private var sheetRoute: SheetRoute? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true
    @AppStorage("icloud_useCloud") private var desiredUseICloud: Bool = false
    @AppStorage("icloud_activeUseCloud") private var activeUseICloud: Bool = false
    @AppStorage("icloud_bootstrapStartedAt") private var iCloudBootstrapStartedAt: Double = 0

    @State private var showingICloudUnavailable: Bool = false
    @State private var showingWorkspaceDeleteConfirm: Bool = false
    @State private var pendingWorkspaceDeleteName: String = ""
    @State private var pendingWorkspaceDeleteOffsets: IndexSet? = nil
    @State private var exportSections: Set<WorkspaceTransferSection> = Set(WorkspaceTransferSection.allCases)
    @State private var exportDocument: WorkspaceArchiveDocument? = nil
    @State private var exportFilename: String = "Offshore-Workspace.json"
    @State private var showingFileExporter: Bool = false
    @State private var showingFileImporter: Bool = false
    @State private var pendingImportArchive: WorkspaceArchive? = nil
    @State private var transferAlert: WorkspaceTransferAlert? = nil

    private var workspaceDiscoveryPhase: ICloudBootstrap.WorkspaceDiscoveryPhase {
        ICloudBootstrap.workspaceDiscoveryPhase(
            useICloud: activeUseICloud,
            startedAt: iCloudBootstrapStartedAt,
            workspaceCount: workspaces.count
        )
    }

    var body: some View {
        List {
            dataSourceSection

            Section("Workspaces") {
                WorkspaceListRows(
                    workspaces: workspaces,
                    selectedWorkspaceID: selectedWorkspaceID,
                    usesICloud: activeUseICloud,
                    discoveryPhase: workspaceDiscoveryPhase,
                    showsSelectionHint: true,
                    onSelect: { workspace in
                        selectedWorkspaceID = workspace.id.uuidString
                    },
                    onEdit: { workspace in
                        sheetRoute = .editWorkspace(workspace)
                    },
                    onDelete: { workspace in
                        requestDelete(workspace)
                    }
                )
            }
        }
        .navigationTitle("Workspaces")
        .onChange(of: workspaces.count) { _, newCount in
            if activeUseICloud, newCount > 0 {
                ICloudBootstrap.logFirstWorkspaceAppearance(
                    startedAt: iCloudBootstrapStartedAt,
                    workspaceCount: newCount
                )
                iCloudBootstrapStartedAt = 0
            }
        }
        .alert("iCloud Unavailable", isPresented: $showingICloudUnavailable) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("To use iCloud sync, sign in to iCloud in the Settings app, then try again.")
        }
        .alert("Delete Workspace?", isPresented: $showingWorkspaceDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let offsets = pendingWorkspaceDeleteOffsets {
                    onDelete(offsets)
                }
                pendingWorkspaceDeleteOffsets = nil
                pendingWorkspaceDeleteName = ""
            }
            Button("Cancel", role: .cancel) {
                pendingWorkspaceDeleteOffsets = nil
                pendingWorkspaceDeleteName = ""
            }
        } message: {
            if pendingWorkspaceDeleteName.isEmpty {
                Text("This workspace will be deleted.")
            } else {
                Text("“\(pendingWorkspaceDeleteName)” will be deleted.")
            }
        }
        .alert(item: $transferAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") {
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                }
            }

            if #available(iOS 26.0, macCatalyst 26.0, *) {
                ToolbarItemGroup(placement: .primaryAction) {
                    exportToolbarButton
                }

                ToolbarSpacer(.flexible, placement: .primaryAction)

                ToolbarItemGroup(placement: .primaryAction) {
                    workspaceActionsMenu
                }
            } else {
                ToolbarItemGroup(placement: .primaryAction) {
                    exportToolbarButton
                    workspaceActionsMenu
                }
            }
        }
        .sheet(item: $sheetRoute) { route in
            switch route {
            case .restartRequired:
                RestartRequiredView(
                    title: "Restart Required",
                    message: AppRestartService.restartRequiredMessage(
                        debugMessage: "Will take effect the next time you quit and relaunch the app."
                    ),
                    primaryButtonTitle: AppRestartService.closeAppButtonTitle,
                    onPrimary: { AppRestartService.closeAppOrDismiss { sheetRoute = nil } }
                )
                .presentationDetents([.large])

            case .addWorkspace:
                NavigationStack {
                    AddWorkspaceView(onCreate: onCreate)
                }

            case .editWorkspace(let workspace):
                NavigationStack {
                    EditWorkspaceView(workspace: workspace)
                }

            case .exportWorkspace(let workspace):
                NavigationStack {
                    WorkspaceExportReviewView(
                        workspaceName: workspace.name,
                        selectedSections: $exportSections,
                        onCancel: { sheetRoute = nil },
                        onExport: { sections in
                            prepareExport(workspace: workspace, sections: sections)
                        }
                    )
                }

            case .importPreview(let preview):
                NavigationStack {
                    WorkspaceImportPreviewView(
                        preview: preview,
                        onCancel: {
                            pendingImportArchive = nil
                            sheetRoute = nil
                        },
                        onImport: importPendingArchive
                    )
                }
            }
        }
        .fileExporter(
            isPresented: $showingFileExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { result in
            exportDocument = nil
            switch result {
            case .success:
                break
            case .failure(let error):
                showTransferAlert(title: "Export Failed", error: error)
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
    }

    // MARK: - Actions

    private var selectedWorkspace: Workspace? {
        guard let selectedID = UUID(uuidString: selectedWorkspaceID) else { return nil }
        return workspaces.first { $0.id == selectedID }
    }

    private var exportToolbarButton: some View {
        Button("Export Workspace", systemImage: "square.and.arrow.up") {
            showExportReview()
        }
        .disabled(selectedWorkspace == nil)
        .labelStyle(.iconOnly)
    }

    private var workspaceActionsMenu: some View {
        Menu("Workspace Actions", systemImage: "plus") {
            Button("Add Workspace", systemImage: "plus") {
                sheetRoute = .addWorkspace
            }

            Button("Import Workspace", systemImage: "square.and.arrow.down") {
                showingFileImporter = true
            }
        }
        .labelStyle(.iconOnly)
    }

    private func requestDelete(_ workspace: Workspace) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        let offsets = IndexSet(integer: index)

        if confirmBeforeDeleting {
            pendingWorkspaceDeleteName = workspace.name
            pendingWorkspaceDeleteOffsets = offsets
            showingWorkspaceDeleteConfirm = true
        } else {
            onDelete(offsets)
        }
    }

    private func showExportReview() {
        guard let selectedWorkspace else {
            transferAlert = WorkspaceTransferAlert(
                title: "Export Failed",
                message: "Choose a workspace before exporting."
            )
            return
        }

        exportSections = Set(WorkspaceTransferSection.allCases)
        sheetRoute = .exportWorkspace(selectedWorkspace)
    }

    private func prepareExport(workspace: Workspace, sections: Set<WorkspaceTransferSection>) {
        do {
            let now = Date()
            let archive = try WorkspaceExportService().exportArchive(
                for: workspace,
                sections: sections,
                modelContext: modelContext,
                now: now
            )
            let data = try WorkspaceArchiveCoding.encode(archive)
            exportDocument = WorkspaceArchiveDocument(data: data)
            exportFilename = Self.exportFilename(workspaceName: workspace.name, date: now)
            sheetRoute = nil
            showingFileExporter = true
        } catch {
            showTransferAlert(title: "Export Failed", error: error)
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else {
                transferAlert = WorkspaceTransferAlert(
                    title: "Import Failed",
                    message: "No file was selected."
                )
                return
            }

            let data = try readImportData(from: url)
            let archive = try WorkspaceArchiveCoding.decode(data)
            let preview = try WorkspaceImportService().preview(for: archive)
            pendingImportArchive = archive
            sheetRoute = .importPreview(preview)
        } catch {
            showTransferAlert(title: "Import Failed", error: error)
        }
    }

    private func importPendingArchive() {
        guard let pendingImportArchive else {
            transferAlert = WorkspaceTransferAlert(
                title: "Import Failed",
                message: "No workspace export is ready to import."
            )
            return
        }

        do {
            let importedWorkspace = try WorkspaceImportService().importArchive(
                pendingImportArchive,
                existingWorkspaces: workspaces,
                modelContext: modelContext
            )
            selectedWorkspaceID = importedWorkspace.id.uuidString
            self.pendingImportArchive = nil
            sheetRoute = nil
        } catch {
            showTransferAlert(title: "Import Failed", error: error)
        }
    }

    private func readImportData(from url: URL) throws -> Data {
        let didAccessSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try Data(contentsOf: url)
    }

    private func showTransferAlert(title: String, error: Error) {
        if let localizedError = error as? LocalizedError,
           let message = localizedError.errorDescription,
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            transferAlert = WorkspaceTransferAlert(title: title, message: message)
        } else {
            transferAlert = WorkspaceTransferAlert(title: title, message: (error as NSError).localizedDescription)
        }
    }

    private static func exportFilename(workspaceName: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "Offshore-Workspace-\(sanitizedFilenameComponent(workspaceName))-\(formatter.string(from: date)).json"
    }

    private static func sanitizedFilenameComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "-"
        }.joined()

        return cleaned.isEmpty ? "Workspace" : cleaned
    }

}

// MARK: - Data Source

extension WorkspacePickerView {

    private var dataSourceSection: some View {
        Section("Data Source") {
            Button {
                handleOnDeviceRowTapped()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "iphone")
                        .foregroundStyle(.secondary)
                    Text("On Device")
                    Spacer()
                    dataSourceTrailingIcon(isActive: !activeUseICloud, isDesired: !desiredUseICloud)
                }
            }

            Button {
                handleICloudRowTapped()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "icloud")
                        .foregroundStyle(.tint)
                    Text("iCloud")
                    Spacer()
                    dataSourceTrailingIcon(isActive: activeUseICloud, isDesired: desiredUseICloud)
                }
            }
        }
    }

    @ViewBuilder
    private func dataSourceTrailingIcon(isActive: Bool, isDesired: Bool) -> some View {
        if isActive {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.tint)
        } else if isDesired != isActive {
            Image(systemName: "arrow.clockwise.circle")
                .foregroundStyle(.tint)
                .accessibilityLabel("Restart required")
        }
    }

    private var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private func handleICloudRowTapped() {
        guard isICloudAvailable else {
            showingICloudUnavailable = true
            return
        }

        guard !activeUseICloud else { return }
        requestSwitchToICloud()
    }

    private func handleOnDeviceRowTapped() {
        guard activeUseICloud else { return }
        requestSwitchToOnDevice()
    }

    private func requestSwitchToICloud() {
        desiredUseICloud = true
        if desiredUseICloud != activeUseICloud {
            sheetRoute = .restartRequired
        }
    }

    private func requestSwitchToOnDevice() {
        desiredUseICloud = false
        if desiredUseICloud != activeUseICloud {
            sheetRoute = .restartRequired
        }
    }
}

// MARK: - Workspace Export Review

private struct WorkspaceExportReviewView: View {
    let workspaceName: String
    @Binding var selectedSections: Set<WorkspaceTransferSection>
    let onCancel: () -> Void
    let onExport: (Set<WorkspaceTransferSection>) -> Void

    var body: some View {
        Form {
            Section("Workspace") {
                LabeledContent("Name", value: workspaceName)
            }

            Section("Included Data") {
                ForEach(WorkspaceTransferSection.userVisibleCases) { section in
                    Toggle(isOn: binding(for: section)) {
                        Label(section.displayTitle, systemImage: section.systemImage)
                    }
                }
            }
        }
        .navigationTitle("Export Workspace")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel", action: onCancel)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Export") {
                    onExport(selectedSections)
                }
                .disabled(selectedSections.intersection(Self.userVisibleSectionSet).isEmpty)
            }
        }
    }

    private static var userVisibleSectionSet: Set<WorkspaceTransferSection> {
        Set(WorkspaceTransferSection.userVisibleCases)
    }

    private func binding(for section: WorkspaceTransferSection) -> Binding<Bool> {
        Binding(
            get: { selectedSections.contains(section) },
            set: { isSelected in
                if isSelected {
                    selectedSections.insert(section)
                } else {
                    selectedSections.remove(section)
                }
            }
        )
    }
}

// MARK: - Workspace Import Preview

private struct WorkspaceImportPreviewView: View {
    let preview: WorkspaceImportPreview
    let onCancel: () -> Void
    let onImport: () -> Void

    var body: some View {
        Form {
            Section("Workspace") {
                LabeledContent("Name", value: preview.workspaceName)
                LabeledContent("Records", value: AppNumberFormat.integer(preview.counts.userVisibleTotalRecords))
            }

            Section("Included Data") {
                ForEach(preview.selectedSections.filter { $0 != .marinaAliases }) { section in
                    Label(section.displayTitle, systemImage: section.systemImage)
                }
            }

            Section("Counts") {
                ForEach(countRows) { row in
                    LabeledContent(row.title, value: AppNumberFormat.integer(row.count))
                }
            }
        }
        .navigationTitle("Import Workspace")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel", action: onCancel)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Import", action: onImport)
            }
        }
    }

    private var countRows: [WorkspaceImportCountRow] {
        [
            WorkspaceImportCountRow(title: "Budgets", count: preview.counts.budgets),
            WorkspaceImportCountRow(title: "Budget Links", count: preview.counts.budgetCardLinks + preview.counts.budgetPresetLinks + preview.counts.budgetCategoryLimits),
            WorkspaceImportCountRow(title: "Cards", count: preview.counts.cards),
            WorkspaceImportCountRow(title: "Categories", count: preview.counts.categories),
            WorkspaceImportCountRow(title: "Presets", count: preview.counts.presets),
            WorkspaceImportCountRow(title: "Planned Expenses", count: preview.counts.plannedExpenses),
            WorkspaceImportCountRow(title: "Variable Expenses", count: preview.counts.variableExpenses),
            WorkspaceImportCountRow(title: "Reconciliation Records", count: preview.counts.allocationAccounts + preview.counts.expenseAllocations + preview.counts.allocationSettlements),
            WorkspaceImportCountRow(title: "Savings Records", count: preview.counts.savingsAccounts + preview.counts.savingsLedgerEntries),
            WorkspaceImportCountRow(title: "Expense Import Rules", count: preview.counts.importMerchantRules),
            WorkspaceImportCountRow(title: "Income Records", count: preview.counts.incomeSeries + preview.counts.incomes)
        ].filter { $0.count > 0 }
    }
}

private struct WorkspaceImportCountRow: Identifiable {
    let id = UUID()
    let title: String
    let count: Int
}

#Preview("Workspace Picker") {
    let container = PreviewSeed.makeContainer()

    NavigationStack {
        WorkspacePickerView(
            workspaces: [
                Workspace(name: "Personal", hexColor: "#3B82F6"),
                Workspace(name: "Work", hexColor: "#10B981")
            ],
            selectedWorkspaceID: .constant(""),
            showsCloseButton: true,
            onCreate: { _, _ in },
            onDelete: { _ in }
        )
    }
    .modelContainer(container)
}
