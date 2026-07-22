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
                windowsRow(snapshot: snapshot)
                detailLines(snapshot: snapshot)
            }

            if let error, status?.state != .healthy && status?.state != .warning {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.orange)
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

    /// Two-window row with pipe separator: 5h 81% | W 67%
    /// Falls back to a single progress bar for credit-based providers.
    private func windowsRow(snapshot: QuotaSnapshot) -> some View {
        // Credit-only providers: show balance as the headline.
        if snapshot.remainingPercent == nil {
            return AnyView(
                HStack(spacing: 6) {
                    if let credits = Formatting.credits(snapshot.creditsRemaining,
                                                        currency: snapshot.currency ?? "USD") {
                        Text(credits)
                            .font(.system(size: 13, weight: .medium))
                    } else {
                        Text(stateLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            )
        }

        let fiveHourPct = snapshot.remainingPercent
        let weeklyPct = snapshot.weeklyRemainingPercent

        return AnyView(
            HStack(spacing: 8) {
                // 5-hour window - bar fills available width
                if let pct = fiveHourPct {
                    windowSegment(label: "5h", pct: pct)
                }
                // Weekly window
                if let wpct = weeklyPct {
                    Text("|")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    windowSegment(label: "W", pct: wpct)
                }
                Spacer(minLength: 0)
            }
        )
    }

    /// One labelled window: "5h [bar] 81%"
    /// Bar expands to fill available space.
    private func windowSegment(label: String, pct: Double) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            ProgressView(value: pct, total: 100)
                .progressViewStyle(.linear)
                .tint(tint(for: pct))
            Text(Formatting.percent(pct) ?? "")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)
        }
    }

    private func detailLines(snapshot: QuotaSnapshot) -> some View {
        let parts = detailText(snapshot: snapshot)
        return VStack(alignment: .leading, spacing: 1) {
            ForEach(parts, id: \.self) { line in
                Text(line)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Compact reset info: "5h in 3h 18m | W in 4d 5h" or credits.
    /// Last-updated moved to header; weekly data replaces it here.
    private func detailText(snapshot: QuotaSnapshot) -> [String] {
        var lines: [String] = []

        // Combine reset countdowns into one line with pipe separator.
        // Wording: "Resets in 3h 15m | Weekly reset in 3d 2h"
        var resets: [String] = []
        if let reset = Formatting.countdown(to: snapshot.resetsAt) {
            resets.append("Resets in \(reset)")
        }
        if let weekly = Formatting.countdown(to: snapshot.weeklyResetsAt) {
            resets.append("Weekly reset in \(weekly)")
        }
        if !resets.isEmpty {
            lines.append(resets.joined(separator: " | "))
        }

        // Credits for balance providers.
        if let credits = Formatting.credits(snapshot.creditsRemaining,
                                            currency: snapshot.currency ?? "USD") {
            lines.append(credits)
        }

        // Fall back to window label if nothing else.
        if lines.isEmpty, let window = snapshot.windowLabel {
            lines.append(window)
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
