import SwiftUI
import SwiftData

@available(iOS 26.0, macOS 26.0, *)
struct MarinaView: View {
    let workspace: Workspace
    let startDate: Date
    let endDate: Date
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller: MarinaConversationController?

    var body: some View {
        Group {
            if let controller {
                MarinaConversationView(workspace: workspace, controller: controller)
            } else {
                ProgressView("Opening Marina")
            }
        }
        .navigationTitle("Marina")
        .task(id: workspace.id) {
            controller?.cancel()
            controller = MarinaConversationController(context: modelContext, workspace: workspace, startDate: startDate, endDate: endDate)
        }
        .onDisappear { controller?.cancel() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { controller?.refreshAvailability() }
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
private struct MarinaConversationView: View {
    let workspace: Workspace
    @Bindable var controller: MarinaConversationController
    @State private var draft = ""
    @State private var showingHistory = false
    @State private var selectedRecord: MarinaRecord?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if controller.messages.isEmpty {
                        ContentUnavailableView("Understand your budget", systemImage: "sparkles", description: Text("Ask Marina to find a transaction, compare spending, or explain your financial statistics. Answers describe your records without financial advice."))
                    }
                    ForEach(controller.messages) { message in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(message.role == .user ? "You" : "Marina").font(.headline)
                                Spacer()
                                Text(message.date, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(message.text).textSelection(.enabled)
                            ForEach(message.results) { result in
                                MarinaResultView(result: result) { selectedRecord = $0 }
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                        .id(message.id)
                    }
                    if controller.isResponding {
                        ProgressView("Marina is looking at your records…")
                    }
                    if let error = controller.errorMessage {
                        VStack(alignment: .leading) {
                            Text(error).foregroundStyle(.secondary)
                            Button("Try again", systemImage: "arrow.clockwise") { controller.retry() }
                                .disabled(controller.isResponding)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: 850)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: controller.messages.count) {
                if let id = controller.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Conversation history", systemImage: "clock") {
                    controller.refreshHistory()
                    showingHistory = true
                }
                .accessibilityIdentifier("marina.history")
                Button("New conversation", systemImage: "square.and.pencil") {
                    controller.newConversation()
                    draft = ""
                }
                .accessibilityIdentifier("marina.newConversation")
            }
        }
        .sheet(isPresented: $showingHistory) {
            NavigationStack {
                List {
                    ForEach(controller.conversations) { conversation in
                        Button {
                            controller.open(conversation)
                            draft = ""
                            showingHistory = false
                        } label: {
                            VStack(alignment: .leading) {
                                Text(conversation.title.isEmpty ? "Conversation" : conversation.title)
                                Text(conversation.updatedAt, format: .dateTime.month().day().year()).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        let records = offsets.map { controller.conversations[$0] }
                        records.forEach { controller.delete($0) }
                    }
                }
                .overlay {
                    if controller.conversations.isEmpty {
                        ContentUnavailableView("No conversations yet", systemImage: "bubble.left.and.bubble.right")
                    }
                }
                .navigationTitle("Conversations")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showingHistory = false }
                    }
                }
            }
        }
        .sheet(item: $selectedRecord) { record in
            NavigationStack {
                MarinaRecordDestination(workspace: workspace, record: record)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { selectedRecord = nil }
                        }
                    }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = controller.availabilityMessage {
                Text(message).font(.footnote).foregroundStyle(.secondary)
                Button("Check again") { controller.refreshAvailability() }.font(.footnote)
            }
            HStack(alignment: .bottom) {
                TextField("Ask about your budget", text: $draft, axis: .vertical)
                    .accessibilityIdentifier("marina.composer")
                    .lineLimit(1...6)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!controller.canSend)
                if controller.isResponding {
                    Button("Cancel", systemImage: "stop.circle") { controller.cancel() }.labelStyle(.iconOnly)
                } else {
                    Button("Send", systemImage: "arrow.up.circle.fill", action: send)
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !controller.canSend)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        controller.send(text)
    }
}
