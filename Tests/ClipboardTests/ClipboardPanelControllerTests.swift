import AppKit
import XCTest
@testable import Clipboard

@MainActor
final class ClipboardPanelControllerTests: XCTestCase {
    func testShowRefreshesPermissionFromService() {
        let permission = FakeAccessibilityPermissionProvider(isTrusted: true)
        let controller = makeController(permission: permission)

        controller.show(items: [], isAccessibilityTrusted: false)

        XCTAssertTrue(controller.isAccessibilityTrustedForTesting)
    }

    func testWindowDidBecomeKeyRefreshesPermissionFromService() {
        let permission = FakeAccessibilityPermissionProvider(isTrusted: false)
        let controller = makeController(permission: permission)

        controller.show(items: [], isAccessibilityTrusted: false)
        permission.isTrusted = true
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))

        XCTAssertTrue(controller.isAccessibilityTrustedForTesting)
    }

    func testGrantAccessStartsPollingAndUpdatesTrustWhenPermissionFlips() throws {
        let permission = FakeAccessibilityPermissionProvider(isTrusted: false)
        let scheduler = FakePermissionPollingScheduler()
        let controller = makeController(permission: permission, scheduler: scheduler)

        controller.show(items: [], isAccessibilityTrusted: false)
        controller.requestAccessibilityAccess()
        permission.isTrusted = true
        let didComplete = try XCTUnwrap(scheduler.action?())

        XCTAssertTrue(permission.didOpenSystemSettings)
        XCTAssertTrue(didComplete)
        XCTAssertTrue(controller.isAccessibilityTrustedForTesting)
    }

    func testDeniedPasteBackCopiesAndClosesWithoutPostingPaste() {
        let permission = FakeAccessibilityPermissionProvider(isTrusted: false)
        let writer = FakePasteboardWriter()
        var suppressed: [String] = []
        var didHide = false
        var didActivate = false
        var didPostShortcut = false
        let controller = makeController(
            permission: permission,
            writer: writer,
            prepareForProgrammaticPaste: { suppressed.append($0) },
            pasteShortcutPoster: { _ in
                didPostShortcut = true
                return true
            },
            pasteShortcutScheduler: { action in action() },
            hideObserver: { didHide = true }
        )
        controller.onItemPasted = { _ in
            XCTFail("Denied paste should not promote history")
        }
        controller.setPreviousApplicationForTesting(
            ClipboardTargetApplication(bundleIdentifier: "target", processIdentifier: 42, isActive: { true }) {
                didActivate = true
                return true
            }
        )

        controller.pasteSelectedItem(ClipboardItem(text: "Denied", sourceAppName: "Tests", sourceBundleID: "tests"))

        XCTAssertEqual(suppressed, ["Denied"])
        XCTAssertEqual(writer.writtenStrings, ["Denied"])
        XCTAssertEqual(permission.prompts, [true])
        XCTAssertTrue(didHide)
        XCTAssertFalse(didActivate)
        XCTAssertFalse(didPostShortcut)
        XCTAssertFalse(controller.isAccessibilityTrustedForTesting)
    }

    func testTrustedPasteBackNotifiesItemPastedAfterSuccessfulShortcutPost() {
        let permission = FakeAccessibilityPermissionProvider(isTrusted: true)
        var pastedItems: [ClipboardItem] = []
        let controller = makeController(
            permission: permission,
            pasteShortcutPoster: { _ in true },
            pasteShortcutScheduler: { action in action() }
        )
        let item = ClipboardItem(text: "Trusted", sourceAppName: "Tests", sourceBundleID: "tests")
        controller.onItemPasted = { pastedItems.append($0) }
        controller.setPreviousApplicationForTesting(
            ClipboardTargetApplication(bundleIdentifier: "target", processIdentifier: 42, isActive: { true }) {
                true
            }
        )

        controller.pasteSelectedItem(item)

        XCTAssertEqual(pastedItems, [item])
    }

    func testTrustedPasteBackDoesNotNotifyItemPastedWhenShortcutPostFails() {
        let permission = FakeAccessibilityPermissionProvider(isTrusted: true)
        var pastedItems: [ClipboardItem] = []
        let controller = makeController(
            permission: permission,
            pasteShortcutPoster: { _ in false },
            pasteShortcutScheduler: { action in action() }
        )
        let item = ClipboardItem(text: "Trusted", sourceAppName: "Tests", sourceBundleID: "tests")
        controller.onItemPasted = { pastedItems.append($0) }
        controller.setPreviousApplicationForTesting(
            ClipboardTargetApplication(bundleIdentifier: "target", processIdentifier: 42, isActive: { true }) {
                true
            }
        )

        controller.pasteSelectedItem(item)

        XCTAssertTrue(pastedItems.isEmpty)
    }

    func testTrustedPasteBackOrdersSideEffects() {
        let permission = FakeAccessibilityPermissionProvider(isTrusted: true)
        let writer = RecordingPasteboardWriter()
        let pasteActivationScheduler = FakePasteActivationScheduler()
        let targetActivationState = FakeTargetActivationState(isActive: false)
        var events: [String] = []
        let controller = makeController(
            permission: permission,
            writer: writer,
            pasteActivationScheduler: pasteActivationScheduler,
            prepareForProgrammaticPaste: { text in
                events.append("suppress:\(text)")
            },
            pasteShortcutPoster: { processIdentifier in
                events.append("shortcut:\(processIdentifier?.description ?? "global")")
                return true
            },
            pasteShortcutScheduler: { action in action() },
            hideObserver: {
                events.append("hide")
            }
        )
        writer.onWrite = { text in
            events.append("write:\(text)")
        }
        controller.setPreviousApplicationForTesting(
            ClipboardTargetApplication(
                bundleIdentifier: "target",
                processIdentifier: 42,
                isActive: { targetActivationState.isActive }
            ) {
                events.append("activate")
                targetActivationState.isActive = true
                return true
            }
        )

        controller.pasteSelectedItem(ClipboardItem(text: "Trusted", sourceAppName: "Tests", sourceBundleID: "tests"))
        _ = pasteActivationScheduler.action?()

        XCTAssertEqual(events, ["suppress:Trusted", "write:Trusted", "hide", "activate", "shortcut:42"])
    }

    func testTrustedPasteBackDoesNotActivateWhenTargetIsAlreadyActive() {
        let permission = FakeAccessibilityPermissionProvider(isTrusted: true)
        let pasteActivationScheduler = FakePasteActivationScheduler()
        var didActivate = false
        var postedProcessIdentifiers: [pid_t?] = []
        let controller = makeController(
            permission: permission,
            pasteActivationScheduler: pasteActivationScheduler,
            pasteShortcutPoster: {
                postedProcessIdentifiers.append($0)
                return true
            },
            pasteShortcutScheduler: { action in action() }
        )
        controller.setPreviousApplicationForTesting(
            ClipboardTargetApplication(bundleIdentifier: "target", processIdentifier: 42, isActive: { true }) {
                didActivate = true
                return true
            }
        )

        controller.pasteSelectedItem(ClipboardItem(text: "Trusted", sourceAppName: "Tests", sourceBundleID: "tests"))

        XCTAssertFalse(didActivate)
        XCTAssertNil(pasteActivationScheduler.action)
        XCTAssertEqual(postedProcessIdentifiers.count, 1)
        XCTAssertEqual(postedProcessIdentifiers[0], 42)
    }

    func testTrustedPasteBackDoesNotPostShortcutUntilTargetIsActive() {
        let permission = FakeAccessibilityPermissionProvider(isTrusted: true)
        let pasteActivationScheduler = FakePasteActivationScheduler()
        let targetActivationState = FakeTargetActivationState(isActive: false)
        var postCount = 0
        var pastedItems: [ClipboardItem] = []
        let controller = makeController(
            permission: permission,
            pasteActivationScheduler: pasteActivationScheduler,
            pasteShortcutPoster: { _ in
                postCount += 1
                return true
            },
            pasteShortcutScheduler: { action in action() }
        )
        controller.setPreviousApplicationForTesting(
            ClipboardTargetApplication(bundleIdentifier: "target", processIdentifier: 42, isActive: { targetActivationState.isActive }) {
                true
            }
        )
        let item = ClipboardItem(text: "Trusted", sourceAppName: "Tests", sourceBundleID: "tests")
        controller.onItemPasted = { pastedItems.append($0) }

        controller.pasteSelectedItem(item)
        let firstAttemptCompleted = pasteActivationScheduler.action?()

        XCTAssertEqual(pasteActivationScheduler.maxAttempts, 40)
        XCTAssertEqual(pasteActivationScheduler.intervalNanoseconds, 50_000_000)
        XCTAssertEqual(firstAttemptCompleted, false)
        XCTAssertEqual(postCount, 0)
        XCTAssertTrue(pastedItems.isEmpty)

        targetActivationState.isActive = true
        let secondAttemptCompleted = pasteActivationScheduler.action?()

        XCTAssertEqual(secondAttemptCompleted, true)
        XCTAssertEqual(postCount, 1)
        XCTAssertEqual(pastedItems, [item])
    }

    func testTrustedPasteBackSchedulesShortcutOnceAfterInactiveTargetBecomesActive() {
        let permission = FakeAccessibilityPermissionProvider(isTrusted: true)
        let pasteActivationScheduler = FakePasteActivationScheduler()
        let targetActivationState = FakeTargetActivationState(isActive: false)
        var postCount = 0
        let controller = makeController(
            permission: permission,
            pasteActivationScheduler: pasteActivationScheduler,
            pasteShortcutPoster: { _ in
                postCount += 1
                return true
            },
            pasteShortcutScheduler: { action in action() }
        )
        controller.setPreviousApplicationForTesting(
            ClipboardTargetApplication(
                bundleIdentifier: "target",
                processIdentifier: 42,
                isActive: { targetActivationState.isActive }
            ) {
                targetActivationState.isActive = true
                return true
            }
        )

        controller.pasteSelectedItem(ClipboardItem(text: "Trusted", sourceAppName: "Tests", sourceBundleID: "tests"))
        let didComplete = pasteActivationScheduler.action?()
        _ = pasteActivationScheduler.action?()

        XCTAssertEqual(didComplete, true)
        XCTAssertEqual(postCount, 1)
    }

    func testTrustedPasteBackDoesNotPostStaleDelayedShortcutAfterNewPasteStarts() throws {
        let permission = FakeAccessibilityPermissionProvider(isTrusted: true)
        let pasteActivationScheduler = FakePasteActivationScheduler()
        let targetActivationState = FakeTargetActivationState(isActive: false)
        var delayedShortcutActions: [@MainActor () -> Void] = []
        var postCount = 0
        var pastedTexts: [String] = []
        let controller = makeController(
            permission: permission,
            pasteActivationScheduler: pasteActivationScheduler,
            pasteShortcutPoster: { _ in
                postCount += 1
                return true
            },
            pasteShortcutScheduler: { action in delayedShortcutActions.append(action) }
        )

        controller.setPreviousApplicationForTesting(
            ClipboardTargetApplication(
                bundleIdentifier: "target",
                processIdentifier: 42,
                isActive: { targetActivationState.isActive }
            ) {
                targetActivationState.isActive = true
                return true
            }
        )
        controller.onItemPasted = { pastedTexts.append($0.text) }
        let first = ClipboardItem(text: "First", sourceAppName: "Tests", sourceBundleID: "tests")
        let second = ClipboardItem(text: "Second", sourceAppName: "Tests", sourceBundleID: "tests")
        controller.pasteSelectedItem(first)
        _ = pasteActivationScheduler.action?()
        let firstDelayedShortcut = try XCTUnwrap(delayedShortcutActions.first)

        controller.pasteSelectedItem(second)

        firstDelayedShortcut()
        XCTAssertEqual(postCount, 0)
        XCTAssertTrue(pastedTexts.isEmpty)

        try XCTUnwrap(delayedShortcutActions.last)()
        XCTAssertEqual(postCount, 1)
        XCTAssertEqual(pastedTexts, ["Second"])
    }

    func testTrustedPasteBackDoesNotPostShortcutWhenTargetActivationFails() {
        let permission = FakeAccessibilityPermissionProvider(isTrusted: true)
        let writer = FakePasteboardWriter()
        let pasteActivationScheduler = FakePasteActivationScheduler()
        var didPostShortcut = false
        var didActivate = false
        let controller = makeController(
            permission: permission,
            writer: writer,
            pasteActivationScheduler: pasteActivationScheduler,
            pasteShortcutPoster: { _ in
                didPostShortcut = true
                return true
            },
            pasteShortcutScheduler: { action in action() }
        )
        controller.setPreviousApplicationForTesting(
            ClipboardTargetApplication(bundleIdentifier: "target", processIdentifier: 42, isActive: { false }) {
                didActivate = true
                return false
            }
        )
        controller.onItemPasted = { _ in
            XCTFail("Failed target activation should not promote history")
        }

        controller.pasteSelectedItem(ClipboardItem(text: "Trusted", sourceAppName: "Tests", sourceBundleID: "tests"))

        XCTAssertEqual(writer.writtenStrings, ["Trusted"])
        XCTAssertTrue(didActivate)
        XCTAssertNil(pasteActivationScheduler.action)
        XCTAssertFalse(didPostShortcut)
    }

    func testShowClearsPreviousApplicationWhenFrontmostApplicationIsClipboard() {
        let permission = FakeAccessibilityPermissionProvider(isTrusted: true)
        let pasteActivationScheduler = FakePasteActivationScheduler()
        var didActivateOldTarget = false
        var didPostShortcut = false
        let controller = makeController(
            permission: permission,
            targetApplicationProvider: {
                ClipboardTargetApplication(bundleIdentifier: "com.tests.Clipboard", processIdentifier: 42, isActive: { true }) {
                    XCTFail("Clipboard should not be captured as a paste target")
                    return true
                }
            },
            pasteActivationScheduler: pasteActivationScheduler,
            pasteShortcutPoster: { _ in
                didPostShortcut = true
                return true
            },
            pasteShortcutScheduler: { action in action() }
        )
        controller.setPreviousApplicationForTesting(
            ClipboardTargetApplication(bundleIdentifier: "old.target", processIdentifier: 42, isActive: { true }) {
                didActivateOldTarget = true
                return true
            }
        )
        controller.onItemPasted = { _ in
            XCTFail("Missing paste target should not promote history")
        }

        controller.show(items: [], isAccessibilityTrusted: true)
        controller.pasteSelectedItem(ClipboardItem(text: "Trusted", sourceAppName: "Tests", sourceBundleID: "tests"))

        XCTAssertFalse(didActivateOldTarget)
        XCTAssertNil(pasteActivationScheduler.action)
        XCTAssertFalse(didPostShortcut)
    }

    func testShowClearsPreviousApplicationWhenNoFrontmostApplicationIsAvailable() {
        let permission = FakeAccessibilityPermissionProvider(isTrusted: true)
        let pasteActivationScheduler = FakePasteActivationScheduler()
        var didActivateOldTarget = false
        let controller = makeController(
            permission: permission,
            targetApplicationProvider: { nil },
            pasteActivationScheduler: pasteActivationScheduler,
            pasteShortcutPoster: { _ in
                XCTFail("Paste shortcut should not be posted without a target")
                return true
            },
            pasteShortcutScheduler: { action in action() }
        )
        controller.setPreviousApplicationForTesting(
            ClipboardTargetApplication(bundleIdentifier: "old.target", processIdentifier: 42, isActive: { true }) {
                didActivateOldTarget = true
                return true
            }
        )
        controller.onItemPasted = { _ in
            XCTFail("Missing paste target should not promote history")
        }

        controller.show(items: [], isAccessibilityTrusted: true)
        controller.pasteSelectedItem(ClipboardItem(text: "Trusted", sourceAppName: "Tests", sourceBundleID: "tests"))

        XCTAssertFalse(didActivateOldTarget)
        XCTAssertNil(pasteActivationScheduler.action)
    }

    func testPanelAndHostingViewForceAquaAppearance() {
        let controller = makeController()

        let panel = controller.makePanelForTesting()

        XCTAssertEqual(panel.appearance?.name, .aqua)
        XCTAssertEqual(panel.contentViewController?.view.appearance?.name, .aqua)
    }

    func testPanelAndHostingViewUseFixedHistoryPanelSizeOnCreation() {
        let controller = makeController()
        let expectedSize = NSSize(
            width: AppConstants.historyPanelWidth,
            height: AppConstants.historyPanelHeight
        )

        let panel = controller.makePanelForTesting()

        XCTAssertEqual(panel.frame.size, expectedSize)
        XCTAssertEqual(panel.minSize, expectedSize)
        XCTAssertEqual(panel.maxSize, expectedSize)
        XCTAssertEqual(panel.contentViewController?.view.frame.size, expectedSize)
        XCTAssertEqual(panel.contentView?.frame.size, expectedSize)
    }

    func testPanelIsNonActivatingAndDoesNotBecomeMain() {
        let controller = makeController()

        let panel = controller.makePanelForTesting()

        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
    }

    func testSystemPasteShortcutPosterUsesGlobalPostingWhenProcessIdentifierIsAvailable() {
        var postedTargets: [pid_t?] = []
        let poster = ClipboardPasteShortcutPoster { processIdentifier, _ in
            postedTargets.append(processIdentifier)
        }

        XCTAssertTrue(poster.postPasteShortcut(targetProcessIdentifier: 42))

        XCTAssertEqual(postedTargets.count, 2)
        XCTAssertTrue(postedTargets.allSatisfy { $0 == nil })
    }

    func testSystemPasteShortcutPosterFallsBackToGlobalPostingWithoutProcessIdentifier() {
        var postedTargets: [pid_t?] = []
        let poster = ClipboardPasteShortcutPoster { processIdentifier, _ in
            postedTargets.append(processIdentifier)
        }

        XCTAssertTrue(poster.postPasteShortcut(targetProcessIdentifier: nil))

        XCTAssertEqual(postedTargets.count, 2)
        XCTAssertTrue(postedTargets.allSatisfy { $0 == nil })
    }

    func testPrimaryPlacementScreenPrefersOriginZeroScreen() throws {
        let secondary = ClipboardPanelPlacementScreen(
            frame: NSRect(x: 1440, y: 0, width: 1280, height: 720),
            visibleFrame: NSRect(x: 1440, y: 0, width: 1280, height: 680)
        )
        let primary = ClipboardPanelPlacementScreen(
            frame: NSRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: NSRect(x: 0, y: 25, width: 1440, height: 875)
        )

        let selected = try XCTUnwrap(ClipboardPanelPlacement.primaryScreen(from: [secondary, primary]))

        XCTAssertEqual(selected, primary)
    }

    func testPrimaryPlacementScreenFallsBackToFirstScreenWhenNoOriginZeroScreenExists() throws {
        let first = ClipboardPanelPlacementScreen(
            frame: NSRect(x: -1280, y: 0, width: 1280, height: 720),
            visibleFrame: NSRect(x: -1280, y: 0, width: 1280, height: 680)
        )
        let second = ClipboardPanelPlacementScreen(
            frame: NSRect(x: 1440, y: 0, width: 1280, height: 720),
            visibleFrame: NSRect(x: 1440, y: 0, width: 1280, height: 680)
        )

        let selected = try XCTUnwrap(ClipboardPanelPlacement.primaryScreen(from: [first, second]))

        XCTAssertEqual(selected, first)
    }

    func testCenteredPanelFrameIsDeterministicForSameScreenAndSize() {
        let visibleFrame = NSRect(x: 0, y: 25, width: 1440, height: 875)
        let panelSize = NSSize(width: 940, height: 560)

        let firstOpenFrame = ClipboardPanelPlacement.centeredFrame(panelSize: panelSize, in: visibleFrame)
        let secondOpenFrame = ClipboardPanelPlacement.centeredFrame(panelSize: panelSize, in: visibleFrame)

        XCTAssertEqual(firstOpenFrame, NSRect(x: 250, y: 182.5, width: 940, height: 560))
        XCTAssertEqual(firstOpenFrame, secondOpenFrame)
    }

    func testPanelPositioningIgnoresCurrentWindowSizeAndUsesFixedHistoryPanelSize() {
        let controller = makeController()
        let screen = ClipboardPanelPlacementScreen(
            frame: NSRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: NSRect(x: 0, y: 25, width: 1440, height: 875)
        )
        let panel = ClipboardPanelWindow(
            contentRect: NSRect(x: 40, y: 40, width: 200, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        controller.positionPanelForTesting(panel, on: screen)

        XCTAssertEqual(panel.frame, NSRect(x: 250, y: 182, width: 940, height: 560))
    }

    func testEscapeKeyEventInvokesCloseHandler() throws {
        let panel = ClipboardPanelWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        var escapeCount = 0
        panel.onKeyDown = { event in
            guard event.keyCode == 53 else { return false }
            escapeCount += 1
            return true
        }
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false,
                keyCode: 53
            )
        )

        panel.sendEvent(event)

        XCTAssertEqual(escapeCount, 1)
    }

    func testEscapeKeyEquivalentIsHandledByPanel() throws {
        let panel = ClipboardPanelWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        var escapeCount = 0
        panel.onKeyDown = { event in
            guard event.keyCode == 53 else { return false }
            escapeCount += 1
            return true
        }
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false,
                keyCode: 53
            )
        )

        XCTAssertTrue(panel.performKeyEquivalent(with: event))
        XCTAssertEqual(escapeCount, 1)
    }

    func testCancelOperationInvokesEscapeHandler() {
        let panel = ClipboardPanelWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        var escapeCount = 0
        panel.onKeyDown = { event in
            guard event.keyCode == 53 else { return false }
            escapeCount += 1
            return true
        }

        panel.cancelOperation(nil)

        XCTAssertEqual(escapeCount, 1)
    }

    func testArrowDownKeyEventMovesSelectionOneRow() throws {
        let controller = makeController()
        let first = ClipboardItem(
            text: "First",
            createdAt: Date(timeIntervalSince1970: 3),
            sourceAppName: "Tests",
            sourceBundleID: "tests"
        )
        let second = ClipboardItem(
            text: "Second",
            createdAt: Date(timeIntervalSince1970: 2),
            sourceAppName: "Tests",
            sourceBundleID: "tests"
        )
        let third = ClipboardItem(
            text: "Third",
            createdAt: Date(timeIntervalSince1970: 1),
            sourceAppName: "Tests",
            sourceBundleID: "tests"
        )
        controller.show(items: [third, first, second], isAccessibilityTrusted: true)
        let panel = controller.makePanelForTesting()
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: String(UnicodeScalar(NSDownArrowFunctionKey)!),
                charactersIgnoringModifiers: String(UnicodeScalar(NSDownArrowFunctionKey)!),
                isARepeat: false,
                keyCode: 125
            )
        )

        panel.sendEvent(event)

        XCTAssertEqual(controller.selectedItemTextForTesting, "First")
    }

    func testCommandCKeyEventCopiesSelectedItemAndCloses() throws {
        let permission = FakeAccessibilityPermissionProvider(isTrusted: true)
        let writer = FakePasteboardWriter()
        var suppressed: [String] = []
        var didHide = false
        let controller = makeController(
            permission: permission,
            writer: writer,
            prepareForProgrammaticPaste: { suppressed.append($0) },
            hideObserver: { didHide = true }
        )
        controller.onItemPasted = { _ in
            XCTFail("Copy-only should not promote history")
        }
        let item = ClipboardItem(text: "Copy only", sourceAppName: "Tests", sourceBundleID: "tests")
        controller.show(items: [item], isAccessibilityTrusted: true)
        let panel = controller.makePanelForTesting()
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .command,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "c",
                charactersIgnoringModifiers: "c",
                isARepeat: false,
                keyCode: 8
            )
        )

        panel.sendEvent(event)

        XCTAssertEqual(suppressed, ["Copy only"])
        XCTAssertEqual(writer.writtenStrings, ["Copy only"])
        XCTAssertTrue(didHide)
    }

    func testCommandCWithSelectedTextDoesNotInvokePanelCopyHandler() throws {
        let panel = ClipboardPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let textView = NSTextView(frame: panel.contentView?.bounds ?? .zero)
        textView.string = "Selected preview text"
        textView.setSelectedRange(NSRange(location: 0, length: 8))
        panel.contentView = textView
        panel.makeFirstResponder(textView)
        var didInvokePanelCopy = false
        panel.onKeyDown = { event in
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "c" {
                didInvokePanelCopy = true
                return true
            }

            return false
        }
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .command,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "c",
                charactersIgnoringModifiers: "c",
                isARepeat: false,
                keyCode: 8
            )
        )

        panel.sendEvent(event)

        XCTAssertFalse(didInvokePanelCopy)
    }

    private func makeController(
        permission: FakeAccessibilityPermissionProvider = FakeAccessibilityPermissionProvider(isTrusted: false),
        writer: ClipboardPasteboardWriting = FakePasteboardWriter(),
        scheduler: PermissionPollingScheduling = FakePermissionPollingScheduler(),
        targetApplicationProvider: @escaping () -> ClipboardTargetApplication? = { nil },
        pasteActivationScheduler: PasteActivationScheduling = FakePasteActivationScheduler(),
        prepareForProgrammaticPaste: @escaping (String) -> Void = { _ in },
        pasteShortcutPoster: @escaping (pid_t?) -> Bool = { _ in true },
        pasteShortcutScheduler: @escaping (@escaping @MainActor () -> Void) -> Void = { _ in },
        hideObserver: @escaping () -> Void = {}
    ) -> ClipboardPanelController {
        ClipboardPanelController(
            permissionService: permission,
            prepareForProgrammaticPaste: prepareForProgrammaticPaste,
            pasteboardWriter: writer,
            targetApplicationProvider: targetApplicationProvider,
            pasteShortcutPoster: pasteShortcutPoster,
            pasteShortcutScheduler: pasteShortcutScheduler,
            pasteActivationScheduler: pasteActivationScheduler,
            permissionPollingScheduler: scheduler,
            hideObserver: hideObserver,
            isPanelPresentationEnabled: false,
            bundleIdentifier: "com.tests.Clipboard"
        )
    }
}

