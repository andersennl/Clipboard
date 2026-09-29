import AppKit
import Carbon
import Foundation
import XCTest
@testable import Clipboard

@MainActor
final class HotkeyShortcutTests: XCTestCase {
    func testDefaultShortcutMatchesLegacyCommandShiftV() {
        XCTAssertEqual(HotkeyShortcut.default.keyCode, UInt32(kVK_ANSI_V))
        XCTAssertEqual(HotkeyShortcut.default.carbonModifiers, UInt32(cmdKey | shiftKey))
        XCTAssertEqual(HotkeyShortcut.default.displayString, "⇧⌘V")
    }

    func testDisplayStringUsesAppleModifierOrderAndNamedKeys() {
        let shortcut = HotkeyShortcut(
            keyCode: UInt32(kVK_Space),
            carbonModifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey)
        )

        // The space bar is the one key name that gets translated, so assert the modifier order
        // and the lookup separately instead of pinning the English string.
        XCTAssertEqual(shortcut.displayString, "⌃⌥⇧⌘" + HotkeyShortcut.keyName(for: UInt32(kVK_Space)))
        XCTAssertNotEqual(HotkeyShortcut.keyName(for: UInt32(kVK_Space)), "Key \(UInt32(kVK_Space))")
    }

    func testShortcutRequiresCommandControlOrOption() {
        let shiftOnly = HotkeyShortcut(keyCode: UInt32(kVK_ANSI_V), carbonModifiers: UInt32(shiftKey))
        let noModifier = HotkeyShortcut(keyCode: UInt32(kVK_ANSI_V), carbonModifiers: 0)
        let optionOnly = HotkeyShortcut(keyCode: UInt32(kVK_ANSI_V), carbonModifiers: UInt32(optionKey))

        XCTAssertFalse(shiftOnly.isValid)
        XCTAssertFalse(noModifier.isValid)
        XCTAssertTrue(optionOnly.isValid)
    }

    func testCarbonModifiersIgnoreNonRelevantEventFlags() {
        let carbonModifiers = HotkeyShortcut.carbonModifiers(
            from: [.command, .shift, .capsLock, .function, .numericPad]
        )

        XCTAssertEqual(carbonModifiers, UInt32(cmdKey | shiftKey))
    }

    func testPreferenceStoreRoundTripsShortcut() throws {
        let userDefaults = try makeIsolatedDefaults()
        let store = HotkeyPreferenceStore(userDefaults: userDefaults)
        let shortcut = HotkeyShortcut(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: UInt32(cmdKey | optionKey))

        store.setShortcut(shortcut)

        XCTAssertEqual(store.shortcut, shortcut)
        XCTAssertEqual(HotkeyPreferenceStore(userDefaults: userDefaults).shortcut, shortcut)
    }

    func testPreferenceStoreFallsBackToDefaultForStoredInvalidShortcut() throws {
        let userDefaults = try makeIsolatedDefaults()
        let invalidShortcut = HotkeyShortcut(keyCode: UInt32(kVK_ANSI_V), carbonModifiers: UInt32(shiftKey))
        let data = try JSONEncoder().encode(invalidShortcut)
        userDefaults.set(data, forKey: AppConstants.hotkeyShortcutDefaultsKey)

        XCTAssertEqual(HotkeyPreferenceStore(userDefaults: userDefaults).shortcut, .default)
    }

    private func makeIsolatedDefaults() throws -> UserDefaults {
        let suiteName = "clipboard.tests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        return userDefaults
    }
}
