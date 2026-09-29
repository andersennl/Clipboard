import Foundation

struct ClipboardItem: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let text: String
    let createdAt: Date
    let sourceAppName: String
    let sourceBundleID: String

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = .now,
        sourceAppName: String,
        sourceBundleID: String
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
    }

    /// Persisted verbatim when the originating app could not be determined. Kept untranslated on
    /// disk so an existing history stays readable after the user switches language.
    static let unknownSourceAppName = "Unknown App"

    /// Real app names come from macOS already localized; only the fallback is translated here.
    var displaySourceAppName: String {
        sourceAppName == Self.unknownSourceAppName
            ? String(localized: "Unknown App")
            : sourceAppName
    }
}
