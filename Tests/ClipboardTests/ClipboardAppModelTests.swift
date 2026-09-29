import Carbon
import XCTest
@testable import Clipboard

@MainActor
final class ClipboardAppModelTests: XCTestCase {
    func testHotkeyOpenFlowRefreshesPermissionAndShowsPanelWithItems() {
        let item = ClipboardItem(text: "Open", sourceAppName: "Tests", sourceBundleID: "tests")
        let store = FakeClipboardStore(items: [item])
        let permission = FakeAppPermissionProvider(isTrusted: false)
        let monitor = FakeClipboardMonitor()
        let hotkey = FakeGlobalHotkey()
        let panel = FakeClipboardPanel()
        let model = ClipboardAppModel(
            store: store,
            permissionService: permission,
            monitorService: monitor,
            hotkeyService: hotkey,
            launchAtLoginService: FakeLaunchAtLoginService(),
            panelController: panel
        )

        permission.isTrusted = true
        hotkey.press()

        XCTAssertTrue(model.hasAccessibilityAccess)
        XCTAssertEqual(panel.shownItems.map(\.id), [item.id])
        XCTAssertEqual(panel.showTrustValues, [true])
    }

    func testCaptureFlowAppendsAndUpdatesPanelForNewItem() {
        let store = FakeClipboardStore()
        let permission = FakeAppPermissionProvider(isTrusted: true)
        let monitor = FakeClipboardMonitor()
        let panel = FakeClipboardPanel()
        let model = ClipboardAppModel(
            store: store,
            permissionService: permission,
            monitorService: monitor,
            hotkeyService: FakeGlobalHotkey(),
            launchAtLoginService: FakeLaunchAtLoginService(),
            panelController: panel
        )
        let item = ClipboardItem(text: "Captured", sourceAppName: "Tests", sourceBundleID: "tests")

        monitor.capture(item)

        XCTAssertEqual(model.items.map(\.id), [item.id])
        XCTAssertEqual(panel.updatedItems.map(\.id), [item.id])
        XCTAssertEqual(panel.updateTrustValues, [true])
    }

    func testCaptureAndOpenFlowsNeverRequestThePermissionPrompt() {
        let store = FakeClipboardStore()
        let permission = FakeAppPermissionProvider(isTrusted: false)
        let monitor = FakeClipboardMonitor()
        let hotkey = FakeGlobalHotkey()
        _ = ClipboardAppModel(
            store: store,
            permissionService: permission,
            monitorService: monitor,
            hotkeyService: hotkey,
            launchAtLoginService: FakeLaunchAtLoginService(),
            panelController: FakeClipboardPanel()
        )

        hotkey.press()
        monitor.capture(ClipboardItem(text: "Captured", sourceAppName: "Tests", sourceBundleID: "tests"))

        XCTAssertFalse(permission.promptValues.isEmpty)
        XCTAssertFalse(permission.promptValues.contains(true))
    }

    func testCaptureFlowDoesNotUpdatePanelWhenStoreRejectsItem() {
        let store = FakeClipboardStore(shouldAppend: false)
        let monitor = FakeClipboardMonitor()
        let panel = FakeClipboardPanel()
        let model = ClipboardAppModel(
            store: store,
            permissionService: FakeAppPermissionProvider(isTrusted: true),
            monitorService: monitor,
            hotkeyService: FakeGlobalHotkey(),
            launchAtLoginService: FakeLaunchAtLoginService(),
            panelController: panel
        )

        monitor.capture(ClipboardItem(text: "Duplicate", sourceAppName: "Tests", sourceBundleID: "tests"))

        XCTAssertTrue(model.items.isEmpty)
        XCTAssertTrue(panel.updatedItems.isEmpty)
    }

    func testClearHistoryClearsStoreAndUpdatesPanel() {
        let item = ClipboardItem(text: "Delete", sourceAppName: "Tests", sourceBundleID: "tests")
        let store = FakeClipboardStore(items: [item])
        let panel = FakeClipboardPanel()
        let model = ClipboardAppModel(
            store: store,
            permissionService: FakeAppPermissionProvider(isTrusted: false),
            monitorService: FakeClipboardMonitor(),
            hotkeyService: FakeGlobalHotkey(),
            launchAtLoginService: FakeLaunchAtLoginService(),
            panelController: panel
        )

        model.clearHistory()

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertTrue(panel.updatedItems.isEmpty)
        XCTAssertEqual(panel.updateTrustValues, [false])
    }

