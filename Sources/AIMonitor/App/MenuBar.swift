import SwiftUI
import AppKit

/// Renders the monitor logo as a template NSImage, the only reliable way to
/// show a custom shape in a MenuBarExtra label. Template images adapt their
/// colour to the menu bar (light/dark) automatically.
enum MonitorMenuBarIcon {
    /// Template image drawn from the SVG glyph: circle + bar + needle.
    static let image: NSImage = {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="40" height="40">
          <g fill="black">
            <path d="M12,24C5.4,24,0,18.6,0,12S5.4,0,12,0s12,5.4,12,12S18.6,24,12,24z M12,2C6.5,2,2,6.5,2,12s4.5,10,10,10s10-4.5,10-10S17.5,2,12,2z"/>
            <rect x="2" y="16" width="20" height="2"/>
            <path d="M12,18c-0.2,0-0.3,0-0.5-0.1c-0.5-0.3-0.6-0.9-0.4-1.4l5-8.7c0.3-0.5,0.9-0.6,1.4-0.4c0.5,0.3,0.6,0.9,0.4,1.4l-5,8.7C12.7,17.8,12.3,18,12,18z"/>
          </g>
        </svg>
        """
        let temp = "/tmp/aistat-menubar-glyph.svg"
        try? svg.write(toFile: temp, atomically: true, encoding: .utf8)
        guard let svgImage = NSImage(contentsOfFile: temp) else {
            // Fallback: simple circle.
            let fallback = NSImage(size: NSSize(width: 20, height: 20))
            fallback.lockFocus()
            NSBezierPath(ovalIn: NSRect(x: 4, y: 4, width: 12, height: 12)).stroke()
            fallback.unlockFocus()
            fallback.isTemplate = true
            return fallback
        }
        // Render at 4x display size then downscale for crisp, thin edges.
        let renderSize: CGFloat = 52
        let displaySize: CGFloat = 13
        let img = NSImage(size: NSSize(width: renderSize, height: renderSize))
        img.lockFocus()
        svgImage.draw(in: NSRect(x: 0, y: 0, width: renderSize, height: renderSize),
                      from: .zero, operation: .copy, fraction: 1.0)
        img.unlockFocus()
        img.isTemplate = true
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
