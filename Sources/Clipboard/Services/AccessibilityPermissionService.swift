import AppKit
import CoreGraphics
import Foundation

@MainActor
protocol AccessibilityPermissionProviding: AnyObject {
    func isTrusted(prompt: Bool) -> Bool
    func openSystemSettings()
}

extension AccessibilityPermissionProviding {
    func isTrusted() -> Bool {
        isTrusted(prompt: false)
    }
}

// The app only needs one accessibility capability: posting the synthetic `Cmd+V` for paste-back.
// `CGPreflightPostEventAccess`/`CGRequestPostEventAccess` ask exactly for that, while
// `AXIsProcessTrustedWithOptions` covers the whole accessibility API surface. Both map to the
// same System Settings pane, so the user-facing wording stays "Accessibility".
@MainActor
final class AccessibilityPermissionService: AccessibilityPermissionProviding {
    func isTrusted(prompt: Bool = false) -> Bool {
        guard prompt else { return CGPreflightPostEventAccess() }

        // Returns the current state right away and shows the system prompt only while the
        // decision is still pending, so it is safe to call on every paste attempt.
        return CGRequestPostEventAccess()
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
