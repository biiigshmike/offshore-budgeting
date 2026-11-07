import SwiftUI

struct DetailListAccessory<SortMode: Hashable>: View {
    let categories: [Category]
    // nil is the initial unfiltered state. An empty set matches no categories.
    @Binding var selectedCategoryIDs: Set<UUID>?
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
        guard let selectedCategoryIDs else { return categories }
        return categories.filter { selectedCategoryIDs.contains($0.id) }
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
                guard let selectedCategoryIDs else { return }
                let validSelection = selectedCategoryIDs.intersection(categoryIDs)
                if validSelection != selectedCategoryIDs {
                    self.selectedCategoryIDs = validSelection
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
                controls(compact: false, equalWidths: true)
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

    private func controls(compact: Bool, equalWidths: Bool = false) -> some View {
        let layout = equalWidths ? AnyLayout(EqualDetailControlLayout()) : AnyLayout(HStackLayout(spacing: 0))
        return layout {
            if let expenseScope {
                scopeMenu(expenseScope, compact: compact, equalWidths: equalWidths)
                separator
            }
            categoriesMenu
            separator
            sortMenu(compact: compact, equalWidths: equalWidths)
        }
    }

    private var separator: some View {
        Divider().frame(width: 1, height: 20).accessibilityHidden(true)
    }

    private func scopeMenu(_ selection: Binding<ExpenseScope>, compact: Bool, equalWidths: Bool) -> some View {
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
            controlLabel(Text(current), symbol: "square.stack", compact: compact, equalWidths: equalWidths)
        }
        .accessibilityLabel(Text(typeTitle))
        .accessibilityValue(Text(current))
        .accessibilityIdentifier("detailList.expenseType")
    }

    private func sortMenu(compact: Bool, equalWidths: Bool) -> some View {
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
                         symbol: "arrow.up.arrow.down", compact: compact, equalWidths: equalWidths)
        }
        .accessibilityLabel(Text(sortTitle))
        .accessibilityValue(current?.title ?? Text(""))
        .accessibilityIdentifier("detailList.sort")
    }

    private var categoriesMenu: some View {
        let selection = selectedCategories
        let isFiltered = selectedCategoryIDs != nil
        return Group {
            #if targetEnvironment(macCatalyst)
            Button {
                showingCategoryPopover = true
            } label: {
                categoriesLabel(categories: selection, isFiltered: isFiltered)
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
                categoriesLabel(categories: selection, isFiltered: isFiltered)
            }
            .toggleStyle(.automatic)
            .menuOrder(.fixed)
            #endif
        }
        .disabled(categories.isEmpty)
        .accessibilityLabel(Text(categoriesTitle))
        .accessibilityValue(categoryAccessibilityValue(selection))
        .accessibilityIdentifier("detailList.categories")
    }

    private func categoryAccessibilityValue(_ selection: [Category]) -> Text {
        guard selectedCategoryIDs != nil else { return Text("No category filter") }
        guard !selection.isEmpty else { return Text("No categories selected") }
        return Text(verbatim: selection.map(\.name).formatted(.list(type: .and)))
    }

    private func categoriesLabel(categories: [Category], isFiltered: Bool) -> some View {
        DetailCategoryAccessoryLabel(categories: categories, isFiltered: isFiltered, title: categoriesTitle)
            .frame(idealWidth: 0)
            .padding(.horizontal, 8)
            .frame(minWidth: 52, maxWidth: .infinity)
            .contentShape(Rectangle())
    }

    private var categoryBulkAction: some View {
        let categoryIDs = Set(categories.map(\.id))
        let allSelected = selectedCategoryIDs.map { categoryIDs.isSubset(of: $0) } ?? true
        return Button(allSelected ? LocalizedStringKey("Deselect All") : LocalizedStringKey("Select All")) {
            selectedCategoryIDs = allSelected ? [] : categoryIDs
        }
    }

    private func categorySelection(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedCategoryIDs?.contains(id) ?? true },
            set: { isSelected in
                var updatedSelection = selectedCategoryIDs ?? Set(categories.map(\.id))
                if isSelected {
                    updatedSelection.insert(id)
                } else {
                    updatedSelection.remove(id)
                }
                selectedCategoryIDs = updatedSelection
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

    private func controlLabel(_ title: Text, symbol: String, compact: Bool, equalWidths: Bool) -> some View {
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
               maxWidth: equalWidths ? .infinity : nil,
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

private struct EqualDetailControlLayout: Layout {
    static var layoutProperties: LayoutProperties {
        var properties = LayoutProperties()
        properties.stackOrientation = .horizontal
        return properties
    }

    // Controls and one-point dividers alternate.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let controlCount = (subviews.count + 1) / 2
        let idealWidth = subviews.indices
            .filter { $0.isMultiple(of: 2) }
            .map { subviews[$0].sizeThatFits(.unspecified).width }
            .max() ?? 0
        let minimumWidth = CGFloat(controlCount) * idealWidth + CGFloat(controlCount - 1)
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: max(proposal.width ?? minimumWidth, minimumWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let controlCount = (subviews.count + 1) / 2
        let controlWidth = (bounds.width - CGFloat(controlCount - 1)) / CGFloat(controlCount)
        var x = bounds.minX
        for index in subviews.indices {
            let width = index.isMultiple(of: 2) ? controlWidth : 1
            subviews[index].place(at: CGPoint(x: x + width / 2, y: bounds.midY),
                                  anchor: .center, proposal: ProposedViewSize(width: width, height: nil))
            x += width
        }
    }
}

private struct DetailCategoryAccessoryLabel: View {
    let categories: [Category]
    let isFiltered: Bool
    let title: String
    private let iconWidth: CGFloat = 20
    private let dotSize: CGFloat = 8
    private let spacing: CGFloat = 4
    @ScaledMetric(relativeTo: .footnote) private var overflowLineHeight: CGFloat = 18

    private var filterIcon: some View {
        Image(systemName: isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            .font(.system(size: iconWidth, weight: .medium))
            .frame(width: iconWidth)
    }

    var body: some View {
        GeometryReader { proxy in
            let capacity = Int(max(0, proxy.size.width - iconWidth) / (dotSize + spacing))
            let maximumDots = min(capacity, categories.count)
            ViewThatFits(in: .horizontal) {
                if categories.isEmpty {
                    HStack(spacing: spacing) {
                        filterIcon
                        Text(title)
                    }
                    .fixedSize()
                }

                ForEach(Array((0...maximumDots).reversed()), id: \.self) { visibleCount in
                    HStack(spacing: spacing) {
                        filterIcon
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

                filterIcon
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
