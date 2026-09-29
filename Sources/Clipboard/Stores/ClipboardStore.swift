import Foundation

@MainActor
protocol ClipboardStoring: AnyObject {
    var items: [ClipboardItem] { get }
    var isMonitoringEnabled: Bool { get }

    @discardableResult
    func append(_ item: ClipboardItem) -> Bool
    @discardableResult
    func moveToFront(id: ClipboardItem.ID) -> Bool
    func clear()
    func setMonitoringEnabled(_ isEnabled: Bool)
}

final class ClipboardStore: ClipboardStoring {
    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private let historyURL: URL

    private(set) var items: [ClipboardItem]
    private(set) var isMonitoringEnabled: Bool

    init(
        baseDirectory: URL? = nil,
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard
    ) {
        self.fileManager = fileManager
        self.userDefaults = userDefaults

        let rootDirectory = baseDirectory ?? Self.defaultBaseDirectory(fileManager: fileManager)
        self.historyURL = rootDirectory.appendingPathComponent(AppConstants.historyFileName)
        self.items = []
        self.isMonitoringEnabled = userDefaults.object(forKey: AppConstants.monitoringDefaultsKey) as? Bool ?? true

        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        self.items = load()
    }

    @discardableResult
    func load() -> [ClipboardItem] {
        guard fileManager.fileExists(atPath: historyURL.path) else {
            items = []
            return items
        }

        do {
            let data = try Data(contentsOf: historyURL)
            let decodedItems = try JSONDecoder().decode([ClipboardItem].self, from: data)
            let prunedItems = Self.pruned(decodedItems)
            items = prunedItems
            if prunedItems != decodedItems {
                persist()
            }
        } catch {
            items = []
        }

        return items
    }

    @discardableResult
    func append(_ item: ClipboardItem) -> Bool {
        guard !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        items.removeAll { $0.text == item.text }
        items.insert(item, at: 0)
        items = Self.pruned(items)
        persist()
        return true
    }

    @discardableResult
    func moveToFront(id: ClipboardItem.ID) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return false
        }

        guard index != 0 else {
            return true
        }

        let item = items.remove(at: index)
        items.insert(item, at: 0)
        persist()
        return true
    }

    func clear() {
        items = []
        persist()
    }

    func setMonitoringEnabled(_ isEnabled: Bool) {
        isMonitoringEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: AppConstants.monitoringDefaultsKey)
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: historyURL, options: .atomic)
        } catch {
            // Intentionally ignore persistence failures in v1 and keep the in-memory history usable.
        }
    }

    private static func defaultBaseDirectory(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())

        return applicationSupport
            .appendingPathComponent(AppConstants.bundleIdentifier, isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
    }

    private static func pruned(_ items: [ClipboardItem]) -> [ClipboardItem] {
        Array(items.prefix(AppConstants.retentionLimit))
    }
}
