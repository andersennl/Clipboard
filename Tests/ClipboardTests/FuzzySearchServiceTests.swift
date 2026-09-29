import XCTest
@testable import Clipboard

final class FuzzySearchServiceTests: XCTestCase {
    private let searchService = FuzzySearchService()

    func testEmptyQueryReturnsItemsInInputOrder() {
        let older = ClipboardItem(text: "old", createdAt: .distantPast, sourceAppName: "Notes", sourceBundleID: "notes")
        let newer = ClipboardItem(text: "new", createdAt: .now, sourceAppName: "Notes", sourceBundleID: "notes")

        let results = searchService.search(query: "", items: [older, newer])

        XCTAssertEqual(results.map(\.text), ["old", "new"])
    }

    func testPrefixRankBeatsContainsMatch() {
        let prefix = ClipboardItem(text: "deploy pipeline", sourceAppName: "Terminal", sourceBundleID: "terminal")
        let contains = ClipboardItem(text: "how to deploy pipeline safely", sourceAppName: "Notes", sourceBundleID: "notes")

        let results = searchService.search(query: "deploy", items: [contains, prefix])

        XCTAssertEqual(results.first?.id, prefix.id)
    }

    func testSubsequenceMatchingStillFindsResult() {
        let item = ClipboardItem(text: "clipboard manager", sourceAppName: "Notes", sourceBundleID: "notes")

        let results = searchService.search(query: "cbm", items: [item])

        XCTAssertEqual(results.first?.id, item.id)
    }

    func testSearchIsCaseAndDiacriticInsensitive() {
        let item = ClipboardItem(text: "Résumé Review", sourceAppName: "Notes", sourceBundleID: "notes")

        let results = searchService.search(query: "resume", items: [item])

        XCTAssertEqual(results.first?.id, item.id)
    }

    func testNonMatchingQueryReturnsEmptyResults() {
        let item = ClipboardItem(text: "clipboard manager", sourceAppName: "Notes", sourceBundleID: "notes")

        let results = searchService.search(query: "database", items: [item])

        XCTAssertTrue(results.isEmpty)
    }

    func testEqualScoresSortByNewestFirst() {
        let older = ClipboardItem(
            text: "same phrase",
            createdAt: Date(timeIntervalSince1970: 1),
            sourceAppName: "Notes",
            sourceBundleID: "notes"
        )
        let newer = ClipboardItem(
            text: "same phrase",
            createdAt: Date(timeIntervalSince1970: 2),
            sourceAppName: "Notes",
            sourceBundleID: "notes"
        )

        let results = searchService.search(query: "same", items: [older, newer])

        XCTAssertEqual(results.map(\.id), [newer.id, older.id])
    }
}
