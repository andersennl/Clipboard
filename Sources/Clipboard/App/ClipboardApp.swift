import SwiftUI

@main
struct ClipboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appModel = ClipboardAppModel()

    var body: some Scene {
        MenuBarExtra {
            Button("Open History  \(appModel.hotkeyShortcut.displayString)") {
                appModel.openClipboardHistory()
            }

            Button(monitoringTitle) {
                appModel.toggleMonitoring()
            }

            if !appModel.hasAccessibilityAccess {
                Button("Grant Accessibility Access") {
                    appModel.openAccessibilitySettings()
                }
            }

            Divider()

            Button("Settings…") {
                appModel.openSettings()
            }

            Divider()

            Button("Clear History") {
                appModel.clearHistory()
            }
            .disabled(appModel.items.isEmpty)

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: "doc.on.clipboard.fill")
        }
        .menuBarExtraStyle(.menu)
    }

    /// Declared as `LocalizedStringKey` so both branches are looked up rather than
    /// resolving to the plain-`String` overload of `Button`.
    private var monitoringTitle: LocalizedStringKey {
        appModel.isMonitoringEnabled ? "Pause Recording" : "Resume Recording"
    }
}