    func testPastedHistoryItemMovesToFrontAndUpdatesPanel() {
        let first = ClipboardItem(text: "First", sourceAppName: "Tests", sourceBundleID: "tests")
        let second = ClipboardItem(text: "Second", sourceAppName: "Tests", sourceBundleID: "tests")
        let third = ClipboardItem(text: "Third", sourceAppName: "Tests", sourceBundleID: "tests")
        let store = FakeClipboardStore(items: [first, second, third])
        let panel = FakeClipboardPanel()
        let model = ClipboardAppModel(
            store: store,
            permissionService: FakeAppPermissionProvider(isTrusted: true),
            monitorService: FakeClipboardMonitor(),
            hotkeyService: FakeGlobalHotkey(),
            launchAtLoginService: FakeLaunchAtLoginService(),
            panelController: panel
        )

        panel.reportItemPasted(third)

        XCTAssertEqual(store.items.map(\.id), [third.id, first.id, second.id])
        XCTAssertEqual(model.items.map(\.id), [third.id, first.id, second.id])
        XCTAssertEqual(panel.updatedItems.map(\.id), [third.id, first.id, second.id])
        XCTAssertEqual(panel.updateTrustValues, [true])
    }

    func testToggleMonitoringStopsAndStartsMonitorAndPersistsState() {
        let store = FakeClipboardStore(isMonitoringEnabled: true)
        let monitor = FakeClipboardMonitor()
        let model = ClipboardAppModel(
            store: store,
            permissionService: FakeAppPermissionProvider(isTrusted: true),
            monitorService: monitor,
            hotkeyService: FakeGlobalHotkey(),
            launchAtLoginService: FakeLaunchAtLoginService(),
            panelController: FakeClipboardPanel()
        )

        model.toggleMonitoring()
        model.toggleMonitoring()

        XCTAssertEqual(store.persistedMonitoringValues, [false, true])
        XCTAssertEqual(monitor.stopCount, 1)
        XCTAssertEqual(monitor.startCount, 1)
        XCTAssertTrue(model.isMonitoringEnabled)
    }

    func testLaunchRegistersStoredHotkeyShortcut() async {
        let storedShortcut = HotkeyShortcut(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: UInt32(cmdKey | optionKey))
        let hotkey = FakeGlobalHotkey()
        let model = ClipboardAppModel(
            store: FakeClipboardStore(isMonitoringEnabled: false),
            permissionService: FakeAppPermissionProvider(isTrusted: true),
            monitorService: FakeClipboardMonitor(),
            hotkeyService: hotkey,
            hotkeyPreferenceStore: FakeHotkeyPreferenceStore(shortcut: storedShortcut),
            launchAtLoginService: FakeLaunchAtLoginService(),
            settingsPresenter: FakeSettingsPresenter(),
            panelController: FakeClipboardPanel()
        )

        NotificationCenter.default.post(name: .clipboardApplicationDidFinishLaunching, object: nil)
        // The launch notification is delivered on the main queue and starts the app asynchronously.
        await waitUntil { !hotkey.registeredShortcuts.isEmpty }

        XCTAssertEqual(model.hotkeyShortcut, storedShortcut)
        XCTAssertEqual(hotkey.registeredShortcuts, [storedShortcut])
    }

    func testLaunchNeverRegistersTheLoginItemOnItsOwn() async {
        let launchAtLogin = FakeLaunchAtLoginService()
        let hotkey = FakeGlobalHotkey()
        let model = ClipboardAppModel(
            store: FakeClipboardStore(isMonitoringEnabled: false),
            permissionService: FakeAppPermissionProvider(isTrusted: true),
            monitorService: FakeClipboardMonitor(),
            hotkeyService: hotkey,
            launchAtLoginService: launchAtLogin,
            panelController: FakeClipboardPanel()
        )

        NotificationCenter.default.post(name: .clipboardApplicationDidFinishLaunching, object: nil)
        await waitUntil { !hotkey.registeredShortcuts.isEmpty }

        XCTAssertTrue(launchAtLogin.requestedValues.isEmpty)
        XCTAssertEqual(model.launchAtLoginState, .notRegistered)
    }

    func testSettingLaunchAtLoginForwardsToServiceAndPublishesResultingState() {
        let launchAtLogin = FakeLaunchAtLoginService()
        let model = ClipboardAppModel(
            store: FakeClipboardStore(),
            permissionService: FakeAppPermissionProvider(isTrusted: true),
            monitorService: FakeClipboardMonitor(),
            hotkeyService: FakeGlobalHotkey(),
            launchAtLoginService: launchAtLogin,
            panelController: FakeClipboardPanel()
        )

        model.setLaunchAtLogin(true)

        XCTAssertEqual(launchAtLogin.requestedValues, [true])
        XCTAssertEqual(model.launchAtLoginState, .enabled)

        model.setLaunchAtLogin(false)

        XCTAssertEqual(launchAtLogin.requestedValues, [true, false])
        XCTAssertEqual(model.launchAtLoginState, .notRegistered)
    }

