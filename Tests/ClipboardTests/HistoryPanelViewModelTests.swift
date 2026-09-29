import XCTest
@testable import Clipboard

@MainActor
final class HistoryPanelViewModelTests: XCTestCase {
    func testPresentationSelectsFirstCanonicalItemByDefault() {
        let older = ClipboardItem(text: "Older", createdAt: .distantPast, sourceAppName: "Notes", sourceBundleID: "notes")
        let newer = ClipboardItem(text: "Newer", createdAt: .now, sourceAppName: "Notes", sourceBundleID: "notes")
        let viewModel = HistoryPanelViewModel()

        viewModel.present(items: [older, newer], isAccessibilityTrusted: true)

        XCTAssertEqual(viewModel.selectedItem?.text, "Older")
    }

    func testArrowNavigationMovesSelection() {
        let first = ClipboardItem(text: "First", createdAt: .now, sourceAppName: "Notes", sourceBundleID: "notes")
        let second = ClipboardItem(text: "Second", createdAt: .distantPast, sourceAppName: "Notes", sourceBundleID: "notes")
        let viewModel = HistoryPanelViewModel()

        viewModel.present(items: [first, second], isAccessibilityTrusted: true)
        viewModel.moveSelection(offset: 1)

        XCTAssertEqual(viewModel.selectedItem?.text, "Second")
    }

    func testSearchFiltersAndResetsSelection() {
        let first = ClipboardItem(text: "deploy pipeline", sourceAppName: "Terminal", sourceBundleID: "terminal")
        let second = ClipboardItem(text: "team standup notes", sourceAppName: "Notes", sourceBundleID: "notes")
        let viewModel = HistoryPanelViewModel()

        viewModel.present(items: [first, second], isAccessibilityTrusted: true)
        viewModel.query = "stand"

        XCTAssertEqual(viewModel.filteredItems.map(\.text), ["team standup notes"])
        XCTAssertEqual(viewModel.selectedItem?.text, "team standup notes")
    }

    func testPresentationAndUpdateSetAccessibilityTrust() {
        let item = ClipboardItem(text: "Permission", sourceAppName: "Tests", sourceBundleID: "tests")
        let viewModel = HistoryPanelViewModel()

        viewModel.present(items: [item], isAccessibilityTrusted: false)
        XCTAssertFalse(viewModel.isAccessibilityTrusted)

        viewModel.updateItems([item], isAccessibilityTrusted: true)
        XCTAssertTrue(viewModel.isAccessibilityTrusted)
    }

    func testRequestAccessibilityAccessInvokesCallbackOnce() {
        let viewModel = HistoryPanelViewModel()
        var requestCount = 0
        viewModel.onGrantAccessRequested = {
            requestCount += 1
        }

        viewModel.requestAccessibilityAccess()

        XCTAssertEqual(requestCount, 1)
    }

    func testConfirmSelectionDoesNothingWhenEmpty() {
        let viewModel = HistoryPanelViewModel()
        var pasteCount = 0
        viewModel.onPasteRequested = { _ in
            pasteCount += 1
        }

        viewModel.present(items: [], isAccessibilityTrusted: true)
        viewModel.confirmSelection()

        XCTAssertEqual(pasteCount, 0)
    }

    func testUpdateItemsPreservesSelectionWhenItemStillExists() {
        let first = ClipboardItem(text: "First", createdAt: .now, sourceAppName: "Tests", sourceBundleID: "tests")
        let second = ClipboardItem(text: "Second", createdAt: .distantPast, sourceAppName: "Tests", sourceBundleID: "tests")
        let viewModel = HistoryPanelViewModel()

        viewModel.present(items: [first, second], isAccessibilityTrusted: true)
        viewModel.select(second)
        viewModel.updateItems([first, second], isAccessibilityTrusted: true)

        XCTAssertEqual(viewModel.selectedItem?.id, second.id)
    }

    func testUpdateItemsFallsBackWhenSelectionDisappears() {
        let first = ClipboardItem(text: "First", createdAt: .now, sourceAppName: "Tests", sourceBundleID: "tests")
        let second = ClipboardItem(text: "Second", createdAt: .distantPast, sourceAppName: "Tests", sourceBundleID: "tests")
        let viewModel = HistoryPanelViewModel()

        viewModel.present(items: [first, second], isAccessibilityTrusted: true)
        viewModel.select(second)
        viewModel.updateItems([first], isAccessibilityTrusted: true)

        XCTAssertEqual(viewModel.selectedItem?.id, first.id)
    }
}
