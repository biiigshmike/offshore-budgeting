import SwiftUI

struct DetailListAccessory<SortMode: Hashable>: View {
    let categories: [Category]
    @Binding var selectedCategoryIDs: Set<UUID>
    var expenseScope: Binding<ExpenseScope>? = nil
    @Binding var sortMode: SortMode
    let name: (ascending: SortMode, descending: SortMode)
    let amount: (ascending: SortMode, descending: SortMode)
    let date: (ascending: SortMode, descending: SortMode)

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if targetEnvironment(macCatalyst)
    @State private var showingCategoryPopover = false
    #endif

    private var categoriesTitle: String {
        String(localized: "categories.title", defaultValue: "Categories", comment: "Title for categories section.")
    }

    private var selectedCategories: [Category] {
        categories.filter { selectedCategoryIDs.contains($0.id) }
    }

    private var sortOptions: [(mode: SortMode, title: Text, shortTitle: Text)] {
        [
            (date.descending, Text("Newest first"), Text("Newest")),
            (date.ascending, Text("Oldest first"), Text("Oldest")),
            (amount.descending, Text("Highest amount first"), Text("Highest")),
            (amount.ascending, Text("Lowest amount first"), Text("Lowest")),
            (name.ascending, Text("Name A–Z"), Text("A–Z")),
            (name.descending, Text("Name Z–A"), Text("Z–A"))
        ]
    }

    var body: some View {
        glassBar
//            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
            .onChange(of: categories.map(\.id), initial: true) { _, categoryIDs in
                let validSelection = selectedCategoryIDs.intersection(categoryIDs)
                if validSelection != selectedCategoryIDs {
                    selectedCategoryIDs = validSelection
                }
            }
    }

