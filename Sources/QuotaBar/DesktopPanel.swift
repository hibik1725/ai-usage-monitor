import AppKit
import QuotaBarCore
import SwiftUI

@MainActor
final class DesktopPanelController {
    private var panel: NSPanel?
    private var hosting: NSHostingView<MediumQuotaView>?

    var isVisible: Bool { panel?.isVisible == true }

    func toggle(with snapshot: UsageSnapshot?) {
        if isVisible {
            hide()
        } else {
            show(snapshot: snapshot ?? SnapshotStore.load() ?? SnapshotStore.placeholder)
        }
    }

    func refresh(with snapshot: UsageSnapshot) {
        guard isVisible else { return }
        hosting?.rootView = MediumQuotaView(snapshot: snapshot)
    }

    func show(snapshot: UsageSnapshot) {
        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 120, y: 120, width: 360, height: 320),
                styleMask: [.nonactivatingPanel, .fullSizeContentView, .hudWindow],
                backing: .buffered,
                defer: false
            )
            p.isFloatingPanel = true
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            p.titleVisibility = .hidden
            p.titlebarAppearsTransparent = true
            p.isMovableByWindowBackground = true
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = true
            p.hidesOnDeactivate = false
            panel = p
        }
        guard let panel else { return }
        let view = MediumQuotaView(snapshot: snapshot)
        if hosting == nil {
            hosting = NSHostingView(rootView: view)
            hosting?.frame = panel.contentView?.bounds ?? .zero
            hosting?.autoresizingMask = [.width, .height]
            panel.contentView = hosting
        } else {
            hosting?.rootView = view
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }
}