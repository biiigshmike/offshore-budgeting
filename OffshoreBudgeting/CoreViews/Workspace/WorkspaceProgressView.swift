import SwiftUI
import SwiftData

struct WorkspaceProgressView: View {
    let workspace: Workspace
    let showsHandoffGuidance: Bool
    private let onBudgetCreated: ((UUID) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var cards: [Card]
    @Query private var categories: [Category]
    @Query private var presets: [Preset]
    @Query private var incomes: [Income]
    @Query private var budgets: [Budget]
    @State private var activeStep: WorkspaceProgressStep?
    @State private var showingRefreshError = false

    init(workspace: Workspace, showsHandoffGuidance: Bool = false, onBudgetCreated: ((UUID) -> Void)? = nil) {
        self.workspace = workspace
        self.showsHandoffGuidance = showsHandoffGuidance
        self.onBudgetCreated = onBudgetCreated
        let workspaceID = workspace.id

        var cardDescriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.workspace?.id == workspaceID })
        cardDescriptor.fetchLimit = 1
        _cards = Query(cardDescriptor)
        var categoryDescriptor = FetchDescriptor<Category>(predicate: #Predicate { $0.workspace?.id == workspaceID })
        categoryDescriptor.fetchLimit = 1
        _categories = Query(categoryDescriptor)
        var presetDescriptor = FetchDescriptor<Preset>(predicate: #Predicate { $0.workspace?.id == workspaceID })
        presetDescriptor.fetchLimit = 1
        _presets = Query(presetDescriptor)
        var incomeDescriptor = FetchDescriptor<Income>(predicate: #Predicate { $0.workspace?.id == workspaceID })
        incomeDescriptor.fetchLimit = 1
        _incomes = Query(incomeDescriptor)
        var budgetDescriptor = FetchDescriptor<Budget>(predicate: #Predicate { $0.workspace?.id == workspaceID })
        budgetDescriptor.fetchLimit = 1
        _budgets = Query(budgetDescriptor)
    }

    private var completedSteps: Set<WorkspaceProgressStep> {
        WorkspaceProgressService.completedSteps(in: workspace)
    }

    private var incompleteSteps: [WorkspaceProgressStep] {
        WorkspaceProgressStep.allCases.filter { !completedSteps.contains($0) }
    }

    private var existingSteps: Set<WorkspaceProgressStep> {
        var steps = Set<WorkspaceProgressStep>()
        if !cards.isEmpty { steps.insert(.card) }
        if !categories.isEmpty { steps.insert(.category) }
        if !presets.isEmpty { steps.insert(.preset) }
        if !incomes.isEmpty { steps.insert(.income) }
        if !budgets.isEmpty { steps.insert(.budget) }
        return steps
    }

    var body: some View {
        List {
            Section {
                progressSummary
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Each completed step represents a core feature of Offshore Budgeting enabled in this workspace. Steps stay checked even if you later archive or delete an item.")
                    if showsHandoffGuidance {
                        Text("You can return to Workspace Progress in Settings.")
                            .accessibilityIdentifier("workspaceProgressReturnGuidance")
                    }
                }
            }

            Section("Checklist") {
                ForEach(WorkspaceProgressStep.allCases) { step in
                    checklistRow(for: step)
                }
            }

            if showsHandoffGuidance {
                Section {
                    HelpGuideButton()
                }
            }

            if incompleteSteps.isEmpty {
                Section {
                    Label("Workspace setup complete", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.primary)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("workspaceProgressComplete")
                    Text("You've set up all of the core features. You're ready to start budgeting Offshore.")
                        .foregroundStyle(.secondary)
                }
            }

            if WorkspaceProgressService.canHideProgress(in: workspace) {
                Section {
                    Text("To hide this row, go to Settings > General > Maintenance and turn on Hide Workspace Progress.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("workspaceProgressHideGuidance")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Workspace Progress")
        .appSheet(item: $activeStep, onDismiss: refreshProgress) { step in
            NavigationStack {
                addForm(for: step)
            }
        }
        .onAppear(perform: refreshProgress)
        .onChange(of: existingSteps) { _, _ in refreshProgress() }
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .active { refreshProgress() }
        }
        .blocksAutomaticExpenseReview(while: showingRefreshError)
        .alert("Unable to Update Progress", isPresented: $showingRefreshError) {
            Button("Retry", action: refreshProgress)
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your saved milestones are still shown. Try again in a moment.")
        }
    }

    private var progressSummary: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))

        return layout {
            VStack(spacing: 12) {
                progressRing

                Text(Double(WorkspaceProgressService.percentage(in: workspace)) / 100, format: .percent.precision(.fractionLength(0)))
                    .font(.title.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                Text(workspace.name)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(completedSteps.count) of 5 completed")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Workspace progress for \(workspace.name)")
        .accessibilityValue("\(WorkspaceProgressService.percentage(in: workspace)) percent, \(completedSteps.count) of 5 completed")
        .accessibilityIdentifier("workspaceProgressSummary")
    }

    private var progressRing: some View {
        let tint = Color(hex: workspace.hexColor) ?? .accentColor
        return ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: 10)
            Circle()
                .trim(from: 0, to: Double(completedSteps.count) / 5)
                .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 96, height: 96)
        .padding(5)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func checklistRow(for step: WorkspaceProgressStep) -> some View {
        let isComplete = completedSteps.contains(step)
        let needsCard = step == .preset && cards.isEmpty
        let status = isComplete ? String(localized: "Completed") : String(localized: "Not completed")

        if isComplete {
            checklistLabel(for: step, isComplete: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(step.title), \(status). \(step.explanation)")
                .accessibilityIdentifier("workspaceProgressStep_\(step.rawValue)")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    guard !needsCard else { return }
                    activeStep = step
                } label: {
                    checklistLabel(for: step, isComplete: false)
                }
                .buttonStyle(.plain)
                .disabled(needsCard)
                .accessibilityLabel("\(step.title), \(status). \(step.explanation)")
                .accessibilityHint(needsCard
                    ? String(localized: "Add a card first. A preset needs a card for its planned expenses.")
                    : step.actionTitle)
                .accessibilityIdentifier("workspaceProgressStep_\(step.rawValue)")

                if needsCard {
                    Text("Add a card first. A preset needs a card for its planned expenses.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if completedSteps.contains(.card) {
                        Button("Add Card", systemImage: "plus.circle") {
                            activeStep = .card
                        }
                        .buttonStyle(.borderless)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("workspaceProgressRestoreCard")
                    }
                }
            }
        }
    }

    private func checklistLabel(for step: WorkspaceProgressStep, isComplete: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isComplete ? Color.accentColor : Color.secondary)
                .imageScale(.large)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .foregroundStyle(.primary)
                Text(step.explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !isComplete {
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func addForm(for step: WorkspaceProgressStep) -> some View {
        switch step {
        case .card:
            AddCardView(workspace: workspace)
        case .category:
            AddCategoryView(workspace: workspace)
        case .preset:
            AddPresetView(workspace: workspace, offersBudgetAfterSave: true)
        case .income:
            AddIncomeView(workspace: workspace, initialDate: Calendar.current.startOfDay(for: .now))
        case .budget:
            AddBudgetView(workspace: workspace, onCreated: onBudgetCreated)
        }
    }

    private func refreshProgress() {
        do {
            try WorkspaceProgressService.backfill(in: workspace, modelContext: modelContext)
        } catch {
            showingRefreshError = true
        }
    }
}

#Preview("Workspace Progress") {
    let container = PreviewSeed.makeContainer()
    PreviewHost(container: container) { workspace in
        NavigationStack {
            WorkspaceProgressView(workspace: workspace)
        }
    }
}
