import SwiftUI

/// The menu bar icon: a coloured dot plus the worst-case percent.
struct MenuBarLabel: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.fill")
                .font(.system(size: 9))
                .foregroundColor(colour)
            if let pct = viewModel.worstRemainingPercent {
                Text(Formatting.percent(pct) ?? "")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
            }
        }
    }

    private var colour: Color {
        switch viewModel.worstState {
        case .healthy: return .green
        case .warning: return .yellow
        case .critical, .exhausted, .error: return .red
        case .unknown: return .secondary
        }
    }
}

/// The popover that expands under the menu bar icon: one card per provider,
/// then global actions.
struct MenuBarContent: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().padding(.vertical, 4)

            ForEach(viewModel.providers, id: \.id) { provider in
                ProviderCard(
                    provider: provider,
                    status: viewModel.statuses[provider.id],
                    error: viewModel.errors[provider.id]
                )
                Divider().padding(.vertical, 4)
            }

            footer
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(width: 280)
    }

    private var header: some View {
        HStack {
            Text("AIStat")
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

    private var footer: some View {
        VStack(spacing: 2) {
            Button {
                viewModel.refreshAll()
            } label: {
                Label("Refresh Now", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .keyboardShortcut("r", modifiers: .command)
            .buttonStyle(.plain)

            Button {
                SettingsOpener.open()
            } label: {
                Label("Preferences\u{2026}", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit AIStat", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }
}
