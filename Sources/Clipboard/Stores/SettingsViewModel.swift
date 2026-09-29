import Carbon
import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    private(set) var shortcut: HotkeyShortcut
    private(set) var isRecording: Bool = false
    private(set) var validationMessage: String?
    private(set) var isLaunchAtLoginEnabled: Bool = false
    private(set) var launchAtLoginMessage: String?

    var onShortcutChanged: ((HotkeyShortcut) -> Void)?
    var onLaunchAtLoginChanged: ((Bool) -> Void)?

    init(shortcut: HotkeyShortcut = .default) {
        self.shortcut = shortcut
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        isLaunchAtLoginEnabled = enabled
        onLaunchAtLoginChanged?(enabled)
    }

    /// Mirrors what macOS actually did, which is not always what the toggle asked for.
    func updateLaunchAtLoginState(_ state: LaunchAtLoginService.State) {
        isLaunchAtLoginEnabled = state.isOn
        launchAtLoginMessage = state == .requiresApproval
            ? String(localized: "Waiting for approval in System Settings › General › Login Items.")
            : nil
    }

    var websiteURLString: String {
        AppConstants.websiteURLString
    }

    var privacyPolicyURLString: String {
        AppConstants.privacyPolicyURLString
    }

    var appVersionDescription: String {
        let infoDictionary = Bundle.main.infoDictionary
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return String(localized: "Version \(version) (\(build))")
    }

    func beginRecording() {
        isRecording = true
        validationMessage = nil
    }

    func cancelRecording() {
        isRecording = false
        validationMessage = nil
    }

    func resetToDefault() {
        isRecording = false
        validationMessage = nil
        apply(.default)
    }

    func updateShortcut(_ shortcut: HotkeyShortcut) {
        self.shortcut = shortcut
    }

    /// Handles a key press while recording. Returns `true` when the event was consumed by the recorder.
    @discardableResult
    func handleRecordingEvent(keyCode: UInt32, carbonModifiers: UInt32) -> Bool {
        guard isRecording else { return false }

        if keyCode == UInt32(kVK_Escape), carbonModifiers == 0 {
            cancelRecording()
            return true
        }

        let candidate = HotkeyShortcut(keyCode: keyCode, carbonModifiers: carbonModifiers)

        guard candidate.isValid else {
            validationMessage = String(localized: "Use at least one of ⌘, ⌃ or ⌥ together with another key.")
            return true
        }

        isRecording = false
        validationMessage = nil
        apply(candidate)
        return true
    }

    private func apply(_ shortcut: HotkeyShortcut) {
        self.shortcut = shortcut
        onShortcutChanged?(shortcut)
    }
}

@MainActor
protocol SettingsPresenting: AnyObject {
    func present(viewModel: SettingsViewModel)
}
