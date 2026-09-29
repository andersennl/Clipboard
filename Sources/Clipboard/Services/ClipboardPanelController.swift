import AppKit
import Carbon
import OSLog
import SwiftUI

@MainActor
protocol ClipboardPanelControlling: AnyObject {
    var onItemPasted: ((ClipboardItem) -> Void)? { get set }

    func show(items: [ClipboardItem], isAccessibilityTrusted: Bool)
    func updateItems(_ items: [ClipboardItem], isAccessibilityTrusted: Bool)
}

@MainActor
protocol ClipboardPasteboardWriting {
    func writeString(_ text: String)
}

struct SystemClipboardPasteboardWriter: ClipboardPasteboardWriting {
    func writeString(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

struct ClipboardTargetApplication {
    let bundleIdentifier: String?
    let processIdentifier: pid_t?
    let isActive: @MainActor () -> Bool
    let activate: @MainActor () -> Bool
}

struct ClipboardPasteShortcutPoster {
    private static let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "PasteBack")
    private let eventPoster: (pid_t?, CGEvent) -> Void

    init(eventPoster: @escaping (pid_t?, CGEvent) -> Void = { _, event in
        // A sandboxed app cannot obtain another process's task port for postToPid.
        // The annotated session tap delivers accessibility-authorized events to the active app.
        event.post(tap: .cgAnnotatedSessionEventTap)
    }) {
        self.eventPoster = eventPoster
    }

    func postPasteShortcut(targetProcessIdentifier _: pid_t?) -> Bool {
        guard
            let source = CGEventSource(stateID: .combinedSessionState),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else {
            Self.logger.error("Could not create synthetic paste events")
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        eventPoster(nil, keyDown)
        eventPoster(nil, keyUp)
        Self.logger.info("Posted paste shortcut through annotated session event tap")
        return true
    }
}

struct ClipboardPanelPlacementScreen: Equatable {
    let frame: NSRect
    let visibleFrame: NSRect
}

enum ClipboardPanelPlacement {
    static func primaryScreen(from screens: [ClipboardPanelPlacementScreen]) -> ClipboardPanelPlacementScreen? {
        screens.first { $0.frame.origin == .zero } ?? screens.first
    }

    static func centeredFrame(panelSize: NSSize, in visibleFrame: NSRect) -> NSRect {
        NSRect(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.midY - panelSize.height / 2,
            width: panelSize.width,
            height: panelSize.height
        )
    }
}

@MainActor
protocol ClipboardPanelPlacementScreenProviding {
    func placementScreen() -> ClipboardPanelPlacementScreen
}

struct SystemClipboardPanelPlacementScreenProvider: ClipboardPanelPlacementScreenProviding {
    func placementScreen() -> ClipboardPanelPlacementScreen {
        let screens = NSScreen.screens.map {
            ClipboardPanelPlacementScreen(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }

        return ClipboardPanelPlacement.primaryScreen(from: screens)
            ?? ClipboardPanelPlacementScreen(frame: .zero, visibleFrame: .zero)
    }
}

@MainActor
final class PermissionPollingHandle {
    private let cancelAction: () -> Void

    init(cancelAction: @escaping () -> Void) {
        self.cancelAction = cancelAction
    }

    func cancel() {
        cancelAction()
    }
}

@MainActor
protocol PermissionPollingScheduling {
    func startPolling(
        maxAttempts: Int,
        intervalNanoseconds: UInt64,
        action: @escaping @MainActor () -> Bool
    ) -> PermissionPollingHandle
}

struct TaskPermissionPollingScheduler: PermissionPollingScheduling {
    func startPolling(
        maxAttempts: Int,
        intervalNanoseconds: UInt64,
        action: @escaping @MainActor () -> Bool
    ) -> PermissionPollingHandle {
        let task = Task { @MainActor in
            for _ in 0..<maxAttempts {
                guard !Task.isCancelled else { return }

                if action() {
                    return
                }

                try? await Task.sleep(nanoseconds: intervalNanoseconds)
            }
        }

        return PermissionPollingHandle {
            task.cancel()
        }
    }
}

@MainActor
protocol PasteActivationScheduling {
    func startPolling(
        maxAttempts: Int,
        intervalNanoseconds: UInt64,
        action: @escaping @MainActor () -> Bool
    ) -> PermissionPollingHandle
}

struct TaskPasteActivationScheduler: PasteActivationScheduling {
    func startPolling(
        maxAttempts: Int,
        intervalNanoseconds: UInt64,
        action: @escaping @MainActor () -> Bool
    ) -> PermissionPollingHandle {
        let task = Task { @MainActor in
            for _ in 0..<maxAttempts {
                guard !Task.isCancelled else { return }

                if action() {
                    return
                }

                try? await Task.sleep(nanoseconds: intervalNanoseconds)
            }
        }

        return PermissionPollingHandle {
            task.cancel()
        }
    }
}

@MainActor
final class ClipboardPanelController: NSObject, NSWindowDelegate, ClipboardPanelControlling {
    private static let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "PasteBack")
    private static let pasteActivationMaxAttempts = 40
    private static let pasteActivationIntervalNanoseconds: UInt64 = 50_000_000

    private let permissionService: AccessibilityPermissionProviding
    private let prepareForProgrammaticPaste: (String) -> Void
    private let pasteboardWriter: ClipboardPasteboardWriting
    private let targetApplicationProvider: () -> ClipboardTargetApplication?
    private let pasteShortcutPoster: (pid_t?) -> Bool
    private let pasteShortcutScheduler: (@escaping @MainActor () -> Void) -> Void
    private let pasteActivationScheduler: PasteActivationScheduling
    private let permissionPollingScheduler: PermissionPollingScheduling
    private let placementScreenProvider: ClipboardPanelPlacementScreenProviding
    private let hideObserver: () -> Void
    private let isPanelPresentationEnabled: Bool
    private let viewModel: HistoryPanelViewModel
    private let bundleIdentifier: String

    private var panel: ClipboardPanelWindow?
    private var permissionPollingHandle: PermissionPollingHandle?
    private var pasteActivationPollingHandle: PermissionPollingHandle?
    private var pasteRequestToken = UUID()
    private var placementTask: Task<Void, Never>?
    private var previousApplication: ClipboardTargetApplication?
    var onItemPasted: ((ClipboardItem) -> Void)?

    init(
        permissionService: AccessibilityPermissionProviding,
        prepareForProgrammaticPaste: @escaping (String) -> Void,
        pasteboardWriter: ClipboardPasteboardWriting = SystemClipboardPasteboardWriter(),
        targetApplicationProvider: @escaping () -> ClipboardTargetApplication? = {
            guard let application = NSWorkspace.shared.frontmostApplication else { return nil }

            return ClipboardTargetApplication(
                bundleIdentifier: application.bundleIdentifier,
                processIdentifier: application.processIdentifier,
                isActive: {
                    application.isActive
                },
                activate: {
                    if #available(macOS 14.0, *) {
                        NSApp.yieldActivation(to: application)
                        return application.activate(from: NSRunningApplication.current, options: [.activateAllWindows])
                    } else {
                        return application.activate(options: [.activateIgnoringOtherApps])
                    }
                }
            )
        },
        pasteShortcutPoster: ((pid_t?) -> Bool)? = nil,
        pasteShortcutScheduler: @escaping (@escaping @MainActor () -> Void) -> Void = { action in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                Task { @MainActor in
                    action()
                }
            }
        },
        pasteActivationScheduler: PasteActivationScheduling = TaskPasteActivationScheduler(),
        permissionPollingScheduler: PermissionPollingScheduling = TaskPermissionPollingScheduler(),
        placementScreenProvider: ClipboardPanelPlacementScreenProviding = SystemClipboardPanelPlacementScreenProvider(),
        hideObserver: @escaping () -> Void = {},
        isPanelPresentationEnabled: Bool = true,
        bundleIdentifier: String = AppConstants.bundleIdentifier
    ) {
        self.permissionService = permissionService
        self.prepareForProgrammaticPaste = prepareForProgrammaticPaste
        self.pasteboardWriter = pasteboardWriter
        self.targetApplicationProvider = targetApplicationProvider
        self.pasteShortcutPoster = pasteShortcutPoster ?? {
            ClipboardPasteShortcutPoster().postPasteShortcut(targetProcessIdentifier: $0)
        }
        self.pasteShortcutScheduler = pasteShortcutScheduler
        self.pasteActivationScheduler = pasteActivationScheduler
        self.permissionPollingScheduler = permissionPollingScheduler
        self.placementScreenProvider = placementScreenProvider
        self.hideObserver = hideObserver
        self.isPanelPresentationEnabled = isPanelPresentationEnabled
        self.bundleIdentifier = bundleIdentifier
        self.viewModel = HistoryPanelViewModel()

        super.init()

        viewModel.onPasteRequested = { [weak self] item in
            self?.pasteSelectedItem(item)
        }
        viewModel.onDismissRequested = { [weak self] in
            self?.hide()
        }
        viewModel.onGrantAccessRequested = { [weak self] in
            self?.requestAccessibilityAccess()
        }
    }

