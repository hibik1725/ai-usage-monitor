import Foundation

public enum AppGroup {
    public static let identifier = "group.com.hivvv.quotabar"
    public static let snapshotFileName = "usage-snapshot.json"

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    public static var snapshotURL: URL? {
        containerURL?.appendingPathComponent(snapshotFileName)
    }

    /// Ensures the group container exists (helps ad-hoc / unsigned local installs).
    public static func ensureContainer() {
        guard let url = containerURL else { return }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}