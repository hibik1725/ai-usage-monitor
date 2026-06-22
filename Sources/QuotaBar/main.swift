import AppKit
import QuotaBarCore

// `--show-desktop`: fetch, open floating desktop panel (verification / dev).
if CommandLine.arguments.contains("--show-desktop") {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            let all = await fetchAll()
            let snapshot = UsageSnapshot.from(all)
            SnapshotStore.save(snapshot)
            delegate.showDesktopPanelForVerification(snapshot: snapshot)
        }
        app.run()
    }
} else if CommandLine.arguments.contains("--probe") {
    let sem = DispatchSemaphore(value: 0)
    Task {
        let all = await fetchAll()
        SnapshotStore.save(UsageSnapshot.from(all))
        for p in Provider.allCases {
            guard let u = all[p] else { continue }
            if let e = u.error {
                print("\(p.label): ERROR \(e)")
            } else {
                let plan = u.loginMethod.map { " [\($0)]" } ?? ""
                print("\(p.label)\(plan):")
                for w in u.windows {
                    let reset = w.resetsAt.map { " resets \(ISO8601DateFormatter().string(from: $0))" } ?? ""
                    print(String(format: "  %@: used %.1f%% / left %.1f%%%@",
                                 w.name, w.usedPercent, w.remainingPercent, reset))
                }
            }
        }
        sem.signal()
    }
    sem.wait()
    exit(0)
}

// Top-level entry runs on the main thread; assert main-actor isolation so we can
// touch the @MainActor AppDelegate / AppKit directly.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // menu-bar only, no Dock icon
    app.run()
}