@MainActor
private final class FakeAccessibilityPermissionProvider: AccessibilityPermissionProviding {
    var isTrusted: Bool
    private(set) var prompts: [Bool] = []
    private(set) var didOpenSystemSettings = false

    init(isTrusted: Bool) {
        self.isTrusted = isTrusted
    }

    func isTrusted(prompt: Bool) -> Bool {
        prompts.append(prompt)
        return isTrusted
    }

    func openSystemSettings() {
        didOpenSystemSettings = true
    }
}

@MainActor
private final class FakePasteboardWriter: ClipboardPasteboardWriting {
    private(set) var writtenStrings: [String] = []

    func writeString(_ text: String) {
        writtenStrings.append(text)
    }
}

@MainActor
private final class RecordingPasteboardWriter: ClipboardPasteboardWriting {
    var onWrite: ((String) -> Void)?

    func writeString(_ text: String) {
        onWrite?(text)
    }
}

@MainActor
private final class FakePermissionPollingScheduler: PermissionPollingScheduling {
    private(set) var startCount = 0
    var action: (@MainActor () -> Bool)?

    func startPolling(
        maxAttempts: Int,
        intervalNanoseconds: UInt64,
        action: @escaping @MainActor () -> Bool
    ) -> PermissionPollingHandle {
        startCount += 1
        self.action = action
        return PermissionPollingHandle {}
    }
}

@MainActor
private final class FakeTargetActivationState {
    var isActive: Bool

    init(isActive: Bool) {
        self.isActive = isActive
    }
}

@MainActor
private final class FakePasteActivationScheduler: PasteActivationScheduling {
    private(set) var startCount = 0
    private(set) var maxAttempts: Int?
    private(set) var intervalNanoseconds: UInt64?
    var action: (@MainActor () -> Bool)?

    func startPolling(
        maxAttempts: Int,
        intervalNanoseconds: UInt64,
        action: @escaping @MainActor () -> Bool
    ) -> PermissionPollingHandle {
        startCount += 1
        self.maxAttempts = maxAttempts
        self.intervalNanoseconds = intervalNanoseconds
        self.action = action
        return PermissionPollingHandle {}
    }
}
