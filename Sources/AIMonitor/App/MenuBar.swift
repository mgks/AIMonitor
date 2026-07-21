import SwiftUI
import AppKit

/// Renders the monitor logo as a template NSImage, the only reliable way to
/// show a custom shape in a MenuBarExtra label. Template images adapt their
/// colour to the menu bar (light/dark) automatically.
enum MonitorMenuBarIcon {
    static let image: NSImage = {
        let size: CGFloat = 32    // render at 2x for the ~16pt menu bar
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()

        let inset: CGFloat = size * 0.12
        let rect = NSRect(x: inset, y: inset,
                          width: size - 2 * inset, height: size - 2 * inset)
        let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.18, yRadius: size * 0.18)
        path.lineWidth = size * 0.075
        path.lineJoinStyle = .round
        path.stroke()

        // Graph bump inside the frame.
        let bump = NSBezierPath()
        let baseY = size * 0.58
        let peakY = size * 0.35
        bump.move(to: NSPoint(x: size * 0.28, y: baseY))
        bump.line(to: NSPoint(x: size * 0.36, y: baseY))
        bump.curve(to: NSPoint(x: size * 0.5, y: peakY),
                   controlPoint1: NSPoint(x: size * 0.42, y: baseY),
                   controlPoint2: NSPoint(x: size * 0.42, y: baseY))
        bump.curve(to: NSPoint(x: size * 0.64, y: baseY),
                   controlPoint1: NSPoint(x: size * 0.58, y: peakY),
                   controlPoint2: NSPoint(x: size * 0.58, y: peakY))
        bump.line(to: NSPoint(x: size * 0.72, y: baseY))
        bump.lineWidth = size * 0.075
        bump.lineCapStyle = .round
        bump.stroke()

        img.unlockFocus()
        img.isTemplate = true    // adaptive colour for light/dark menu bar
        return img
    }()
}

/// The menu bar icon: monitor logo plus optional stat summary.
struct MenuBarLabel: View {
    @ObservedObject var viewModel: AppViewModel
    @AppStorage(AppSettings.Keys.showSummary) private var showSummary = false

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: MonitorMenuBarIcon.image)
            if showSummary, let pct = viewModel.summaryPercent {
                Text(Formatting.percent(pct) ?? "")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
            }
        }
    }
}

/// The popover content under the menu bar icon.
struct MenuBarContent: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().padding(.vertical, 6)

            if viewModel.hasActiveProviders {
                ForEach(viewModel.activeProviders, id: \.id) { provider in
                    ProviderCard(
                        provider: provider,
                        status: viewModel.statuses[provider.id],
                        error: viewModel.errors[provider.id]
                    )
                    Divider().padding(.vertical, 6)
                }
            } else {
                emptyState
                Divider().padding(.vertical, 6)
            }

            footer
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(width: 280)
    }

    private var header: some View {
        HStack {
            Image(nsImage: MonitorMenuBarIcon.image)
            Text("AIMonitor")
                .font(.headline)
            Spacer()
            if viewModel.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else if let last = viewModel.lastRefresh {
                Text(Formatting.relativeShort(from: last))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
