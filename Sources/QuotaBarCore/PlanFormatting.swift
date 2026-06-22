import Foundation

public enum PlanFormatting {
    public static func claudePlan(subscriptionType: String?, rateLimitTier: String?) -> String? {
        if let tier = rateLimitTier?.lowercased() {
            if tier.contains("max") { return "Max" }
            if tier.contains("pro") { return "Pro" }
            if tier.contains("team") { return "Team" }
            if tier.contains("enterprise") { return "Enterprise" }
            if tier.contains("ultra") { return "Ultra" }
        }
        if let sub = subscriptionType?.lowercased(), !sub.isEmpty {
            return sub.prefix(1).uppercased() + sub.dropFirst()
        }
        return nil
    }

    public static func grokPlan(authMode: String?) -> String? {
        switch authMode?.lowercased() {
        case "oidc": return "SuperGrok"
        case "session": return "Session"
        case let m?: return m
        default: return nil
        }
    }

    public static func codexPlanDisplay(_ plan: String) -> String {
        plan
    }
}