    private var glassBar: some View {
        bar.background {
            if #available(iOS 26.0, macCatalyst 26.0, *) {
                Color.clear
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .allowsHitTesting(false)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.regularMaterial)
                    .allowsHitTesting(false)
            }
        }
    }

    private var bar: some View {
        ViewThatFits(in: .horizontal) {
            if !dynamicTypeSize.isAccessibilitySize {
                controls(compact: false)
            }
            controls(compact: true)
        }
        .font(.subheadline.weight(.medium))
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .foregroundStyle(.primary)
        .padding(.horizontal, 4)
    }

    private func controls(compact: Bool) -> some View {
        HStack(spacing: 0) {
            if let expenseScope {
                scopeMenu(expenseScope, compact: compact)
                separator
            }
            categoriesMenu(compact: compact)
            separator
            sortMenu(compact: compact)
        }
    }

    private var separator: some View {
        Divider().frame(height: 20).accessibilityHidden(true)
    }

    private func scopeMenu(_ selection: Binding<ExpenseScope>, compact: Bool) -> some View {
        let typeTitle = String(localized: "common.type", defaultValue: "Type", comment: "Label for type picker.")
        let current = scopeTitle(selection.wrappedValue)
        return Menu {
            Picker(typeTitle, selection: selection) {
                Text(scopeTitle(.planned)).tag(ExpenseScope.planned)
                Text(scopeTitle(.unified)).tag(ExpenseScope.unified)
                Text(scopeTitle(.variable)).tag(ExpenseScope.variable)
            }
            .pickerStyle(.inline)
        } label: {
            controlLabel(Text(current), symbol: "square.stack", compact: compact)
        }
        .accessibilityLabel(Text(typeTitle))
        .accessibilityValue(Text(current))
        .accessibilityIdentifier("detailList.expenseType")
    }

    private func sortMenu(compact: Bool) -> some View {
        let sortTitle = String(localized: "common.sort", defaultValue: "Sort", comment: "Label for sort actions.")
        let options = sortOptions
        let current = options.first { $0.mode == sortMode }
        return Menu {
            Picker(sortTitle, selection: $sortMode) {
                ForEach(options.indices, id: \.self) { index in
                    options[index].title.tag(options[index].mode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            controlLabel(current?.shortTitle ?? Text(sortTitle),
                         symbol: "arrow.up.arrow.down", compact: compact)
        }
        .accessibilityLabel(Text(sortTitle))
        .accessibilityValue(current?.title ?? Text(""))
        .accessibilityIdentifier("detailList.sort")
    }

    private func categoriesMenu(compact: Bool) -> some View {
        let selection = selectedCategories
        return Group {
            #if targetEnvironment(macCatalyst)
            Button {
                showingCategoryPopover = true
            } label: {
                categoriesLabel(selection: selection, compact: compact)
            }
            .popover(isPresented: $showingCategoryPopover, arrowEdge: .bottom) {
                categoryPopover
            }
            #else
            Menu {
                categoryBulkAction
                    .menuActionDismissBehavior(.disabled)

                Divider()

                ForEach(categories, id: \.id) { category in
                    Toggle(isOn: categorySelection(category.id)) {
                        CategoryMenuLabel(category: category)
                    }
                    .accessibilityLabel(Text(category.name))
                    .menuActionDismissBehavior(.disabled)
                }
            } label: {
                categoriesLabel(selection: selection, compact: compact)
            }
            .toggleStyle(.automatic)
            .menuOrder(.fixed)
            #endif
        }
        .disabled(categories.isEmpty)
        .accessibilityLabel(Text(categoriesTitle))
        .accessibilityValue(selection.isEmpty
            ? Text("All categories")
            : Text(verbatim: selection.map(\.name).formatted(.list(type: .and))))
        .accessibilityIdentifier("detailList.categories")
    }

    private func categoriesLabel(selection: [Category], compact: Bool) -> some View {
        ZStack {
            controlLabel(Text(categoriesTitle), symbol: "line.3.horizontal.decrease", compact: compact)
                .opacity(selection.isEmpty ? 1 : 0)

            if !selection.isEmpty {
                DetailCategoryDots(categories: selection)
                    .padding(.horizontal, 4)
            }
        }
        .frame(minWidth: 52, maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var categoryBulkAction: some View {
        let categoryIDs = Set(categories.map(\.id))
        let allSelected = categoryIDs.isSubset(of: selectedCategoryIDs)
        return Button(allSelected ? LocalizedStringKey("Deselect All") : LocalizedStringKey("Select All")) {
            selectedCategoryIDs = allSelected ? [] : categoryIDs
        }
    }

    private func categorySelection(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedCategoryIDs.contains(id) },
            set: { isSelected in
                if isSelected {
                    selectedCategoryIDs.insert(id)
                } else {
                    selectedCategoryIDs.remove(id)
                }
            }
        )
    }

    #if targetEnvironment(macCatalyst)
    private var categoryPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            categoryBulkAction
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(categories, id: \.id) { category in
                        let selection = categorySelection(category.id)
                        Button {
                            selection.wrappedValue.toggle()
                        } label: {
                            HStack {
                                CategoryMenuLabel(category: category)
                                    .labelStyle(.titleAndIcon)
                                Spacer()
                                Image(systemName: "checkmark")
                                    .opacity(selection.wrappedValue ? 1 : 0)
                                    .accessibilityHidden(true)
                            }
                            .padding(.horizontal, 8)
                            .frame(minHeight: 36)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(category.name))
                        .accessibilityAddTraits(selection.wrappedValue ? .isSelected : [])
                    }
                }
            }
            .frame(height: min(CGFloat(categories.count) * 36, 320))
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(12)
        .frame(width: 280)
    }
    #endif

    private func controlLabel(_ title: Text, symbol: String, compact: Bool) -> some View {
        HStack(spacing: 6) {
            if compact {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
            } else {
                Image(systemName: symbol)
                title
            }
        }
        .fixedSize()
        .padding(.horizontal, compact ? 6 : 12)
        .frame(minWidth: TintedGlassNavigationButton.minimumSize,
               minHeight: TintedGlassNavigationButton.minimumGlassHeight)
        .contentShape(Rectangle())
    }

    private func scopeTitle(_ scope: ExpenseScope) -> String {
        switch scope {
        case .planned:
            String(localized: "expenseScope.planned", defaultValue: "Planned", comment: "Expense scope option for planned expenses.")
        case .unified:
            String(localized: "expenseScope.unified", defaultValue: "Combined", comment: "Expense scope option for combined expenses.")
        case .variable:
            String(localized: "expenseScope.variable", defaultValue: "Variable", comment: "Expense scope option for variable expenses.")
        }
    }
}

private struct DetailCategoryDots: View {
    let categories: [Category]
    private let dotSize: CGFloat = 8
    private let spacing: CGFloat = 4
    @ScaledMetric(relativeTo: .footnote) private var overflowLineHeight: CGFloat = 18

    var body: some View {
        GeometryReader { proxy in
            let capacity = Int((proxy.size.width + spacing) / (dotSize + spacing))
            let maximumDots = min(capacity, categories.count)
            ViewThatFits(in: .horizontal) {
                ForEach(Array((0...maximumDots).reversed()), id: \.self) { visibleCount in
                    HStack(spacing: spacing) {
                        ForEach(categories.prefix(visibleCount), id: \.id) { category in
                            categoryDot(category)
                        }
                        if visibleCount < categories.count {
                            Text("+\(categories.count - visibleCount)")
                                .font(.footnote.monospacedDigit())
                        }
                    }
                    .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: max(overflowLineHeight + 8, TintedGlassNavigationButton.minimumGlassHeight))
        .accessibilityHidden(true)
    }
}

private func categoryDot(_ category: Category) -> some View {
    Circle()
        .fill(Color(hex: category.hexColor) ?? Color.secondary.opacity(0.35))
        .frame(width: 8, height: 8)
        .accessibilityHidden(true)
}
