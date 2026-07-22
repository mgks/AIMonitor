import SwiftUI
import AppKit

/// Renders the monitor logo as a template NSImage, the only reliable way to
/// show a custom shape in a MenuBarExtra label. Template images adapt their
/// colour to the menu bar (light/dark) automatically.
enum MonitorMenuBarIcon {
    static let image: NSImage = {
        // Menu bar icon: simplified circle + bar + needle, matching the app icon.
        let renderSize: CGFloat = 40
        let displaySize: CGFloat = 20
        let img = NSImage(size: NSSize(width: renderSize, height: renderSize))
        img.lockFocus()

        let s = renderSize
        let cx = s * 0.5
        let cy = s * 0.5
        let r = s * 0.375
        let lw = s * 0.058

        // Circle outline.
        let circle = NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        circle.lineWidth = lw
        circle.stroke()

        // Horizontal bar.
        let barY = cy - r * 0.35
        let bar = NSBezierPath()
        bar.move(to: NSPoint(x: cx - r * 0.85, y: barY))
        bar.line(to: NSPoint(x: cx + r * 0.85, y: barY))
        bar.lineWidth = lw
        bar.lineCapStyle = .round
        bar.stroke()

        // Diagonal needle.
        let needle = NSBezierPath()
        needle.move(to: NSPoint(x: cx - r * 0.25, y: cy + r * 0.05))
        needle.line(to: NSPoint(x: cx + r * 0.5, y: cy + r * 0.7))
        needle.lineWidth = lw
        needle.lineCapStyle = .round
        needle.stroke()

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
            if viewModel.showSummary, let row = viewModel.summaryRow {
                Text(Formatting.percent(row.percent) ?? "")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(colour(for: row.state))
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
