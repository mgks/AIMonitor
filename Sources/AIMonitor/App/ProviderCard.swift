import SwiftUI

/// One provider's card inside the menu popover.
struct ProviderCard: View {
    let provider: any AIProvider
    let status: ProviderStatus?
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if let snapshot = status?.snapshot {
                progressBar(snapshot: snapshot)
                details(snapshot: snapshot)
            }

            if let error, status?.state != .healthy && status?.state != .warning {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var displayName: String { status?.displayName ?? provider.displayName }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: provider.symbolName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(displayName)
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if let model = status?.model {
                Text(model)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func progressBar(snapshot: QuotaSnapshot) -> some View {
        HStack(spacing: 6) {
            if let pct = snapshot.remainingPercent {
                ProgressView(value: pct, total: 100)
                    .progressViewStyle(.linear)
                    .tint(tint(for: pct))
                Text(Formatting.percent(pct) ?? "")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
            } else {
                Text(stateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private func details(snapshot: QuotaSnapshot) -> some View {
        let parts = detailLines(snapshot: snapshot)
        return VStack(alignment: .leading, spacing: 1) {
            ForEach(parts, id: \.self) { line in
                Text(line)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Build the small grey lines under the bar: window reset countdowns,
    /// last updated.
    private func detailLines(snapshot: QuotaSnapshot) -> [String] {
        var lines: [String] = []

        // 5h / interval window reset.
        if let reset = Formatting.countdown(to: snapshot.resetsAt) {
            lines.append("5h resets in \(reset)")
        }

        // Weekly window reset (if present).
        if let weekly = Formatting.countdown(to: snapshot.weeklyResetsAt) {
            lines.append("Weekly resets in \(weekly)")
        }

        // Fall back to window label if no reset times.
        if lines.isEmpty, let window = snapshot.windowLabel {
            lines.append(window)
        }

        if let last = status?.lastUpdated {
            lines.append("Updated " + Formatting.relativeShort(from: last))
        }
        return lines
    }

    private var stateLabel: String {
        switch status?.state {
        case .healthy: return "Healthy"
        case .warning: return "Limited"
        case .critical: return "Low"
        case .exhausted: return "Exhausted"
        case .error: return "Error"
        case .unknown, .none: return "Checking\u{2026}"
        }
    }

    private func tint(for pct: Double) -> Color {
        QuotaThresholds.state(forPercent: pct) == .healthy ? .green
            : QuotaThresholds.state(forPercent: pct) == .warning ? .yellow : .red
    }
}
