import Foundation

public struct WindowSnapshot: Codable, Sendable {
    public var name: String
    public var usedPercent: Double
    public var remainingPercent: Double
    public var resetsAt: Date?

    public init(name: String, usedPercent: Double, remainingPercent: Double, resetsAt: Date?) {
        self.name = name
        self.usedPercent = usedPercent
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
    }
}

public struct ProviderSnapshot: Codable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var plan: String?
    public var error: String?
    public var windows: [WindowSnapshot]
    public var minRemaining: Double?

    public init(
        id: String,
        label: String,
        plan: String?,
        error: String?,
        windows: [WindowSnapshot],
        minRemaining: Double?
    ) {
        self.id = id
        self.label = label
        self.plan = plan
        self.error = error
        self.windows = windows
        self.minRemaining = minRemaining
    }
}

public struct UsageSnapshot: Codable, Sendable {
    public var updatedAt: Date
    public var providers: [ProviderSnapshot]

    public init(updatedAt: Date, providers: [ProviderSnapshot]) {
        self.updatedAt = updatedAt
        self.providers = providers
    }

    public static func from(_ map: [Provider: ProviderUsage]) -> UsageSnapshot {
        let providers = Provider.allCases.compactMap { p -> ProviderSnapshot? in
            guard let u = map[p] else { return nil }
            return ProviderSnapshot(
                id: p.rawValue,
                label: p.label,
                plan: u.loginMethod,
                error: u.error,
                windows: u.windows.map {
                    WindowSnapshot(
                        name: $0.name,
                        usedPercent: $0.usedPercent,
                        remainingPercent: $0.remainingPercent,
                        resetsAt: $0.resetsAt
                    )
                },
                minRemaining: u.minRemaining
            )
        }
        return UsageSnapshot(updatedAt: Date(), providers: providers)
    }
}

public enum SnapshotStore {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static func save(_ snapshot: UsageSnapshot) {
        AppGroup.ensureContainer()
        guard let url = AppGroup.snapshotURL else { return }
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public static func load() -> UsageSnapshot? {
        guard let url = AppGroup.snapshotURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }

    public static var placeholder: UsageSnapshot {
        UsageSnapshot(
            updatedAt: Date(),
            providers: [
                ProviderSnapshot(
                    id: "codex", label: "codex", plan: "prolite", error: nil,
                    windows: [
                        WindowSnapshot(name: "Weekly", usedPercent: 72, remainingPercent: 28, resetsAt: nil),
                        WindowSnapshot(name: "5h", usedPercent: 10, remainingPercent: 90, resetsAt: nil),
                    ],
                    minRemaining: 28
                ),
                ProviderSnapshot(
                    id: "claude", label: "claude", plan: "Max", error: nil,
                    windows: [WindowSnapshot(name: "Weekly", usedPercent: 31, remainingPercent: 69, resetsAt: nil)],
                    minRemaining: 69
                ),
                ProviderSnapshot(
                    id: "grok", label: "grok", plan: "SuperGrok", error: nil,
                    windows: [WindowSnapshot(name: "Quota", usedPercent: 34, remainingPercent: 66, resetsAt: nil)],
                    minRemaining: 66
                ),
            ]
        )
    }
}