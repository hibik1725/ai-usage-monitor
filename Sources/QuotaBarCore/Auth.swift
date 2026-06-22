import Foundation

public enum AuthError: LocalizedError {
    case notFound(String)
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case let .notFound(msg): return msg
        case let .malformed(msg): return msg
        }
    }
}

private let home = FileManager.default.homeDirectoryForCurrentUser

// MARK: - Codex

public struct CodexToken: Sendable {
    public let accessToken: String
    public let accountId: String?
}

/// Reads `~/.codex/auth.json` → `tokens.access_token` / `tokens.account_id`.
public func loadCodexToken() throws -> CodexToken {
    let url = home.appendingPathComponent(".codex/auth.json")
    guard let data = try? Data(contentsOf: url) else {
        throw AuthError.notFound("~/.codex/auth.json が見つかりません。`codex` でログインしてください。")
    }
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tokens = root["tokens"] as? [String: Any],
          let access = tokens["access_token"] as? String, !access.isEmpty
    else {
        throw AuthError.malformed("Codex auth.json を解析できません。")
    }
    return CodexToken(accessToken: access, accountId: tokens["account_id"] as? String)
}

// MARK: - Claude

public struct ClaudeCredentials: Sendable {
    public let accessToken: String
    public let subscriptionType: String?
    public let rateLimitTier: String?
}

/// Reads the Claude Code OAuth access token. Prefers the credentials file, falls
/// back to the macOS keychain item `Claude Code-credentials` via /usr/bin/security.
public func loadClaudeCredentials() throws -> ClaudeCredentials {
    let fileURL = home.appendingPathComponent(".claude/.credentials.json")
    if let data = try? Data(contentsOf: fileURL),
       let creds = claudeCredentials(fromCredentialsJSON: data)
    {
        return creds
    }
    if let raw = securityFindGenericPassword(service: "Claude Code-credentials"),
       let creds = claudeCredentials(fromCredentialsJSON: Data(raw.utf8))
    {
        return creds
    }
    throw AuthError.notFound("Claude の認証情報が見つかりません。`claude` でログインしてください。")
}

public func loadClaudeToken() throws -> String {
    try loadClaudeCredentials().accessToken
}

private func claudeCredentials(fromCredentialsJSON data: Data) -> ClaudeCredentials? {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let oauth = root["claudeAiOauth"] as? [String: Any],
          let token = oauth["accessToken"] as? String, !token.isEmpty
    else { return nil }
    return ClaudeCredentials(
        accessToken: token,
        subscriptionType: oauth["subscriptionType"] as? String,
        rateLimitTier: oauth["rateLimitTier"] as? String
    )
}

/// `security find-generic-password -s <service> -w` — returns the password (the
/// stored JSON blob) or nil. Runs with a short timeout so a keychain prompt can't hang us.
private func securityFindGenericPassword(service: String) -> String? {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    proc.arguments = ["find-generic-password", "-s", service, "-w"]
    let out = Pipe()
    proc.standardOutput = out
    proc.standardError = Pipe()
    do { try proc.run() } catch { return nil }
    proc.waitUntilExit()
    guard proc.terminationStatus == 0 else { return nil }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    return (s?.isEmpty == false) ? s : nil
}

// MARK: - Grok

public struct GrokToken: Sendable {
    public let accessToken: String
    public let isExpired: Bool
    public let authMode: String?
    public let email: String?
}

/// Reads `~/.grok/auth.json`. Entries are keyed by scope URL; we prefer the OIDC
/// scope (`https://auth.x.ai::…`, SuperGrok), then any entry with a non-empty key.
public func loadGrokToken() throws -> GrokToken {
    let url = home.appendingPathComponent(".grok/auth.json")
    guard let data = try? Data(contentsOf: url),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        throw AuthError.notFound("~/.grok/auth.json が見つかりません。`grok login` してください。")
    }

    func entryKey(_ v: Any?) -> String? {
        guard let dict = v as? [String: Any],
              let key = dict["key"] as? String, !key.isEmpty else { return nil }
        return key
    }
    func expiresAt(_ v: Any?) -> Date? {
        guard let dict = v as? [String: Any] else { return nil }
        if let s = dict["expires_at"] as? String { return parseISO8601(s) }
        if let n = dict["expires_at"] as? Double { return Date(timeIntervalSince1970: n) }
        return nil
    }

    let oidc = root.first { scope, _ in scope.hasPrefix("https://auth.x.ai::") }
    let chosen = (oidc?.value).flatMap { entryKey($0) != nil ? oidc : nil }
        ?? root.first { entryKey($0.value) != nil }

    guard let entry = chosen,
          let value = entry.value as? [String: Any],
          let key = entryKey(value)
    else {
        throw AuthError.malformed("Grok auth.json に有効なトークンがありません。`grok login` してください。")
    }
    let expired = expiresAt(value).map { $0 <= Date() } ?? false
    return GrokToken(
        accessToken: key,
        isExpired: expired,
        authMode: value["auth_mode"] as? String,
        email: value["email"] as? String
    )
}

// MARK: - Shared

/// ISO-8601 with or without fractional seconds.
public func parseISO8601(_ s: String) -> Date? {
    let f1 = ISO8601DateFormatter()
    f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f1.date(from: s) { return d }
    let f2 = ISO8601DateFormatter()
    f2.formatOptions = [.withInternetDateTime]
    return f2.date(from: s)
}