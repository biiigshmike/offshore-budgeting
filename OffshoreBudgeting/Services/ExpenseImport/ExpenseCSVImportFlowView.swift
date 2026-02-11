import SwiftUI
import SwiftData
import PhotosUI
import Photos
import UniformTypeIdentifiers

struct ExpenseCSVImportFlowView: View {
    let workspace: Workspace
    let card: Card

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @StateObject private var vm = ExpenseCSVImportViewModel()

    @State private var showingFileImporter: Bool = false
    @State private var showingPhotoPicker: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedFileName: String? = nil

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Card")
                    Spacer()
                    Text(card.name)
                        .foregroundStyle(.secondary)
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
                     ? "You can import one file at a time (CSV, PDF, or image) from Files or Photos. You will review everything before saving."
                     : "Use the toggle switch for any row you want to save and have automatically recognized next time. It will help make future imports faster.")
            }

            if vm.state == .idle {
                Section {
                    Text("Choose a CSV, PDF, or image from Files or Photos to begin.")
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
                    sectionView(title: "Income / Payments", rows: vm.paymentRows)
                }

                if !vm.possibleDuplicateRows.isEmpty {
                    sectionView(title: "Possible Duplicates", rows: vm.possibleDuplicateRows)
                }

                if !vm.needsMoreDataRows.isEmpty {
                    sectionView(title: "Needs More Data", rows: vm.needsMoreDataRows)
                }

                Section {
                    Text(vm.commitSummaryText)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Import Expenses")
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
        Section {
            ForEach(rows) { row in
                ExpenseCSVImportRowView(
                    row: row,
                    allCategories: vm.categories,
                    onToggleInclude: { vm.toggleInclude(rowID: row.id) },
                    onSetDate: { date in vm.setDate(rowID: row.id, date: date) },
                    onSetMerchant: { text in vm.setMerchant(rowID: row.id, merchant: text) },
                    onSetCategory: { category in vm.setCategory(rowID: row.id, category: category) },
                    onSetKind: { kind in vm.setKind(rowID: row.id, kind: kind) },
                    onToggleRemember: { vm.toggleRemember(rowID: row.id) }
                )
            }
        } header: {
            Text(title)
        }
    }
}
