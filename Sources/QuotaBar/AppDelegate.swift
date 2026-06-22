import AppKit
import QuotaBarCore
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var timer: Timer?
    private var latest: [Provider: ProviderUsage] = [:]
    private var lastUpdated: Date?
    private var isFetching = false
    private var notificationsReady = false
    private var forceFallbackNotifier = false
    private let desktopPanel = DesktopPanelController()

    // Config
    private let pollInterval: TimeInterval = 300 // 5 min
    private var alertThreshold: Double {
        let v = UserDefaults.standard.double(forKey: "alertThreshold")
        return v == 0 ? 20 : v
    }

    private var canUseUserNotifications: Bool { Bundle.main.bundleIdentifier != nil }

    func showDesktopPanelForVerification(snapshot: UsageSnapshot) {
        desktopPanel.show(snapshot: snapshot)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "…"
        statusItem.menu = menu
        rebuildMenu()

        if canUseUserNotifications {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
                Task { @MainActor in
                    guard let self else { return }
                    // If UN can't authorize (common for ad-hoc-signed apps), fall back to osascript.
                    if !granted || error != nil { self.forceFallbackNotifier = true }
                    self.notificationsReady = true
                    if !self.latest.isEmpty { self.checkThresholds(self.latest) }
                }
            }
        } else {
            notificationsReady = true // osascript fallback always available
        }

        if UserDefaults.standard.bool(forKey: "sendTestNotificationOnLaunch") {
            UserDefaults.standard.set(false, forKey: "sendTestNotificationOnLaunch")
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                self.sendTestNotification()
            }
        }

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: - Fetch

    private func refresh() {
        guard !isFetching else { return }
        isFetching = true
        Task { @MainActor in
            let result = await fetchAll()
            self.latest = result
            self.lastUpdated = Date()
            let snapshot = UsageSnapshot.from(result)
            SnapshotStore.save(snapshot)
            if UserDefaults.standard.bool(forKey: "showDesktopPanelOnLaunch") {
                self.desktopPanel.show(snapshot: snapshot)
            } else {
                self.desktopPanel.refresh(with: snapshot)
            }
            self.isFetching = false
            self.updateTitle()
            self.rebuildMenu()
            self.checkThresholds(result)
        }
    }

    // MARK: - Menu bar title

    private func updateTitle() {
        let attr = NSMutableAttributedString()
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        for (i, p) in Provider.allCases.enumerated() {
            if i > 0 { attr.append(NSAttributedString(string: "  ")) }
            let usage = latest[p]
            let text: String
            let color: NSColor
            if let usage, usage.error == nil, let rem = usage.minRemaining {
                text = " \(Int(rem.rounded()))%"
                color = colorFor(remaining: rem)
            } else {
                text = " !"
                color = .systemGray
            }
            // Brand icon, tinted to the status color, then the percentage.
            if let icon = providerIcon(p, tint: color) {
                let att = NSTextAttachment()
                att.image = icon
                att.bounds = CGRect(x: 0, y: -2.5, width: 14, height: 14)
                attr.append(NSAttributedString(attachment: att))
            } else {
                attr.append(NSAttributedString(string: p.short, attributes: [
                    .foregroundColor: color, .font: font,
                ]))
            }
            attr.append(NSAttributedString(string: text, attributes: [
                .foregroundColor: color, .font: font,
            ]))
        }
        statusItem.button?.attributedTitle = attr
    }

    private var iconCache: [Provider: NSImage] = [:]

    /// Loads the bundled brand SVG once and returns a copy tinted to `tint`.
    private func providerIcon(_ p: Provider, tint: NSColor) -> NSImage? {
        let base: NSImage
        if let cached = iconCache[p] {
            base = cached
        } else {
            guard let url = Bundle.main.url(forResource: "ProviderIcon-\(p.rawValue)", withExtension: "svg"),
                  let img = NSImage(contentsOf: url) else { return nil }
            iconCache[p] = img
            base = img
        }
        let size = NSSize(width: 14, height: 14)
        let tinted = NSImage(size: size)
        tinted.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        tint.set()
        rect.fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.isTemplate = false
        return tinted
    }

    private func colorFor(remaining: Double) -> NSColor {
        if remaining < alertThreshold { return .systemRed }
        if remaining < 50 { return .systemOrange }
        return .systemGreen
    }

    // MARK: - Menu

    private func rebuildMenu() {
        menu.removeAllItems()

        for p in Provider.allCases {
            let usage = latest[p]
            let header = NSMenuItem(title: providerHeader(p, usage), action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            if let usage {
                if let err = usage.error {
                    let item = NSMenuItem(title: "   ⚠︎ \(err)", action: nil, keyEquivalent: "")
                    item.isEnabled = false
                    menu.addItem(item)
                } else {
                    for w in usage.windows {
                        let item = NSMenuItem(title: "   " + windowLine(w), action: nil, keyEquivalent: "")
                        item.isEnabled = false
                        menu.addItem(item)
                    }
                }
            } else {
                let item = NSMenuItem(title: "   …", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        let updated = NSMenuItem(title: updatedLine(), action: nil, keyEquivalent: "")
        updated.isEnabled = false
        menu.addItem(updated)

        let desktopTitle = desktopPanel.isVisible ? "デスクトップウィジェットを隠す" : "デスクトップウィジェットを表示"
        menu.addItem(withTitle: desktopTitle, action: #selector(toggleDesktopPanel), keyEquivalent: "d").target = self
        menu.addItem(withTitle: "通知をテスト", action: #selector(testNotification), keyEquivalent: "t").target = self
        menu.addItem(withTitle: "今すぐ更新", action: #selector(refreshNow), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "終了", action: #selector(quit), keyEquivalent: "q").target = self
    }

    private func providerHeader(_ p: Provider, _ usage: ProviderUsage?) -> String {
        var s = p.label
        // Append plan only when it adds info (not a redundant copy of the name).
        if let plan = usage?.loginMethod, plan.caseInsensitiveCompare(p.label) != .orderedSame {
            s += " · \(plan)"
        }
        if let email = usage?.accountEmail { s += " · \(email)" }
        return s
    }

    private func windowLine(_ w: RateWindow) -> String {
        let rem = Int(w.remainingPercent.rounded())
        var line = String(format: "%@: 残り %d%%  (使用 %d%%)", w.name, rem, Int(w.usedPercent.rounded()))
        if let reset = w.resetsAt {
            line += "  · " + resetDescription(reset)
        }
        return line
    }

    private func resetDescription(_ date: Date) -> String {
        let secs = date.timeIntervalSinceNow
        if secs <= 0 { return "リセット済" }
        let mins = Int(secs / 60)
        if mins < 60 { return "あと\(mins)分" }
        let hours = mins / 60
        if hours < 24 { return "あと\(hours)時間\(mins % 60)分" }
        let days = hours / 24
        return "あと\(days)日\(hours % 24)時間"
    }

    private func updatedLine() -> String {
        guard let t = lastUpdated else { return "更新: —" }
        let s = Int(Date().timeIntervalSince(t))
        if s < 60 { return "更新: \(s)秒前" }
        return "更新: \(s / 60)分前"
    }

    @objc private func refreshNow() { refresh() }
    @objc private func testNotification() { sendTestNotification() }
    @objc private func toggleDesktopPanel() {
        desktopPanel.toggle(with: UsageSnapshot.from(latest))
        rebuildMenu()
    }
    @objc private func quit() { NSApplication.shared.terminate(nil) }

    // MARK: - Threshold notifications

    private func checkThresholds(_ result: [Provider: ProviderUsage]) {
        // Don't mark keys as notified until we can actually deliver, or we'd
        // silently swallow the first alert and never retry for that window.
        guard notificationsReady else { return }
        let defaults = UserDefaults.standard

        var notified = Set(defaults.stringArray(forKey: "notifiedKeys") ?? [])

        // One-time migration: old keys embedded volatile reset timestamps.
        if !defaults.bool(forKey: "notifiedKeysV2") {
            notified.removeAll()
            for p in Provider.allCases {
                guard let usage = result[p], usage.error == nil else { continue }
                for w in usage.windows where w.remainingPercent < alertThreshold {
                    notified.insert(w.notifyKey(provider: p))
                }
            }
            defaults.set(true, forKey: "notifiedKeysV2")
        }

        // Clear only when a window recovers above threshold (new depletion episode may alert again).
        for p in Provider.allCases {
            guard let usage = result[p], usage.error == nil else { continue }
            for w in usage.windows where w.remainingPercent >= alertThreshold {
                notified.remove(w.notifyKey(provider: p))
            }
        }

        for p in Provider.allCases {
            guard let usage = result[p], usage.error == nil else { continue }
            for w in usage.windows where w.remainingPercent < alertThreshold {
                let key = w.notifyKey(provider: p)
                guard !notified.contains(key) else { continue }
                notified.insert(key)
                postNotification(
                    title: "\(p.label) 残り \(Int(w.remainingPercent.rounded()))%",
                    body: "\(w.name) 枠がしきい値(\(Int(alertThreshold))%)を下回りました。"
                        + (w.resetsAt.map { " \(resetDescription($0))にリセット。" } ?? "")
                )
            }
        }

        defaults.set(Array(notified), forKey: "notifiedKeys")
    }

    func sendTestNotification() {
        postNotification(
            title: "QuotaBar 通知テスト",
            body: "残量がしきい値（\(Int(alertThreshold))%）を下回るとお知らせします。"
        )
    }

    // Menu bar apps stay foreground; without this delegate macOS swallows banners.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private func postNotification(title: String, body: String) {
        if canUseUserNotifications, !forceFallbackNotifier {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(req) { [weak self] error in
                guard error != nil else { return }
                Task { @MainActor in self?.postNotificationViaOsascript(title: title, body: body) }
            }
        } else {
            postNotificationViaOsascript(title: title, body: body)
        }
    }

    private func postNotificationViaOsascript(title: String, body: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        let esc = { (s: String) in s.replacingOccurrences(of: "\"", with: "'") }
        p.arguments = ["-e", "display notification \"\(esc(body))\" with title \"\(esc(title))\""]
        try? p.run()
    }
}
