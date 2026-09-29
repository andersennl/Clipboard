import Foundation
import Observation

@MainActor
@Observable
final class HistoryPanelViewModel {
    private let fuzzySearchService: FuzzySearchService
    private(set) var allItems: [ClipboardItem] = []
    private(set) var filteredItems: [ClipboardItem] = []
    var query = "" {
        didSet {
            applySearch(resetSelection: true)
        }
    }
    var selectedItemID: ClipboardItem.ID?
    var presentationToken = UUID()
    var isAccessibilityTrusted = false

    @ObservationIgnored
    var onPasteRequested: ((ClipboardItem) -> Void)?

    @ObservationIgnored
    var onDismissRequested: (() -> Void)?

    @ObservationIgnored
    var onGrantAccessRequested: (() -> Void)?

    init(fuzzySearchService: FuzzySearchService = FuzzySearchService()) {
        self.fuzzySearchService = fuzzySearchService
    }

    var selectedItem: ClipboardItem? {
        guard let selectedItemID else { return filteredItems.first }
        return filteredItems.first(where: { $0.id == selectedItemID }) ?? filteredItems.first
    }

    func present(items: [ClipboardItem], isAccessibilityTrusted: Bool) {
        allItems = items
        self.isAccessibilityTrusted = isAccessibilityTrusted
        query = ""
        presentationToken = UUID()
        applySearch(resetSelection: true)
    }

    func updateItems(_ items: [ClipboardItem], isAccessibilityTrusted: Bool) {
        allItems = items
        self.isAccessibilityTrusted = isAccessibilityTrusted
        applySearch(resetSelection: false)
    }

    func moveSelection(offset: Int) {
        guard !filteredItems.isEmpty else { return }

        let currentIndex = filteredItems.firstIndex(where: { $0.id == selectedItem?.id }) ?? 0
        let newIndex = min(max(currentIndex + offset, 0), filteredItems.count - 1)
        selectedItemID = filteredItems[newIndex].id
    }

    func select(_ item: ClipboardItem) {
        selectedItemID = item.id
    }

    func confirmSelection() {
        guard let selectedItem else { return }
        onPasteRequested?(selectedItem)
    }

    func dismiss() {
        onDismissRequested?()
    }

    func requestAccessibilityAccess() {
        onGrantAccessRequested?()
    }

    private func applySearch(resetSelection: Bool) {
        let currentSelection = selectedItemID
        filteredItems = fuzzySearchService.search(query: query, items: allItems)

        if filteredItems.isEmpty {
            selectedItemID = nil
            return
        }

        if !resetSelection, let currentSelection, filteredItems.contains(where: { $0.id == currentSelection }) {
            selectedItemID = currentSelection
            return
        }

        selectedItemID = filteredItems[0].id
    }
}