    func show(items: [ClipboardItem], isAccessibilityTrusted: Bool) {
        invalidatePendingPasteRequest()
        capturePreviousApplication()
        viewModel.present(
            items: items,
            isAccessibilityTrusted: permissionService.isTrusted() || isAccessibilityTrusted
        )

        guard isPanelPresentationEnabled else { return }

        let placementScreen = placementScreenProvider.placementScreen()

        let panel = panel ?? makePanel()
        positionPanel(panel, on: placementScreen)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        positionPanel(panel, on: placementScreen)
        schedulePostShowPlacement(for: panel, on: placementScreen)
    }

    func hide() {
        placementTask?.cancel()
        placementTask = nil
        panel?.orderOut(nil)
        hideObserver()
    }

    func updateItems(_ items: [ClipboardItem], isAccessibilityTrusted: Bool) {
        viewModel.updateItems(
            items,
            isAccessibilityTrusted: permissionService.isTrusted() || isAccessibilityTrusted
        )
    }

    func requestAccessibilityAccess() {
        permissionService.openSystemSettings()
        startPermissionPolling()
    }

    private func startPermissionPolling() {
        permissionPollingHandle?.cancel()
        permissionPollingHandle = permissionPollingScheduler.startPolling(
            maxAttempts: 60,
            intervalNanoseconds: 500_000_000
        ) { [weak self] in
            self?.refreshAccessibilityStatus() ?? true
        }
    }

