import Foundation
import XCTest
@testable import Clipboard

@MainActor
final class ClipboardStoreTests: XCTestCase {
    func testStorePrunesToRetentionLimit() throws {
        let store = ClipboardStore(baseDirectory: try makeTemporaryDirectory())

        for index in 0..<(AppConstants.retentionLimit + 5) {
            let item = ClipboardItem(
                text: "Item \(index)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                sourceAppName: "Tests",
                sourceBundleID: "tests"
            )
            _ = store.append(item)
        }

        XCTAssertEqual(store.items.count, AppConstants.retentionLimit)
        XCTAssertEqual(store.items.first?.text, "Item \(AppConstants.retentionLimit + 4)")
    }

    func testStoreReplacesDirectDuplicateWithFreshItem() throws {
        let store = ClipboardStore(baseDirectory: try makeTemporaryDirectory())
        let originalItem = ClipboardItem(
            id: UUID(),
            text: "Same",
            createdAt: Date(timeIntervalSince1970: 1),
            sourceAppName: "Original",
            sourceBundleID: "original"
        )
        let copiedAgainItem = ClipboardItem(
            id: UUID(),
            text: "Same",
            createdAt: Date(timeIntervalSince1970: 2),
            sourceAppName: "Copied Again",
            sourceBundleID: "copied-again"
        )

        XCTAssertTrue(store.append(originalItem))
        XCTAssertTrue(store.append(copiedAgainItem))

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first, copiedAgainItem)
    }

    func testStoreReplacesOlderDuplicateAndMovesItToFront() throws {
        let store = ClipboardStore(baseDirectory: try makeTemporaryDirectory())
        let firstA = ClipboardItem(
            text: "A",
            createdAt: Date(timeIntervalSince1970: 1),
            sourceAppName: "Original",
            sourceBundleID: "original"
        )
        let itemB = ClipboardItem(
            text: "B",
            createdAt: Date(timeIntervalSince1970: 2),
            sourceAppName: "Middle",
            sourceBundleID: "middle"
        )
        let secondA = ClipboardItem(
            text: "A",
            createdAt: Date(timeIntervalSince1970: 3),
            sourceAppName: "Copied Again",
            sourceBundleID: "copied-again"
        )

        XCTAssertTrue(store.append(firstA))
        XCTAssertTrue(store.append(itemB))
        XCTAssertTrue(store.append(secondA))

        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items, [secondA, itemB])
    }

    func testMoveToFrontMovesExistingItemByIDAndPreservesMetadata() throws {
        let store = ClipboardStore(baseDirectory: try makeTemporaryDirectory())
        let first = ClipboardItem(
            id: UUID(),
            text: "First",
            createdAt: Date(timeIntervalSince1970: 1),
            sourceAppName: "Original First",
            sourceBundleID: "original.first"
        )
        let second = ClipboardItem(
            id: UUID(),
            text: "Second",
            createdAt: Date(timeIntervalSince1970: 2),
            sourceAppName: "Original Second",
            sourceBundleID: "original.second"
        )
        let third = ClipboardItem(
            id: UUID(),
            text: "Third",
            createdAt: Date(timeIntervalSince1970: 3),
            sourceAppName: "Original Third",
            sourceBundleID: "original.third"
        )
        XCTAssertTrue(store.append(first))
        XCTAssertTrue(store.append(second))
        XCTAssertTrue(store.append(third))

        XCTAssertTrue(store.moveToFront(id: first.id))

        XCTAssertEqual(store.items, [first, third, second])
    }

    func testMoveToFrontPersistsMovedOrder() throws {
        let directory = try makeTemporaryDirectory()
        let firstStore = ClipboardStore(baseDirectory: directory)
        let first = ClipboardItem(text: "First", createdAt: Date(timeIntervalSince1970: 1), sourceAppName: "Tests", sourceBundleID: "tests")
        let second = ClipboardItem(text: "Second", createdAt: Date(timeIntervalSince1970: 2), sourceAppName: "Tests", sourceBundleID: "tests")
        XCTAssertTrue(firstStore.append(first))
        XCTAssertTrue(firstStore.append(second))

        XCTAssertTrue(firstStore.moveToFront(id: first.id))

        let secondStore = ClipboardStore(baseDirectory: directory)
        XCTAssertEqual(secondStore.items.map(\.id), [first.id, second.id])
    }

    func testMoveToFrontReturnsFalseForMissingIDAndLeavesHistoryUnchanged() throws {
        let store = ClipboardStore(baseDirectory: try makeTemporaryDirectory())
        let item = ClipboardItem(text: "Only", sourceAppName: "Tests", sourceBundleID: "tests")
        XCTAssertTrue(store.append(item))

        XCTAssertFalse(store.moveToFront(id: UUID()))

        XCTAssertEqual(store.items, [item])
    }

    func testMoveToFrontReturnsTrueForAlreadyFrontItemWithoutChangingHistory() throws {
        let store = ClipboardStore(baseDirectory: try makeTemporaryDirectory())
        let first = ClipboardItem(text: "First", createdAt: Date(timeIntervalSince1970: 1), sourceAppName: "Tests", sourceBundleID: "tests")
        let second = ClipboardItem(text: "Second", createdAt: Date(timeIntervalSince1970: 2), sourceAppName: "Tests", sourceBundleID: "tests")
        XCTAssertTrue(store.append(first))
        XCTAssertTrue(store.append(second))

        XCTAssertTrue(store.moveToFront(id: second.id))

        XCTAssertEqual(store.items, [second, first])
    }

    func testStorePersistsAndLoadsHistory() throws {
        let directory = try makeTemporaryDirectory()
        let firstStore = ClipboardStore(baseDirectory: directory)
        let item = ClipboardItem(text: "Persist me", sourceAppName: "Tests", sourceBundleID: "tests")

        _ = firstStore.append(item)

        let secondStore = ClipboardStore(baseDirectory: directory)
        XCTAssertEqual(secondStore.items.first?.text, "Persist me")
    }

    func testStoreIgnoresWhitespaceOnlyItems() throws {
        let store = ClipboardStore(baseDirectory: try makeTemporaryDirectory())

        let didAppend = store.append(ClipboardItem(text: "  \n\t  ", sourceAppName: "Tests", sourceBundleID: "tests"))

        XCTAssertFalse(didAppend)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testStorePreservesAppendedItemTextOver100Words() throws {
        let store = ClipboardStore(baseDirectory: try makeTemporaryDirectory())
        let longText = makeLongText(wordCount: 125)

        let didAppend = store.append(ClipboardItem(text: longText, sourceAppName: "Tests", sourceBundleID: "tests"))

        XCTAssertTrue(didAppend)
        XCTAssertEqual(store.items.first?.text, longText)
    }

    func testStorePersistsAndLoadsItemTextOver100Words() throws {
        let directory = try makeTemporaryDirectory()
        let firstStore = ClipboardStore(baseDirectory: directory)
        let longText = makeLongText(wordCount: 140)

        XCTAssertTrue(firstStore.append(ClipboardItem(text: longText, sourceAppName: "Tests", sourceBundleID: "tests")))

        let secondStore = ClipboardStore(baseDirectory: directory)
        XCTAssertEqual(secondStore.items.first?.text, longText)
    }

    func testStoreKeepsLongItemsWithSharedPrefixAndDifferentSuffixesSeparate() throws {
        let store = ClipboardStore(baseDirectory: try makeTemporaryDirectory())
        let sharedPrefix = makeLongText(wordCount: 120)
        let firstLongText = "\(sharedPrefix) first suffix"
        let secondLongText = "\(sharedPrefix) second suffix"

        XCTAssertTrue(store.append(ClipboardItem(text: firstLongText, sourceAppName: "Tests", sourceBundleID: "tests")))
        XCTAssertTrue(store.append(ClipboardItem(text: secondLongText, sourceAppName: "Tests", sourceBundleID: "tests")))

        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items.map(\.text), [secondLongText, firstLongText])
    }

    func testStoreReplacesExactDirectDuplicatesOver100Words() throws {
        let store = ClipboardStore(baseDirectory: try makeTemporaryDirectory())
        let longText = makeLongText(wordCount: 130)
        let originalItem = ClipboardItem(
            text: longText,
            createdAt: Date(timeIntervalSince1970: 1),
            sourceAppName: "Original",
            sourceBundleID: "original"
        )
        let copiedAgainItem = ClipboardItem(
            text: longText,
            createdAt: Date(timeIntervalSince1970: 2),
            sourceAppName: "Copied Again",
            sourceBundleID: "copied-again"
        )

        XCTAssertTrue(store.append(originalItem))
        XCTAssertTrue(store.append(copiedAgainItem))

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first, copiedAgainItem)
    }

    func testStorePersistsReplacedDuplicateOrderAndUniqueness() throws {
        let directory = try makeTemporaryDirectory()
        let firstStore = ClipboardStore(baseDirectory: directory)
        let firstA = ClipboardItem(
            text: "A",
            createdAt: Date(timeIntervalSince1970: 1),
            sourceAppName: "Original",
            sourceBundleID: "original"
        )
        let itemB = ClipboardItem(
            text: "B",
            createdAt: Date(timeIntervalSince1970: 2),
            sourceAppName: "Middle",
            sourceBundleID: "middle"
        )
        let secondA = ClipboardItem(
            text: "A",
            createdAt: Date(timeIntervalSince1970: 3),
            sourceAppName: "Copied Again",
            sourceBundleID: "copied-again"
        )

        XCTAssertTrue(firstStore.append(firstA))
        XCTAssertTrue(firstStore.append(itemB))
        XCTAssertTrue(firstStore.append(secondA))

        let secondStore = ClipboardStore(baseDirectory: directory)
        XCTAssertEqual(secondStore.items, [secondA, itemB])
    }

    func testStoreReplacingDuplicateAtRetentionLimitDoesNotDropAnotherItem() throws {
        let store = ClipboardStore(baseDirectory: try makeTemporaryDirectory())

        for index in 0..<AppConstants.retentionLimit {
            let item = ClipboardItem(
                text: "Item \(index)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                sourceAppName: "Tests",
                sourceBundleID: "tests"
            )
            XCTAssertTrue(store.append(item))
        }

        let copiedAgainItem = ClipboardItem(
            text: "Item 500",
            createdAt: Date(timeIntervalSince1970: TimeInterval(AppConstants.retentionLimit + 1)),
            sourceAppName: "Copied Again",
            sourceBundleID: "copied-again"
        )

        XCTAssertTrue(store.append(copiedAgainItem))

        XCTAssertEqual(store.items.count, AppConstants.retentionLimit)
        XCTAssertEqual(store.items.first, copiedAgainItem)
        XCTAssertEqual(Set(store.items.map(\.text)).count, AppConstants.retentionLimit)
        XCTAssertEqual(Set(store.items.map(\.text)), Set((0..<AppConstants.retentionLimit).map { "Item \($0)" }))
    }

    func testStoreLoadsExistingItemTextOver100WordsWithoutTruncating() throws {
        let directory = try makeTemporaryDirectory()
        let historyURL = directory.appendingPathComponent(AppConstants.historyFileName)
        let longText = makeLongText(wordCount: 150)
        let items = [
            ClipboardItem(text: longText, sourceAppName: "Tests", sourceBundleID: "tests")
        ]
        try JSONEncoder().encode(items).write(to: historyURL)

        let store = ClipboardStore(baseDirectory: directory)
        let persistedItems = try JSONDecoder().decode([ClipboardItem].self, from: Data(contentsOf: historyURL))

        XCTAssertEqual(store.items.first?.text, longText)
        XCTAssertEqual(persistedItems.first?.text, longText)
    }

    func testStoreLoadsEmptyHistoryWhenFileIsCorrupt() throws {
        let directory = try makeTemporaryDirectory()
        let historyURL = directory.appendingPathComponent(AppConstants.historyFileName)
        try Data("not json".utf8).write(to: historyURL)

        let store = ClipboardStore(baseDirectory: directory)

        XCTAssertTrue(store.items.isEmpty)
    }

    func testStorePrunesLoadedHistoryToRetentionLimit() throws {
        let directory = try makeTemporaryDirectory()
        let historyURL = directory.appendingPathComponent(AppConstants.historyFileName)
        let items = (0..<(AppConstants.retentionLimit + 3)).map { index in
            ClipboardItem(
                text: "Loaded \(index)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                sourceAppName: "Tests",
                sourceBundleID: "tests"
            )
        }
        try JSONEncoder().encode(items).write(to: historyURL)

        let store = ClipboardStore(baseDirectory: directory)

        XCTAssertEqual(store.items.count, AppConstants.retentionLimit)
        XCTAssertEqual(store.items.first?.text, "Loaded 0")
    }

    func testClearPersistsEmptyHistory() throws {
        let directory = try makeTemporaryDirectory()
        let firstStore = ClipboardStore(baseDirectory: directory)
        _ = firstStore.append(ClipboardItem(text: "Delete me", sourceAppName: "Tests", sourceBundleID: "tests"))

        firstStore.clear()
        let secondStore = ClipboardStore(baseDirectory: directory)

        XCTAssertTrue(secondStore.items.isEmpty)
    }

    func testMonitoringEnabledPersistsInIsolatedDefaults() throws {
        let userDefaults = try makeTemporaryUserDefaults()
        let directory = try makeTemporaryDirectory()
        let firstStore = ClipboardStore(baseDirectory: directory, userDefaults: userDefaults)

        firstStore.setMonitoringEnabled(false)
        let secondStore = ClipboardStore(baseDirectory: directory, userDefaults: userDefaults)

        XCTAssertFalse(secondStore.isMonitoringEnabled)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func makeTemporaryUserDefaults() throws -> UserDefaults {
        let suiteName = "ClipboardStoreTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        return userDefaults
    }

    private func makeLongText(wordCount: Int) -> String {
        (1...wordCount)
            .map { "word\($0)" }
            .joined(separator: " ")
    }
}
