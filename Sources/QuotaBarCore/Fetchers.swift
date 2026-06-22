import Foundation

private let session: URLSession = {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.timeoutIntervalForRequest = 30
    cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: cfg)
}()

/// Human label for a window given its length in minutes.
private func windowName(minutes: Int?) -> String {
    guard let m = minutes else { return "Quota" }
    switch m {
    case 300: return "5h"
    case 10080: return "Weekly"
    default:
        if m % 1440 == 0 { return "\(m / 1440)d" }
        if m % 60 == 0 { return "\(m / 60)h" }
        return "\(m)m"
    }
}

// MARK: - Codex  (GET https://chatgpt.com/backend-api/wham/usage)

public func fetchCodex() async -> ProviderUsage {
    var u = ProviderUsage(provider: .codex)
    do {
        let tok = try loadCodexToken()
        var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(tok.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("CodexBar", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let acc = tok.accountId, !acc.isEmpty {
            req.setValue(acc, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code != 401, code != 403 else {
            u.error = "認証切れ。`codex` で再ログインしてください。"; return u
        }
        guard (200...299).contains(code) else {
            u.error = "Codex API エラー \(code)"; return u
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            u.error = "Codex 応答を解析できません"; return u
        }

        func window(_ dict: [String: Any]?, fallbackName: String? = nil) -> RateWindow? {
            guard let d = dict, let used = (d["used_percent"] as? NSNumber)?.doubleValue else { return nil }
            let secs = (d["limit_window_seconds"] as? NSNumber)?.intValue
            let minutes = secs.map { $0 / 60 }
            let reset = (d["reset_at"] as? NSNumber)?.doubleValue
            return RateWindow(name: fallbackName ?? windowName(minutes: minutes),
                              usedPercent: used,
                              windowMinutes: minutes,
                              resetsAt: reset.map { Date(timeIntervalSince1970: $0) })
        }

        if let rl = root["rate_limit"] as? [String: Any] {
            if let w = window(rl["primary_window"] as? [String: Any]) { u.windows.append(w) }
            if let w = window(rl["secondary_window"] as? [String: Any]) { u.windows.append(w) }
        }
        if let extras = root["additional_rate_limits"] as? [[String: Any]] {
            for extra in extras {
                let name = (extra["limit_name"] as? String) ?? "extra"
                if let rl = extra["rate_limit"] as? [String: Any],
                   let w = window(rl["primary_window"] as? [String: Any], fallbackName: name)
                {
                    u.windows.append(w)
                }
            }
        }
        if let plan = root["plan_type"] as? String {
            u.loginMethod = PlanFormatting.codexPlanDisplay(plan)
        }
        if u.windows.isEmpty { u.error = "レート制限枠が返ってきませんでした" }
    } catch {
        u.error = error.localizedDescription
    }
    return u
}

// MARK: - Claude  (GET https://api.anthropic.com/api/oauth/usage)

public func fetchClaude() async -> ProviderUsage {
    var u = ProviderUsage(provider: .claude)
    do {
        let creds = try loadClaudeCredentials()
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("claude-code/2.1.0", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code != 401, code != 403 else {
            u.error = "認証切れ。`claude` で再ログインしてください。"; return u
        }
        guard (200...299).contains(code) else {
            u.error = "Claude API エラー \(code)"; return u
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            u.error = "Claude 応答を解析できません"; return u
        }

        func window(_ key: String, name: String, minutes: Int) -> RateWindow? {
            guard let d = root[key] as? [String: Any],
                  let util = (d["utilization"] as? NSNumber)?.doubleValue else { return nil }
            let reset = (d["resets_at"] as? String).flatMap(parseISO8601)
            return RateWindow(name: name, usedPercent: util, windowMinutes: minutes, resetsAt: reset)
        }

        if let w = window("five_hour", name: "5h", minutes: 300) { u.windows.append(w) }
        if let w = window("seven_day", name: "Weekly", minutes: 10080) { u.windows.append(w) }
        if let w = window("seven_day_opus", name: "Opus(週)", minutes: 10080) { u.windows.append(w) }
        else if let w = window("seven_day_sonnet", name: "Sonnet(週)", minutes: 10080) { u.windows.append(w) }
        u.loginMethod = PlanFormatting.claudePlan(
            subscriptionType: creds.subscriptionType,
            rateLimitTier: creds.rateLimitTier
        )
        if u.windows.isEmpty { u.error = "レート制限枠が返ってきませんでした" }
    } catch {
        u.error = error.localizedDescription
    }
    return u
}

// MARK: - Grok  (POST grok.com gRPC-Web GetGrokCreditsConfig)

public func fetchGrok() async -> ProviderUsage {
    var u = ProviderUsage(provider: .grok)
    do {
        let tok = try loadGrokToken()
        guard !tok.isExpired else {
            u.error = "Grok トークン期限切れ。`grok login` してください。"; return u
        }
        var req = URLRequest(url: URL(string: "https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.httpBody = Data([0x00, 0x00, 0x00, 0x00, 0x00])
        req.setValue("Bearer \(tok.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("https://grok.com", forHTTPHeaderField: "Origin")
        req.setValue("https://grok.com/?_s=usage", forHTTPHeaderField: "Referer")
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        req.setValue("application/grpc-web+proto", forHTTPHeaderField: "Content-Type")
        req.setValue("1", forHTTPHeaderField: "x-grpc-web")
        req.setValue("connect-es/2.1.1", forHTTPHeaderField: "x-user-agent")
        req.setValue("CodexBar", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code != 401, code != 403 else {
            u.error = "認証切れ。`grok login` してください。"; return u
        }
        guard code == 200 else {
            u.error = "Grok リクエスト失敗 HTTP \(code)"; return u
        }
        let trailers = GrokProtobuf.trailerFields(from: data)
        if let s = trailers["grpc-status"], let n = Int(s), n != 0 {
            u.error = "Grok RPC エラー status \(n)"; return u
        }
        guard let billing = GrokProtobuf.parse(data), let used = billing.usedPercent else {
            u.error = "Grok の利用量を解析できません"; return u
        }
        u.windows.append(RateWindow(name: "Quota", usedPercent: used,
                                    windowMinutes: nil, resetsAt: billing.resetsAt))
        u.loginMethod = PlanFormatting.grokPlan(authMode: tok.authMode)
        u.accountEmail = tok.email
        if u.windows.isEmpty { u.error = "レート制限枠が返ってきませんでした" }
    } catch {
        u.error = error.localizedDescription
    }
    return u
}

/// Fetch all three concurrently.
public func fetchAll() async -> [Provider: ProviderUsage] {
    async let c = fetchCodex()
    async let cl = fetchClaude()
    async let g = fetchGrok()
    let results = await [c, cl, g]
    var map: [Provider: ProviderUsage] = [:]
    for r in results { map[r.provider] = r }
    return map
}