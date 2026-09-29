import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate, SettingsPresenting {
    private var window: SettingsWindow?
    private var viewModel: SettingsViewModel?

    func present(viewModel: SettingsViewModel) {
        self.viewModel = viewModel

        let window = window ?? makeWindow(viewModel: viewModel)
        activateApplication()

        if !window.isVisible {
            window.center()
        }

        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(viewModel: SettingsViewModel) -> SettingsWindow {
        let contentSize = NSSize(
            width: AppConstants.settingsWindowWidth,
            height: AppConstants.settingsWindowHeight
        )
        let window = SettingsWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = String(localized: "\(AppConstants.appName) Settings")
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView(viewModel: viewModel))
        window.setContentSize(contentSize)
        window.onKeyDown = { [weak viewModel] event in
            guard let viewModel else { return false }

            let carbonModifiers = HotkeyShortcut.carbonModifiers(
                from: event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            )
            return viewModel.handleRecordingEvent(
                keyCode: UInt32(event.keyCode),
                carbonModifiers: carbonModifiers
            )
        }

        self.window = window
        return window
    }

    private func activateApplication() {
        // The app runs as an accessory, so it must be activated explicitly to show a regular window.
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        viewModel?.cancelRecording()
    }

    func windowWillClose(_ notification: Notification) {
        viewModel?.cancelRecording()
    }
}

final class SettingsWindow: NSWindow {
    var onKeyDown: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKeyDown?(event) == true {
            return
        }

        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, onKeyDown?(event) == true {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}
