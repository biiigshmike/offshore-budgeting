import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ExpenseCSVImportFlowView: View {
    let workspace: Workspace
    let card: Card

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @StateObject private var vm = ExpenseCSVImportViewModel()

    @State private var showingFileImporter: Bool = false
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

                Button {
                    showingFileImporter = true
                } label: {
                    Label(selectedFileName == nil ? "Choose CSV File" : "Choose Another CSV", systemImage: "doc")
                }
            } header: {
                Text("Import")
            } footer: {
                Text(selectedFileName == nil
                     ? "You can import one CSV at a time. You will review everything before saving."
                     : "Use the toggle switch for any row you want to save and have automatically recognized next time. It will help make future imports faster.")
            }

            if vm.state == .idle {
                Section {
                    Text("Choose a CSV to begin.")
                        .foregroundStyle(.secondary)
                }
            }

            if vm.state == .loading {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Parsing CSV…")
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
        .navigationTitle("Import CSV")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
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
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                selectedFileName = url.lastPathComponent
                vm.load(url: url, workspace: workspace, card: card, modelContext: modelContext)

            case .failure(let error):
                vm.state = .failed(error.localizedDescription)
            }
        }
        .onAppear {
            vm.prepare(workspace: workspace, modelContext: modelContext)
        }
    }

    @ViewBuilder
    private func sectionView(title: String, rows: [ExpenseCSVImportRow]) -> some View {
        Section {
            ForEach(rows) { row in
                ExpenseCSVImportRowView(
                    row: row,
                    allCategories: vm.categories,
                    onToggleInclude: { vm.toggleInclude(rowID: row.id) },
                    onSetMerchant: { text in vm.setMerchant(rowID: row.id, merchant: text) },
                    onSetCategory: { category in vm.setCategory(rowID: row.id, category: category) },
                    onToggleRemember: { vm.toggleRemember(rowID: row.id) }
                )
            }
        } header: {
            Text(title)
        }
    }
}