    @discardableResult
    func refreshAccessibilityStatus() -> Bool {
        let isTrusted = permissionService.isTrusted()
        viewModel.isAccessibilityTrusted = isTrusted
        return isTrusted
    }

    func pasteSelectedItem(_ item: ClipboardItem) {
        let pasteRequestToken = beginPasteRequest()
        prepareForProgrammaticPaste(item.text)
        pasteboardWriter.writeString(item.text)

        let isAccessibilityTrusted = permissionService.isTrusted(prompt: true)
        Self.logger.info("Paste requested; accessibility trusted: \(isAccessibilityTrusted)")

        guard isAccessibilityTrusted else {
            viewModel.isAccessibilityTrusted = false
            hide()
            return
        }

        viewModel.isAccessibilityTrusted = true

        let targetApplication = previousApplication
        Self.logger.info(
            "Paste target: \(targetApplication?.bundleIdentifier ?? "none", privacy: .public)"
        )
        hide()

        guard let targetApplication else { return }

        if targetApplication.isActive() {
            schedulePasteShortcut(for: targetApplication, item: item, pasteRequestToken: pasteRequestToken)
            return
        }

        guard targetApplication.activate() else { return }

        waitForTargetActivationThenPaste(targetApplication, item: item, pasteRequestToken: pasteRequestToken)
    }

    private func capturePreviousApplication() {
        guard let frontmost = targetApplicationProvider(),
              frontmost.bundleIdentifier != bundleIdentifier else {
            previousApplication = nil
            return
        }

        previousApplication = frontmost
        Self.logger.info(
            "Captured paste target: \(frontmost.bundleIdentifier ?? "unknown", privacy: .public)"
        )
    }

    private func beginPasteRequest() -> UUID {
        pasteActivationPollingHandle?.cancel()
        let token = UUID()
        pasteRequestToken = token
        return token
    }

    private func invalidatePendingPasteRequest() {
        pasteActivationPollingHandle?.cancel()
        pasteRequestToken = UUID()
    }

    private func waitForTargetActivationThenPaste(
        _ targetApplication: ClipboardTargetApplication,
        item: ClipboardItem,
        pasteRequestToken: UUID
    ) {
        var didSchedulePasteShortcut = false
        pasteActivationPollingHandle = pasteActivationScheduler.startPolling(
            maxAttempts: Self.pasteActivationMaxAttempts,
            intervalNanoseconds: Self.pasteActivationIntervalNanoseconds
        ) { [weak self] in
            guard let self else { return true }
            guard !didSchedulePasteShortcut else { return true }
            guard targetApplication.isActive() else { return false }

            didSchedulePasteShortcut = true
            schedulePasteShortcut(for: targetApplication, item: item, pasteRequestToken: pasteRequestToken)
            return true
        }
    }

