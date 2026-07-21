import SwiftUI

/// The monitor logo drawn as a vector shape in SwiftUI Canvas.
/// Matches the AppIcon design: rounded rect outline + magenta graph bump.
struct MonitorIconShape: View {
    var size: CGFloat = 18

    var body: some View {
        Canvas { ctx, sz in
            let w = sz.width
            let h = sz.height

            // Outer rounded rect (monitor frame).
            let inset = w * 0.12
            let rect = CGRect(x: inset, y: inset,
                              width: w - 2 * inset, height: h - 2 * inset)
            let frame = Path(roundedRect: rect, cornerRadius: w * 0.18)
            ctx.stroke(frame, with: .color(.primary), lineWidth: w * 0.075)

            // Graph line: bump shape going up in the middle.
            var line = Path()
            let baseY = h * 0.58
            let peakY = h * 0.35
            line.move(to: CGPoint(x: w * 0.28, y: baseY))
            line.addLine(to: CGPoint(x: w * 0.36, y: baseY))
            line.addQuadCurve(
                to: CGPoint(x: w * 0.5, y: peakY),
                control: CGPoint(x: w * 0.42, y: baseY - h * 0.02)
            )
            line.addQuadCurve(
                to: CGPoint(x: w * 0.64, y: baseY),
                control: CGPoint(x: w * 0.58, y: peakY + h * 0.02)
            )
            line.addLine(to: CGPoint(x: w * 0.72, y: baseY))
            ctx.stroke(line, with: .color(Color(red: 0.875, green: 0.078, blue: 0.388)),
                       lineWidth: w * 0.075)
        }
        .frame(width: size, height: size)
    }
}

/// The menu bar icon: monitor logo plus optional stat summary.
struct MenuBarLabel: View {
    @ObservedObject var viewModel: AppViewModel
    @AppStorage(AppSettings.Keys.showSummary) private var showSummary = false

    var body: some View {
        HStack(spacing: 4) {
            MonitorIconShape(size: 16)
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
            MonitorIconShape(size: 14)
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