    func testSettingLaunchAtLoginPublishesRequiresApprovalWhenMacOSDefersTheDecision() {
        let launchAtLogin = FakeLaunchAtLoginService()
        launchAtLogin.stateAfterEnabling = .requiresApproval
        let model = ClipboardAppModel(
            store: FakeClipboardStore(),
            permissionService: FakeAppPermissionProvider(isTrusted: true),
            monitorService: FakeClipboardMonitor(),
            hotkeyService: FakeGlobalHotkey(),
            launchAtLoginService: launchAtLogin,
            panelController: FakeClipboardPanel()
        )

        model.setLaunchAtLogin(true)

        XCTAssertEqual(model.launchAtLoginState, .requiresApproval)
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)

        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func testUpdatingHotkeyShortcutPersistsAndReregisters() {
        let hotkey = FakeGlobalHotkey()
        let preferenceStore = FakeHotkeyPreferenceStore(shortcut: .default)
        let model = ClipboardAppModel(
            store: FakeClipboardStore(),
            permissionService: FakeAppPermissionProvider(isTrusted: true),
            monitorService: FakeClipboardMonitor(),
            hotkeyService: hotkey,
            hotkeyPreferenceStore: preferenceStore,
            launchAtLoginService: FakeLaunchAtLoginService(),
            settingsPresenter: FakeSettingsPresenter(),
            panelController: FakeClipboardPanel()
        )
        let newShortcut = HotkeyShortcut(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(controlKey | optionKey))

        model.updateHotkeyShortcut(newShortcut)

        XCTAssertEqual(model.hotkeyShortcut, newShortcut)
        XCTAssertEqual(preferenceStore.persistedShortcuts, [newShortcut])
        XCTAssertEqual(hotkey.registeredShortcuts, [newShortcut])
    }

    func testUpdatingHotkeyShortcutRejectsShortcutWithoutPrimaryModifier() {
        let hotkey = FakeGlobalHotkey()
        let preferenceStore = FakeHotkeyPreferenceStore(shortcut: .default)
        let model = ClipboardAppModel(
            store: FakeClipboardStore(),
            permissionService: FakeAppPermissionProvider(isTrusted: true),
            monitorService: FakeClipboardMonitor(),
            hotkeyService: hotkey,
            hotkeyPreferenceStore: preferenceStore,
            launchAtLoginService: FakeLaunchAtLoginService(),
            settingsPresenter: FakeSettingsPresenter(),
            panelController: FakeClipboardPanel()
        )

        model.updateHotkeyShortcut(HotkeyShortcut(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: UInt32(shiftKey)))

        XCTAssertEqual(model.hotkeyShortcut, .default)
        XCTAssertTrue(preferenceStore.persistedShortcuts.isEmpty)
        XCTAssertTrue(hotkey.registeredShortcuts.isEmpty)
    }

    func testSettingsRecordingUpdatesHotkeyThroughSharedViewModel() {
        let hotkey = FakeGlobalHotkey()
        let preferenceStore = FakeHotkeyPreferenceStore(shortcut: .default)
        let presenter = FakeSettingsPresenter()
        let model = ClipboardAppModel(
            store: FakeClipboardStore(),
            permissionService: FakeAppPermissionProvider(isTrusted: true),
            monitorService: FakeClipboardMonitor(),
            hotkeyService: hotkey,
            hotkeyPreferenceStore: preferenceStore,
            launchAtLoginService: FakeLaunchAtLoginService(),
            settingsPresenter: presenter,
            panelController: FakeClipboardPanel()
        )

        model.openSettings()
        let presentedViewModel = presenter.presentedViewModels.last
        presentedViewModel?.beginRecording()
        presentedViewModel?.handleRecordingEvent(
            keyCode: UInt32(kVK_ANSI_K),
            carbonModifiers: UInt32(cmdKey | optionKey)
        )

        XCTAssertEqual(presenter.presentedViewModels.count, 1)
        XCTAssertEqual(model.hotkeyShortcut.keyCode, UInt32(kVK_ANSI_K))
        XCTAssertEqual(hotkey.registeredShortcuts.map(\.keyCode), [UInt32(kVK_ANSI_K)])
        XCTAssertEqual(preferenceStore.persistedShortcuts.map(\.keyCode), [UInt32(kVK_ANSI_K)])
    }
}

