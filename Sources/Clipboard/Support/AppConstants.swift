import Carbon
import Foundation

enum AppConstants {
    // The Swift module and bundle identifier stay "Clipboard" for source and Store identity.
    // The shipped target, executable and app bundle use the user-facing product name.
    static let appName = "Paste Again"
    static let bundleIdentifier = "com.nandersen.Clipboard"
    static let minimumSystemVersion = "14.0"
    static let retentionLimit = 1000
    static let historyFileName = "history.json"
    static let monitoringDefaultsKey = "clipboard.monitoringEnabled"
    static let hotkeyShortcutDefaultsKey = "clipboard.hotkeyShortcut"
    static let historyPanelWidth: CGFloat = 940
    static let historyPanelHeight: CGFloat = 560
    static let settingsWindowWidth: CGFloat = 460
    // Sized for the longest translation. German needs 512pt; below that the About section
    // scrolls the privacy policy link out of view, which App Review expects to be reachable.
    static let settingsWindowHeight: CGFloat = 520
    static let defaultHotKeyCode = UInt32(kVK_ANSI_V)
    static let defaultHotKeyModifiers = UInt32(cmdKey | shiftKey)
    static let hotKeyIdentifier = UInt32(1)
    static let hotKeySignature = fourCharCode("CLIP")
    static let websiteURLString = "https://andersennl.github.io"
    // App Review guideline 5.1.1(i) requires the policy to be reachable from inside the app,
    // not only from the App Store listing.
    static let privacyPolicyURLString = "https://andersennl.github.io/paste-again/privacy/"
}

private func fourCharCode(_ value: String) -> FourCharCode {
    value.utf8.reduce(0) { partialResult, byte in
        (partialResult << 8) + FourCharCode(byte)
    }
}
