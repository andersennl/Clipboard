import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ClipboardAppModel {
    private let store: ClipboardStoring
    private let monitorService: ClipboardMonitoring
    private let hotkeyService: GlobalHotkeyServing
    private let hotkeyPreferenceStore: HotkeyPreferenceStoring
    private let permissionService: AccessibilityPermissionProviding
    private let panelController: ClipboardPanelControlling
    private let launchAtLoginService: LaunchAtLoginServing
    private let settingsPresenter: SettingsPresenting
    private let settingsViewModel: SettingsViewModel

    private var launchObserver: NSObjectProtocol?
    private var hasStarted = false

    private(set) var items: [ClipboardItem]
    private(set) var isMonitoringEnabled: Bool
    private(set) var hasAccessibilityAccess: Bool
    private(set) var launchAtLoginState: LaunchAtLoginService.State
    private(set) var hotkeyShortcut: HotkeyShortcut

    init(
        store: ClipboardStoring = ClipboardStore(),
        permissionService: AccessibilityPermissionProviding = AccessibilityPermissionService(),
        monitorService: ClipboardMonitoring = ClipboardMonitorService(),
        hotkeyService: GlobalHotkeyServing = GlobalHotkeyService(),
        hotkeyPreferenceStore: HotkeyPreferenceStoring = HotkeyPreferenceStore(),
        launchAtLoginService: LaunchAtLoginServing = LaunchAtLoginService(),
        settingsPresenter: SettingsPresenting = SettingsWindowController(),
        panelController: ClipboardPanelControlling? = nil
    ) {
        self.store = store
        self.monitorService = monitorService
        self.hotkeyService = hotkeyService
        self.hotkeyPreferenceStore = hotkeyPreferenceStore
        self.permissionService = permissionService
        self.launchAtLoginService = launchAtLoginService
        self.settingsPresenter = settingsPresenter
        self.items = store.items
        self.isMonitoringEnabled = store.isMonitoringEnabled
        self.hasAccessibilityAccess = permissionService.isTrusted()
        self.launchAtLoginState = launchAtLoginService.state
        self.hotkeyShortcut = hotkeyPreferenceStore.shortcut
        self.settingsViewModel = SettingsViewModel(shortcut: hotkeyPreferenceStore.shortcut)
        self.panelController = panelController ?? ClipboardPanelController(
            permissionService: permissionService,
            prepareForProgrammaticPaste: { text in
                monitorService.suppressNextCapture(text: text)
            }
        )
        self.panelController.onItemPasted = { [weak self] item in
            self?.handlePastedItem(item)
        }

        monitorService.onCapture = { [weak self] item in
            self?.handleCapturedItem(item)
        }

        hotkeyService.onHotKeyPressed = { [weak self] in
            self?.openClipboardHistory()
        }

        settingsViewModel.onShortcutChanged = { [weak self] shortcut in
            self?.updateHotkeyShortcut(shortcut)
        }

        settingsViewModel.onLaunchAtLoginChanged = { [weak self] enabled in
            self?.setLaunchAtLogin(enabled)
        }

        settingsViewModel.updateLaunchAtLoginState(launchAtLoginService.state)

        launchObserver = NotificationCenter.default.addObserver(
            forName: .clipboardApplicationDidFinishLaunching,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.startIfNeeded()
            }
        }
    }

    func openClipboardHistory() {
        hasAccessibilityAccess = permissionService.isTrusted()
        panelController.show(items: items, isAccessibilityTrusted: hasAccessibilityAccess)
    }

    func toggleMonitoring() {
        isMonitoringEnabled.toggle()
        store.setMonitoringEnabled(isMonitoringEnabled)

        if isMonitoringEnabled {
            monitorService.start()
        } else {
            monitorService.stop()
        }
    }

    func clearHistory() {
        store.clear()
        items = store.items
        panelController.updateItems(items, isAccessibilityTrusted: permissionService.isTrusted())
    }

    func openAccessibilitySettings() {
        permissionService.openSystemSettings()
    }

    func openSettings() {
        settingsViewModel.updateShortcut(hotkeyShortcut)
        refreshLaunchAtLoginState()
        settingsPresenter.present(viewModel: settingsViewModel)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginState = launchAtLoginService.setEnabled(enabled)
        settingsViewModel.updateLaunchAtLoginState(launchAtLoginState)
    }

    private func refreshLaunchAtLoginState() {
        launchAtLoginState = launchAtLoginService.state
        settingsViewModel.updateLaunchAtLoginState(launchAtLoginState)
    }

    func updateHotkeyShortcut(_ shortcut: HotkeyShortcut) {
        guard shortcut.isValid, shortcut != hotkeyShortcut else { return }

        hotkeyShortcut = shortcut
        hotkeyPreferenceStore.setShortcut(shortcut)
        hotkeyService.register(shortcut: shortcut)
    }

    private func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true

        // The login item is opt-in and is only ever registered from the settings toggle.
        launchAtLoginState = launchAtLoginService.state
        hotkeyService.register(shortcut: hotkeyShortcut)

        if isMonitoringEnabled {
            monitorService.start()
        }
    }

    private func handleCapturedItem(_ item: ClipboardItem) {
        let didAppend = store.append(item)
        guard didAppend else { return }

        items = store.items
        hasAccessibilityAccess = permissionService.isTrusted()
        panelController.updateItems(items, isAccessibilityTrusted: hasAccessibilityAccess)
    }

    private func handlePastedItem(_ item: ClipboardItem) {
        let didFindItem = store.moveToFront(id: item.id)
        guard didFindItem else { return }

        items = store.items
        hasAccessibilityAccess = permissionService.isTrusted()
        panelController.updateItems(items, isAccessibilityTrusted: hasAccessibilityAccess)
    }
}
