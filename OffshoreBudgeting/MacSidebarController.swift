#if targetEnvironment(macCatalyst)
import UIKit

/// A native sidebar for the owned Catalyst split view. UIKit supplies the
/// sidebar appearance and selection treatment at the column boundary.
@MainActor
final class MacSidebarController: UICollectionViewController {
    private var onSelectSection: (AppSection) -> Void = { _ in }
    private var onAddExpense: () -> Void = {}
    private var onAddIncome: () -> Void = {}

    private var selectedSection: AppSection = .home
    private let sections = AppSection.allCases
    private lazy var cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, IndexPath> { [weak self] cell, _, indexPath in
        guard let self else { return }
        var content = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            let section = self.sections[indexPath.item]
            content.text = section.title
            content.image = UIImage(systemName: section.systemImage)
        } else {
            switch indexPath.item {
            case 0:
                content.text = String(
                    localized: "app.quickLinks.section.title",
                    defaultValue: "Quick Links",
                    comment: "Sidebar section title for quick add actions."
                )
            case 1:
                content.text = String(
                    localized: "app.quickLinks.addExpense",
                    defaultValue: "Add Expense",
                    comment: "Sidebar quick link for adding an expense."
                )
                content.image = UIImage(systemName: "plus")
            default:
                content.text = String(
                    localized: "app.quickLinks.addIncome",
                    defaultValue: "Add Income",
                    comment: "Sidebar quick link for adding income."
                )
                content.image = UIImage(systemName: "plus")
            }
        }
        cell.contentConfiguration = content
    }

    init() {
        let layout = UICollectionViewCompositionalLayout { section, environment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .sidebar)
            configuration.headerMode = section == 1 ? .firstItemInSection : .none
            return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
        }
        super.init(collectionViewLayout: layout)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Create the registration before UIKit requests its first cell.
        _ = cellRegistration
        collectionView.tintColor = UIColor(named: "AccentColor")
        restoreSelection()
    }

    func update(
        selectedSection: AppSection,
        onSelectSection: @escaping (AppSection) -> Void,
        onAddExpense: @escaping () -> Void,
        onAddIncome: @escaping () -> Void
    ) {
        self.selectedSection = selectedSection
        self.onSelectSection = onSelectSection
        self.onAddExpense = onAddExpense
        self.onAddIncome = onAddIncome
        if isViewLoaded { restoreSelection() }
    }

    override func numberOfSections(in collectionView: UICollectionView) -> Int { 2 }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        section == 0 ? sections.count : 3
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: indexPath)
    }

    override func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        indexPath.section == 0 || indexPath.item != 0
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if indexPath.section == 0 {
            selectedSection = sections[indexPath.item]
            onSelectSection(selectedSection)
        } else {
            collectionView.deselectItem(at: indexPath, animated: false)
            restoreSelection()
            if indexPath.item == 1 {
                onAddExpense()
            } else {
                onAddIncome()
            }
        }
    }

    private func restoreSelection() {
        guard let item = sections.firstIndex(of: selectedSection) else { return }
        collectionView.selectItem(at: IndexPath(item: item, section: 0), animated: false, scrollPosition: [])
    }
}
#endif
