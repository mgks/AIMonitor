import SwiftUI
import AppKit

/// Renders the monitor logo as a template NSImage, the only reliable way to
/// show a custom shape in a MenuBarExtra label. Template images adapt their
/// colour to the menu bar (light/dark) automatically.
enum MonitorMenuBarIcon {
    static let image: NSImage = {
        // Apple menu bar icons target ~18pt visually. Render at 2x for retina.
        let renderSize: CGFloat = 40
        let displaySize: CGFloat = 20
        let img = NSImage(size: NSSize(width: renderSize, height: renderSize))
        img.lockFocus()

        let s = renderSize
        let lw = s * 0.064    // a few micro pixels thicker for visibility

        // Rounded rect outline. Fill ~73% of frame like native icons.
        let inset = s * 0.135
        let rect = NSRect(x: inset, y: inset,
                          width: s - 2 * inset, height: s - 2 * inset)
        let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.12, yRadius: s * 0.12)
        path.lineWidth = lw
        path.lineJoinStyle = .round
        path.stroke()

        // Graph bump inside the frame.
        let bump = NSBezierPath()
        let baseY = s * 0.56
        let peakY = s * 0.38
        bump.move(to: NSPoint(x: s * 0.31, y: baseY))
        bump.line(to: NSPoint(x: s * 0.38, y: baseY))
        bump.curve(to: NSPoint(x: s * 0.5, y: peakY),
                   controlPoint1: NSPoint(x: s * 0.43, y: baseY),
                   controlPoint2: NSPoint(x: s * 0.43, y: baseY))
        bump.curve(to: NSPoint(x: s * 0.62, y: baseY),
                   controlPoint1: NSPoint(x: s * 0.57, y: peakY),
                   controlPoint2: NSPoint(x: s * 0.57, y: peakY))
        bump.line(to: NSPoint(x: s * 0.69, y: baseY))
        bump.lineWidth = lw
        bump.lineCapStyle = .round
        bump.stroke()

        img.unlockFocus()
        img.isTemplate = true    // adaptive colour for light/dark menu bar
        img.size = NSSize(width: displaySize, height: displaySize)
        return img
    }()
}

/// The menu bar icon: monitor logo plus optional stat summary.
struct MenuBarLabel: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: MonitorMenuBarIcon.image)
            if viewModel.showSummary {
                // Render compact segments: M 81% | Z 67%
                // Pipes go BETWEEN segments, not after the last one.
                let rows = viewModel.summaryRows
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Text("|")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Text("\(row.shortName) \(Formatting.percent(row.percent) ?? "")")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(colour(for: row.state))
                }
            }
        }
    }

    private func colour(for state: QuotaState) -> Color {
        switch state {
        case .healthy: return .primary
        case .warning: return .yellow
        case .critical, .exhausted, .error: return .red
        case .unknown: return .secondary
        }
    }
}

/// The popover content under the menu bar icon.
struct MenuBarContent: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().padding(.vertical, 4)

            if viewModel.hasActiveProviders {
                ForEach(viewModel.activeProviders, id: \.id) { provider in
                    ProviderCard(
                        provider: provider,
                        status: viewModel.statuses[provider.id],
                        error: viewModel.errors[provider.id]
                    )
                    Divider().padding(.vertical, 4)
                }
            } else {
                emptyState
                Divider().padding(.vertical, 4)
            }

            footer
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .frame(width: 280)
        .task {
            // Auto-refresh on launch. This fires once when the popover's
            // content view first appears (the app starts with the menu bar item).
            viewModel.start()
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.horizontal.axis")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("AIMonitor")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            if viewModel.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else if let last = viewModel.lastRefresh {
                Text(Formatting.relativeShort(from: last))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.horizontal.axis")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No stats enabled")
                .font(.system(size: 13, weight: .medium))
            Text("Enable a provider in Preferences to start monitoring.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Preferences") {
                SettingsOpener.open()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            actionButton("Refresh Now", systemImage: "arrow.clockwise", shortcut: "r") {
                viewModel.refreshAll()
            }
            actionButton("Preferences\u{2026}", systemImage: "gearshape") {
                SettingsOpener.open()
            }
            actionButton("Quit AIMonitor", systemImage: "power") {
                NSApp.terminate(nil)
            }
        }
    }

    /// Consistent-height action row with proper spacing.
    private func actionButton(_ title: String, systemImage: String,
                              shortcut: String? = nil,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: 28)
    }
}
