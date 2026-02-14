import SwiftUI
import SwiftData
import PhotosUI
import Photos
import UniformTypeIdentifiers

struct ExpenseCSVImportFlowView: View {
    let workspace: Workspace
    let card: Card?
    let mode: ExpenseCSVImportViewModel.ImportMode
    let initialClipboardText: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @StateObject private var vm: ExpenseCSVImportViewModel

    @State private var showingFileImporter: Bool = false
    @State private var showingPhotoPicker: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedFileName: String? = nil

    init(workspace: Workspace, card: Card, initialClipboardText: String? = nil) {
        self.workspace = workspace
        self.card = card
        self.mode = .cardTransactions
        self.initialClipboardText = initialClipboardText
        _vm = StateObject(wrappedValue: ExpenseCSVImportViewModel(mode: .cardTransactions))
    }

    init(workspace: Workspace, initialClipboardText: String? = nil) {
        self.workspace = workspace
        self.card = nil
        self.mode = .incomeOnly
        self.initialClipboardText = initialClipboardText
        _vm = StateObject(wrappedValue: ExpenseCSVImportViewModel(mode: .incomeOnly))
    }

    var body: some View {
        List {
            Section {
                if let card {
                    HStack {
                        Text("Card")
                        Spacer()
                        Text(card.name)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        Text("Destination")
                        Spacer()
                        Text("Income")
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text("File")
                    Spacer()
                    Text(selectedFileName ?? "None")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Menu {
                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("Import from Files", systemImage: "doc")
                    }

                    Button {
                        showingPhotoPicker = true
                    } label: {
                        Label("Import from Photos", systemImage: "photo.on.rectangle")
                    }
                } label: {
                    Label(selectedFileName == nil ? "Choose Source" : "Choose Another Source", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Import")
            } footer: {
                Text(selectedFileName == nil
                     ? importHintText
                     : "Use the toggle switch for any row you want to save and have automatically recognized to speed up future imports.")
            }

            if vm.state == .idle {
                Section {
                    Text(idlePromptText)
                        .foregroundStyle(.secondary)
                }
            }

            if vm.state == .loading {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Parsing file…")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if case .failed(let message) = vm.state {
                Section {
                    Text(message)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Error")
                }
            }

            if vm.state == .loaded {
                if !vm.readyRows.isEmpty {
                    sectionView(title: "Ready to Import", rows: vm.readyRows)
                }

                if !vm.possibleMatchRows.isEmpty {
                    sectionView(title: "Possible Matches", rows: vm.possibleMatchRows)
                }

                if !vm.paymentRows.isEmpty {
                    sectionView(title: paymentSectionTitle, rows: vm.paymentRows)
                }

                if !vm.possibleDuplicateRows.isEmpty {
                    sectionView(title: "Possible Duplicates", rows: vm.possibleDuplicateRows)
                }

                if !vm.needsMoreDataRows.isEmpty {
                    sectionView(title: "Needs More Data", rows: vm.needsMoreDataRows)
                }

                if !vm.blockedRows.isEmpty {
                    sectionView(title: "Skipped (Expenses)", rows: vm.blockedRows)
                }

                Section {
                    Text(vm.commitSummaryText)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(navigationTitle)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Import") {
                    vm.commitImport(workspace: workspace, card: card, modelContext: modelContext)
                    dismiss()
                }
                .disabled(!(vm.state == .loaded && vm.canCommit))
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.commaSeparatedText, .pdf, .image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                selectedFileName = url.lastPathComponent
                vm.load(url: url, workspace: workspace, card: card, modelContext: modelContext, referenceDate: nil)

            case .failure(let error):
                vm.state = .failed(error.localizedDescription)
            }
        }
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $selectedPhotoItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await importFromPhotos(item: newItem)
            }
        }
        .onAppear {
            vm.prepare(workspace: workspace, modelContext: modelContext)

            let clipboard = (initialClipboardText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !clipboard.isEmpty, vm.state == .idle {
                selectedFileName = "Clipboard"
                vm.loadClipboard(
                    text: clipboard,
                    workspace: workspace,
                    card: card,
                    modelContext: modelContext,
                    referenceDate: .now
                )
            }
        }
    }

    // MARK: - Photos Import

    @MainActor
    private func importFromPhotos(item: PhotosPickerItem) async {
        defer {
            selectedPhotoItem = nil
        }

        do {
            vm.state = .loading

            guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else {
                vm.state = .failed("No image data was returned from Photos.")
                return
            }

            let fileExtension = preferredImageExtension(for: item)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("offshore-photo-import-\(UUID().uuidString).\(fileExtension)")

            try data.write(to: tempURL, options: .atomic)
            selectedFileName = "Photo (\(tempURL.lastPathComponent))"
            let referenceDate = photoReferenceDate(for: item)
            vm.load(url: tempURL, workspace: workspace, card: card, modelContext: modelContext, referenceDate: referenceDate)
            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            vm.state = .failed("Could not load the selected photo.")
        }
    }

    private func photoReferenceDate(for item: PhotosPickerItem) -> Date? {
        guard let identifier = item.itemIdentifier else { return nil }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = assets.firstObject else { return nil }
        return asset.creationDate ?? asset.modificationDate
    }

    private func preferredImageExtension(for item: PhotosPickerItem) -> String {
        if let type = item.supportedContentTypes.first(where: { $0.conforms(to: .image) }),
           let ext = type.preferredFilenameExtension,
           !ext.isEmpty {
            return ext
        }
        return "jpg"
    }

    @ViewBuilder
    private func sectionView(title: String, rows: [ExpenseCSVImportRow]) -> some View {
        if let firstRow = rows.first {
            Section {
                rowView(firstRow)
            } header: {
                Text(title)
            }

            ForEach(rows.dropFirst()) { row in
                Section {
                    rowView(row)
                }
            }
        }
    }

    private func rowView(_ row: ExpenseCSVImportRow) -> some View {
        ExpenseCSVImportRowView(
            row: row,
            allCategories: vm.categories,
            allAllocationAccounts: vm.allocationAccounts,
            allowKindEditing: mode == .cardTransactions,
            onToggleInclude: { vm.toggleInclude(rowID: row.id) },
            onSetDate: { date in vm.setDate(rowID: row.id, date: date) },
            onSetMerchant: { text in vm.setMerchant(rowID: row.id, merchant: text) },
            onSetAmount: { text in vm.setAmount(rowID: row.id, amountText: text) },
            onSetCategory: { category in vm.setCategory(rowID: row.id, category: category) },
            onSetKind: { kind in vm.setKind(rowID: row.id, kind: kind) },
            onSetAllocationAccount: { account in vm.setAllocationAccount(rowID: row.id, account: account) },
            onSetAllocationAmount: { text in vm.setAllocationAmount(rowID: row.id, amountText: text) },
            onToggleRemember: { vm.toggleRemember(rowID: row.id) }
        )
    }

    private var navigationTitle: String {
        mode == .cardTransactions ? "Import Expenses" : "Import Income"
    }

    private var paymentSectionTitle: String {
        mode == .cardTransactions ? "Income / Payments" : "Income"
    }

    private var idlePromptText: String {
        mode == .cardTransactions
            ? "Choose a CSV, PDF, or image from Files or Photos to begin."
            : "Choose a CSV, PDF, or image from Files or Photos to begin. Expense rows will be skipped."
    }

    private var importHintText: String {
        mode == .cardTransactions
            ? "You can import one file at a time (CSV, PDF, or image) from Files or Photos. You will review everything before saving."
            : "You can import one file at a time (CSV, PDF, or image) from Files or Photos. Expense rows are skipped in Income import."
    }
}
