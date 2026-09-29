import Foundation

@MainActor
protocol HotkeyPreferenceStoring: AnyObject {
    var shortcut: HotkeyShortcut { get }

    func setShortcut(_ shortcut: HotkeyShortcut)
}

final class HotkeyPreferenceStore: HotkeyPreferenceStoring {
    private let userDefaults: UserDefaults

    private(set) var shortcut: HotkeyShortcut

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.shortcut = Self.loadShortcut(from: userDefaults) ?? .default
    }

    func setShortcut(_ shortcut: HotkeyShortcut) {
        guard shortcut.isValid else { return }

        self.shortcut = shortcut

        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        userDefaults.set(data, forKey: AppConstants.hotkeyShortcutDefaultsKey)
    }

    private static func loadShortcut(from userDefaults: UserDefaults) -> HotkeyShortcut? {
        guard
            let data = userDefaults.data(forKey: AppConstants.hotkeyShortcutDefaultsKey),
            let shortcut = try? JSONDecoder().decode(HotkeyShortcut.self, from: data),
            shortcut.isValid
        else {
            return nil
        }

        return shortcut
    }
}
