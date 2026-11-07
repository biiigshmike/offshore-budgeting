import SwiftUI

/// A single-selection menu with an optional unassigned choice.
/// Mac Catalyst callers can opt into a popover that preserves row artwork.
struct EntityMenuPicker<Item: Identifiable, ItemLabel: View>: View where Item.ID == UUID {
    let title: LocalizedStringKey
    let items: [Item]
    @Binding var selection: UUID?
    private let showsTitle: Bool
    private let allowsEmptySelection: Bool
    private let showsArtworkOnMac: Bool
    private let itemLabel: (Item?) -> ItemLabel

    #if targetEnvironment(macCatalyst)
    @State private var isShowingChoices = false
    #endif

    init(
        title: LocalizedStringKey,
        items: [Item],
        selection: Binding<UUID?>,
        allowsEmptySelection: Bool = true,
        showsTitle: Bool = true,
        showsArtworkOnMac: Bool = false,
        @ViewBuilder label: @escaping (Item?) -> ItemLabel
    ) {
        self.title = title
        self.showsTitle = showsTitle
        self.showsArtworkOnMac = showsArtworkOnMac
        self.items = items
        _selection = selection
        self.allowsEmptySelection = allowsEmptySelection
        itemLabel = label
    }

    private var selectedItem: Item? {
        items.first { $0.id == selection }
    }

    var body: some View {
        #if targetEnvironment(macCatalyst)
        if showsArtworkOnMac {
            artworkPicker
        } else {
            nativeMenu
        }
        #else
        nativeMenu
        #endif
    }

    private var nativeMenu: some View {
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
            pickerLabel
        }
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
    }

    #if targetEnvironment(macCatalyst)
    private var artworkPicker: some View {
        Button {
            isShowingChoices = true
        } label: {
            pickerLabel
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $isShowingChoices, arrowEdge: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    if allowsEmptySelection {
                        artworkChoice(nil)
                    }
                    ForEach(items) { item in
                        artworkChoice(item)
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(
                width: 280,
                height: min(CGFloat(items.count + (allowsEmptySelection ? 1 : 0)) * 44, 320)
            )
        }
    }

    private func artworkChoice(_ item: Item?) -> some View {
        let isSelected = selection == item?.id
        return Button {
            selection = item?.id
            isShowingChoices = false
        } label: {
            HStack(spacing: 12) {
                itemLabel(item)
                    .labelStyle(.titleAndIcon)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    #endif

    private var pickerLabel: some View {
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
