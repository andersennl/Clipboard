import Carbon
import Foundation
import XCTest
@testable import Clipboard

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testRecordingAssignsValidShortcutAndNotifiesOnce() {
        let viewModel = SettingsViewModel(shortcut: .default)
        var recordedShortcuts: [HotkeyShortcut] = []
        viewModel.onShortcutChanged = { recordedShortcuts.append($0) }

        viewModel.beginRecording()
        let didConsume = viewModel.handleRecordingEvent(
            keyCode: UInt32(kVK_ANSI_K),
            carbonModifiers: UInt32(cmdKey | optionKey)
        )

        XCTAssertTrue(didConsume)
        XCTAssertFalse(viewModel.isRecording)
        XCTAssertNil(viewModel.validationMessage)
        XCTAssertEqual(viewModel.shortcut.keyCode, UInt32(kVK_ANSI_K))
        XCTAssertEqual(recordedShortcuts.count, 1)
        XCTAssertEqual(recordedShortcuts.first?.carbonModifiers, UInt32(cmdKey | optionKey))
    }

    func testRecordingKeepsListeningForShortcutWithoutPrimaryModifier() {
        let viewModel = SettingsViewModel(shortcut: .default)
        var recordedShortcuts: [HotkeyShortcut] = []
        viewModel.onShortcutChanged = { recordedShortcuts.append($0) }

        viewModel.beginRecording()
        let didConsume = viewModel.handleRecordingEvent(
            keyCode: UInt32(kVK_ANSI_K),
            carbonModifiers: UInt32(shiftKey)
        )

        XCTAssertTrue(didConsume)
        XCTAssertTrue(viewModel.isRecording)
        XCTAssertNotNil(viewModel.validationMessage)
        XCTAssertEqual(viewModel.shortcut, .default)
        XCTAssertTrue(recordedShortcuts.isEmpty)
    }

    func testEscapeCancelsRecordingWithoutChangingShortcut() {
        let viewModel = SettingsViewModel(shortcut: .default)
        var recordedShortcuts: [HotkeyShortcut] = []
        viewModel.onShortcutChanged = { recordedShortcuts.append($0) }

        viewModel.beginRecording()
        let didConsume = viewModel.handleRecordingEvent(keyCode: UInt32(kVK_Escape), carbonModifiers: 0)

        XCTAssertTrue(didConsume)
        XCTAssertFalse(viewModel.isRecording)
        XCTAssertNil(viewModel.validationMessage)
        XCTAssertEqual(viewModel.shortcut, .default)
        XCTAssertTrue(recordedShortcuts.isEmpty)
    }

    func testEventsAreIgnoredWhileNotRecording() {
        let viewModel = SettingsViewModel(shortcut: .default)
        var recordedShortcuts: [HotkeyShortcut] = []
        viewModel.onShortcutChanged = { recordedShortcuts.append($0) }

        let didConsume = viewModel.handleRecordingEvent(
            keyCode: UInt32(kVK_ANSI_K),
            carbonModifiers: UInt32(cmdKey)
        )

        XCTAssertFalse(didConsume)
        XCTAssertEqual(viewModel.shortcut, .default)
        XCTAssertTrue(recordedShortcuts.isEmpty)
    }

    func testLaunchAtLoginIsOffUntilTheUserTurnsItOn() {
        let viewModel = SettingsViewModel(shortcut: .default)
        var requestedValues: [Bool] = []
        viewModel.onLaunchAtLoginChanged = { requestedValues.append($0) }

        XCTAssertFalse(viewModel.isLaunchAtLoginEnabled)
        XCTAssertTrue(requestedValues.isEmpty)

        viewModel.setLaunchAtLogin(true)

        XCTAssertEqual(requestedValues, [true])
    }

    func testLaunchAtLoginReflectsTheStateReportedBackByTheService() {
        let viewModel = SettingsViewModel(shortcut: .default)

        viewModel.updateLaunchAtLoginState(.enabled)
        XCTAssertTrue(viewModel.isLaunchAtLoginEnabled)
        XCTAssertNil(viewModel.launchAtLoginMessage)

        viewModel.updateLaunchAtLoginState(.requiresApproval)
        XCTAssertTrue(viewModel.isLaunchAtLoginEnabled)
        XCTAssertNotNil(viewModel.launchAtLoginMessage)

        viewModel.updateLaunchAtLoginState(.notRegistered)
        XCTAssertFalse(viewModel.isLaunchAtLoginEnabled)
        XCTAssertNil(viewModel.launchAtLoginMessage)
    }

    func testResetToDefaultNotifiesAndStopsRecording() {
        let custom = HotkeyShortcut(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: UInt32(cmdKey))
        let viewModel = SettingsViewModel(shortcut: custom)
        var recordedShortcuts: [HotkeyShortcut] = []
        viewModel.onShortcutChanged = { recordedShortcuts.append($0) }

        viewModel.beginRecording()
        viewModel.resetToDefault()

        XCTAssertFalse(viewModel.isRecording)
        XCTAssertEqual(viewModel.shortcut, .default)
        XCTAssertEqual(recordedShortcuts, [.default])
    }
}
