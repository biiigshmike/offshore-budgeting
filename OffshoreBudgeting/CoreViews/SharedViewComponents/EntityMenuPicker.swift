import SwiftUI

/// A native menu with artwork and an optional unassigned selection.
struct EntityMenuPicker<Item: Identifiable, ItemLabel: View>: View where Item.ID == UUID {
    let title: LocalizedStringKey
    let items: [Item]
    @Binding var selection: UUID?
    private let showsTitle: Bool
    private let allowsEmptySelection: Bool
    private let itemLabel: (Item?) -> ItemLabel

    init(
        title: LocalizedStringKey,
        items: [Item],
        selection: Binding<UUID?>,
        allowsEmptySelection: Bool = true,
        showsTitle: Bool = true,
        @ViewBuilder label: @escaping (Item?) -> ItemLabel
    ) {
        self.title = title
        self.showsTitle = showsTitle
        self.items = items
        _selection = selection
        self.allowsEmptySelection = allowsEmptySelection
        itemLabel = label
    }

    private var selectedItem: Item? {
        items.first { $0.id == selection }
    }

    var body: some View {
        Menu {
            Picker(selection: $selection) {
                if allowsEmptySelection {
                    itemLabel(nil).tag(nil as UUID?)
                }
                ForEach(items) { item in
                    itemLabel(item).tag(Optional(item.id))
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    if showsTitle {
                        Text(title)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                    }
                    selectedLabel
                    if !showsTitle {
                        Spacer(minLength: 0)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    if showsTitle {
                        Text(title)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        selectedLabel
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
    }

    private var selectedLabel: some View {
        HStack(spacing: 8) {
            itemLabel(selectedItem)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

}