@MainActor
private final class FakeClipboardStore: ClipboardStoring {
    private(set) var items: [ClipboardItem]
    private(set) var isMonitoringEnabled: Bool
    private let shouldAppend: Bool
    private(set) var persistedMonitoringValues: [Bool] = []

    init(items: [ClipboardItem] = [], isMonitoringEnabled: Bool = true, shouldAppend: Bool = true) {
        self.items = items
        self.isMonitoringEnabled = isMonitoringEnabled
        self.shouldAppend = shouldAppend
    }

    @discardableResult
    func append(_ item: ClipboardItem) -> Bool {
        guard shouldAppend else { return false }
        items.insert(item, at: 0)
        return true
    }

    @discardableResult
    func moveToFront(id: ClipboardItem.ID) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        guard index != 0 else { return true }

        let item = items.remove(at: index)
        items.insert(item, at: 0)
        return true
    }

    func clear() {
        items = []
    }

    func setMonitoringEnabled(_ isEnabled: Bool) {
        isMonitoringEnabled = isEnabled
        persistedMonitoringValues.append(isEnabled)
    }
}

@MainActor
private final class FakeClipboardMonitor: ClipboardMonitoring {
    var onCapture: ((ClipboardItem) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var suppressedTexts: [String] = []

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func suppressNextCapture(text: String) {
        suppressedTexts.append(text)
    }

    func capture(_ item: ClipboardItem) {
        onCapture?(item)
    }
}

@MainActor
private final class FakeGlobalHotkey: GlobalHotkeyServing {
    var onHotKeyPressed: (() -> Void)?
    private(set) var registeredShortcuts: [HotkeyShortcut] = []

    func register(shortcut: HotkeyShortcut) {
        registeredShortcuts.append(shortcut)
    }

    func press() {
        onHotKeyPressed?()
    }
}

@MainActor
private final class FakeHotkeyPreferenceStore: HotkeyPreferenceStoring {
    private(set) var shortcut: HotkeyShortcut
    private(set) var persistedShortcuts: [HotkeyShortcut] = []

    init(shortcut: HotkeyShortcut) {
        self.shortcut = shortcut
    }

    func setShortcut(_ shortcut: HotkeyShortcut) {
        self.shortcut = shortcut
        persistedShortcuts.append(shortcut)
    }
}

@MainActor
private final class FakeSettingsPresenter: SettingsPresenting {
    private(set) var presentedViewModels: [SettingsViewModel] = []

    func present(viewModel: SettingsViewModel) {
        presentedViewModels.append(viewModel)
    }
}

@MainActor
private final class FakeClipboardPanel: ClipboardPanelControlling {
    var onItemPasted: ((ClipboardItem) -> Void)?
    private(set) var shownItems: [ClipboardItem] = []
    private(set) var showTrustValues: [Bool] = []
    private(set) var updatedItems: [ClipboardItem] = []
    private(set) var updateTrustValues: [Bool] = []

    func show(items: [ClipboardItem], isAccessibilityTrusted: Bool) {
        shownItems = items
        showTrustValues.append(isAccessibilityTrusted)
    }

    func updateItems(_ items: [ClipboardItem], isAccessibilityTrusted: Bool) {
        updatedItems = items
        updateTrustValues.append(isAccessibilityTrusted)
    }

    func reportItemPasted(_ item: ClipboardItem) {
        onItemPasted?(item)
    }
}

@MainActor
private final class FakeAppPermissionProvider: AccessibilityPermissionProviding {
    var isTrusted: Bool
    private(set) var didOpenSettings = false
    private(set) var promptValues: [Bool] = []

    init(isTrusted: Bool) {
        self.isTrusted = isTrusted
    }

    func isTrusted(prompt: Bool) -> Bool {
        promptValues.append(prompt)
        return isTrusted
    }

    func openSystemSettings() {
        didOpenSettings = true
    }
}

@MainActor
private final class FakeLaunchAtLoginService: LaunchAtLoginServing {
    var state: LaunchAtLoginService.State = .notRegistered
    var stateAfterEnabling: LaunchAtLoginService.State = .enabled
    private(set) var requestedValues: [Bool] = []

    @discardableResult
    func setEnabled(_ enabled: Bool) -> LaunchAtLoginService.State {
        requestedValues.append(enabled)
        state = enabled ? stateAfterEnabling : .notRegistered
        return state
    }
}
