import QuotaBarCore
import SwiftUI
import WidgetKit

struct QuotaBarEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
}

struct MediumWidgetView: View {
    let entry: QuotaBarEntry

    var body: some View {
        MediumQuotaView(snapshot: entry.snapshot)
            .containerBackground(for: .widget) {
                WidgetTheme.background
            }
    }
}

struct QuotaBarProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaBarEntry {
        QuotaBarEntry(date: Date(), snapshot: SnapshotStore.placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuotaBarEntry) -> Void) {
        let snapshot = SnapshotStore.load() ?? SnapshotStore.placeholder
        completion(QuotaBarEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaBarEntry>) -> Void) {
        let snapshot = SnapshotStore.load() ?? SnapshotStore.placeholder
        let entry = QuotaBarEntry(date: Date(), snapshot: snapshot)
        let next = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date().addingTimeInterval(300)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct QuotaBarMediumWidget: Widget {
    let kind = "QuotaBarMedium"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuotaBarProvider()) { entry in
            MediumWidgetView(entry: entry)
        }
        .configurationDisplayName("QuotaBar")
        .description("Codex / Claude / Grok の残量をデスクトップに表示")
        .supportedFamilies([.systemMedium])
    }
}

@main
struct QuotaBarWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuotaBarMediumWidget()
    }
}