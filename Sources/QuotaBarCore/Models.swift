import Foundation

/// The three subscriptions we track.
public enum Provider: String, CaseIterable, Sendable {
    case codex
    case claude
    case grok

    public var label: String {
        switch self {
        case .codex: return "codex"
        case .claude: return "claude"
        case .grok: return "grok"
        }
    }

    /// Two-letter tag shown in the menu bar.
    public var short: String {
        switch self {
        case .codex: return "Cx"
        case .claude: return "Cl"
        case .grok: return "Gk"
        }
    }
}

/// One rate-limit window (e.g. Codex 5h, Claude weekly, Grok monthly quota).
public struct RateWindow: Sendable {
    public var name: String
    public var usedPercent: Double
    public var windowMinutes: Int?
    public var resetsAt: Date?

    public init(name: String, usedPercent: Double, windowMinutes: Int?, resetsAt: Date?) {
        self.name = name
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Double { max(0, 100 - usedPercent) }

    /// Stable key for notification de-duplication (provider + window name only).
    /// Do not include `resetsAt` — API timestamps can drift between polls and would re-fire alerts.
    public func notifyKey(provider: Provider) -> String {
        "\(provider.rawValue).\(name)"
    }
}

/// A provider's full snapshot for one poll.
public struct ProviderUsage: Sendable {
    public var provider: Provider
    public var accountEmail: String?
    public var loginMethod: String?
    public var windows: [RateWindow]
    public var error: String?
    public var updatedAt: Date

    public init(
        provider: Provider,
        accountEmail: String? = nil,
        loginMethod: String? = nil,
        windows: [RateWindow] = [],
        error: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.provider = provider
        self.accountEmail = accountEmail
        self.loginMethod = loginMethod
        self.windows = windows
        self.error = error
        self.updatedAt = updatedAt
    }

    /// Tightest remaining headroom across all windows — what we surface at a glance and alert on.
    public var minRemaining: Double? { windows.map(\.remainingPercent).min() }

    /// The window that is closest to its limit.
    public var tightestWindow: RateWindow? {
        windows.min { $0.remainingPercent < $1.remainingPercent }
    }
}