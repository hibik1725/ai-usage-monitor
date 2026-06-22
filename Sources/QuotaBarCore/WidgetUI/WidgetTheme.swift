import SwiftUI

public enum WidgetTheme {
    public static let background = LinearGradient(
        colors: [
            Color(red: 0.08, green: 0.10, blue: 0.22),
            Color(red: 0.14, green: 0.08, blue: 0.28),
            Color(red: 0.06, green: 0.14, blue: 0.20),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static func accent(for providerId: String) -> LinearGradient {
        switch providerId {
        case "codex":
            return LinearGradient(
                colors: [Color(red: 0.16, green: 0.78, blue: 0.55), Color(red: 0.05, green: 0.55, blue: 0.42)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case "claude":
            return LinearGradient(
                colors: [Color(red: 0.98, green: 0.58, blue: 0.36), Color(red: 0.86, green: 0.34, blue: 0.24)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case "grok":
            return LinearGradient(
                colors: [Color(red: 0.92, green: 0.92, blue: 0.96), Color(red: 0.55, green: 0.58, blue: 0.66)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            return LinearGradient(colors: [.gray, .gray.opacity(0.6)], startPoint: .leading, endPoint: .trailing)
        }
    }

    public static func barColor(remaining: Double, threshold: Double = 20) -> Color {
        if remaining < threshold { return Color(red: 1.0, green: 0.32, blue: 0.34) }
        if remaining < 50 { return Color(red: 1.0, green: 0.62, blue: 0.18) }
        return Color(red: 0.28, green: 0.86, blue: 0.56)
    }

    public static func providerSymbol(_ id: String) -> String {
        switch id {
        case "codex": return "terminal.fill"
        case "claude": return "sparkles"
        case "grok": return "bolt.fill"
        default: return "gauge.with.dots.needle.67percent"
        }
    }

    public static func updatedLabel(_ date: Date) -> String {
        let secs = Int(Date().timeIntervalSince(date))
        if secs < 60 { return "\(secs)秒前" }
        if secs < 3600 { return "\(secs / 60)分前" }
        return "\(secs / 3600)時間前"
    }
}