    private func schedulePasteShortcut(
        for targetApplication: ClipboardTargetApplication,
        item: ClipboardItem,
        pasteRequestToken: UUID
    ) {
        pasteShortcutScheduler { [weak self] in
            guard let self, pasteRequestToken == self.pasteRequestToken else { return }
            guard self.pasteShortcutPoster(targetApplication.processIdentifier) else { return }

            self.onItemPasted?(item)
        }
    }

    private func positionPanel(_ panel: NSPanel, on screen: ClipboardPanelPlacementScreen) {
        let frame = ClipboardPanelPlacement.centeredFrame(
            panelSize: NSSize(
                width: AppConstants.historyPanelWidth,
                height: AppConstants.historyPanelHeight
            ),
            in: screen.visibleFrame
        )

        panel.setFrame(frame, display: false)
    }

    private func schedulePostShowPlacement(
        for panel: ClipboardPanelWindow,
        on screen: ClipboardPanelPlacementScreen
    ) {
        placementTask?.cancel()
        placementTask = Task { @MainActor [weak self, weak panel] in
            await Task.yield()

            guard !Task.isCancelled, let self, let panel, panel.isVisible else { return }

            self.positionPanel(panel, on: screen)
            panel.displayIfNeeded()
        }
    }

    private func makePanel() -> ClipboardPanelWindow {
        let fixedPanelSize = NSSize(
            width: AppConstants.historyPanelWidth,
            height: AppConstants.historyPanelHeight
        )
        let panel = ClipboardPanelWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: fixedPanelSize.width,
                height: fixedPanelSize.height
            ),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.delegate = self
        panel.isOpaque = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.appearance = NSAppearance(named: .aqua)
        panel.onKeyDown = { [weak self] event in
            self?.handlePanelKeyDown(event) ?? false
        }
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        panel.minSize = fixedPanelSize
        panel.maxSize = fixedPanelSize
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        let hostingController = NSHostingController(
            rootView: HistoryPanelView(viewModel: viewModel)
        )
        hostingController.view.appearance = NSAppearance(named: .aqua)
        hostingController.view.frame = NSRect(origin: .zero, size: fixedPanelSize)
        panel.contentViewController = hostingController
        panel.setContentSize(fixedPanelSize)
        self.panel = panel
        return panel
    }

    private func handlePanelKeyDown(_ event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "c" {
            copySelectedItem()
            return true
        }

        switch event.keyCode {
        case 53:
            hide()
            return true
        case 125:
            viewModel.moveSelection(offset: 1)
            return true
        case 126:
            viewModel.moveSelection(offset: -1)
            return true
        case 36, 76:
            viewModel.confirmSelection()
            return true
        default:
            return false
        }
    }

    private func copySelectedItem() {
        guard let selectedItem = viewModel.selectedItem else { return }

        invalidatePendingPasteRequest()
        prepareForProgrammaticPaste(selectedItem.text)
        pasteboardWriter.writeString(selectedItem.text)
        hide()
    }

    func makePanelForTesting() -> ClipboardPanelWindow {
        panel ?? makePanel()
    }

    func positionPanelForTesting(_ panel: NSPanel, on screen: ClipboardPanelPlacementScreen) {
        positionPanel(panel, on: screen)
    }

    var isAccessibilityTrustedForTesting: Bool {
        viewModel.isAccessibilityTrusted
    }

    var selectedItemTextForTesting: String? {
        viewModel.selectedItem?.text
    }

    func setPreviousApplicationForTesting(_ application: ClipboardTargetApplication?) {
        previousApplication = application
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refreshAccessibilityStatus()
    }
}

final class ClipboardPanelWindow: NSPanel {
    var onKeyDown: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.isCommandC, hasSelectedTextInFirstResponder {
            super.sendEvent(event)
            return
        }

        if event.type == .keyDown, onKeyDown?(event) == true {
            return
        }

        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53, handleKeyDown(event) {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        ) else {
            return
        }

        if !handleKeyDown(event) {
            super.cancelOperation(sender)
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        event.type == .keyDown && onKeyDown?(event) == true
    }

    private var hasSelectedTextInFirstResponder: Bool {
        guard let textView = firstResponder as? NSTextView else { return false }
        return textView.selectedRange().length > 0
    }
}

private extension NSEvent {
    var isCommandC: Bool {
        type == .keyDown
            && modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
            && charactersIgnoringModifiers?.lowercased() == "c"
    }
}
