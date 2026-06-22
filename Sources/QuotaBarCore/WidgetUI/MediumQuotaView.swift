import SwiftUI

public struct MediumQuotaView: View {
    public let snapshot: UsageSnapshot

    public init(snapshot: UsageSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        ZStack {
            WidgetTheme.background
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(0.04))
                .padding(10)

            VStack(alignment: .leading, spacing: 10) {
                header
                ForEach(snapshot.providers) { provider in
                    providerRow(provider)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("QuotaBar")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("AI quota monitor")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            Text(WidgetTheme.updatedLabel(snapshot.updatedAt))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    @ViewBuilder
    private func providerRow(_ provider: ProviderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                providerIcon(provider.id)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(provider.label)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        if let plan = provider.plan, !plan.isEmpty {
                            Text("· \(plan)")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }
                    if let err = provider.error {
                        Text(err)
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    } else if let tight = tightestWindow(for: provider) {
                        Text(tight.name)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                Spacer()
                if let rem = provider.minRemaining {
                    Text("\(Int(rem.rounded()))%")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(WidgetTheme.barColor(remaining: rem))
                } else {
                    Text("!")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.gray)
                }
            }

            if provider.error == nil {
                miniChart(for: provider)
            }
        }
        .padding(.vertical, 2)
    }

    private func providerIcon(_ id: String) -> some View {
        ZStack {
            Circle()
                .fill(WidgetTheme.accent(for: id))
                .frame(width: 26, height: 26)
            Image(systemName: WidgetTheme.providerSymbol(id))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(id == "grok" ? .black.opacity(0.75) : .white)
        }
    }

    private func miniChart(for provider: ProviderSnapshot) -> some View {
        VStack(spacing: 4) {
            ForEach(Array(provider.windows.enumerated()), id: \.offset) { _, window in
                HStack(spacing: 6) {
                    Text(window.name)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 52, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.10))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            WidgetTheme.barColor(remaining: window.remainingPercent).opacity(0.95),
                                            WidgetTheme.barColor(remaining: window.remainingPercent).opacity(0.55),
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(4, geo.size.width * window.remainingPercent / 100))
                        }
                    }
                    .frame(height: 6)
                    Text("\(Int(window.remainingPercent.rounded()))")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(WidgetTheme.barColor(remaining: window.remainingPercent))
                        .frame(width: 18, alignment: .trailing)
                }
            }
        }
    }

    private func tightestWindow(for provider: ProviderSnapshot) -> WindowSnapshot? {
        provider.windows.min { $0.remainingPercent < $1.remainingPercent }
    }
}