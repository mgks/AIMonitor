import SwiftUI

/// Preferences window: General, Providers, About.
struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        TabView {
            GeneralTab(viewModel: viewModel)
                .tabItem { Label("General", systemImage: "gearshape") }

            ProvidersTab(viewModel: viewModel)
                .tabItem { Label("Providers", systemImage: "list.bullet") }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 420)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var viewModel: AppViewModel
    @AppStorage(AppSettings.Keys.launchAtLogin) private var launchAtLogin = false
    @AppStorage(AppSettings.Keys.refreshInterval) private var interval = AppSettings.defaultRefreshInterval
    @AppStorage(AppSettings.Keys.appearance) private var appearance = "system"

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch AIMonitor on login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in LoginItem.set(newValue) }

                Picker("Refresh interval", selection: $interval) {
                    Text("30 seconds").tag(30.0)
                    Text("60 seconds").tag(60.0)
                    Text("5 minutes").tag(300.0)
                }
                .onChange(of: interval) { newValue in viewModel.applyRefreshInterval(newValue) }

                Picker("Appearance", selection: $appearance) {
                    ForEach(AppSettings.appearanceOptions, id: \.self) { Text($0.capitalized).tag($0) }
                }
                .onChange(of: appearance) { _ in AppearanceManager.apply() }
            }

            Section("Menu bar summary") {
                Toggle("Show usage summary", isOn: $viewModel.showSummary)
                    .onChange(of: viewModel.showSummary) { newValue in
                        UserDefaults.standard.set(newValue, forKey: AppSettings.Keys.showSummary)
                    }
                if viewModel.showSummary {
                    Picker("Provider", selection: Binding(
                        get: { viewModel.summaryProviderID },
                        set: { viewModel.setSummaryProvider($0) }
                    )) {
                        ForEach(viewModel.activeProviders, id: \.id) { provider in
                            Text(provider.displayName).tag(provider.id)
                        }
                    }
                    Picker("Display mode", selection: Binding(
                        get: { viewModel.summaryMode },
                        set: { viewModel.setSummaryMode($0) }
                    )) {
                        ForEach(AppSettings.summaryModes, id: \.self) {
                            Text($0.capitalized).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Providers (merged with Credentials)

private struct ProvidersTab: View {
    @ObservedObject var viewModel: AppViewModel
    @AppStorage("minimax.region") private var minimaxRegion = "international"
    @AppStorage("zai.region") private var zaiRegion = "international"

    var body: some View {
        Form {
            Section("Providers") {
                ForEach(viewModel.providers, id: \.id) { provider in
                    providerSection(provider)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private func providerSection(_ provider: any AIProvider) -> some View {
        let isOn = viewModel.isProviderEnabled(provider.id)
        let configured = viewModel.isProviderConfigured(provider.id)

        Toggle(isOn: Binding(
            get: { isOn },
            set: { newValue in viewModel.setProviderEnabled(provider.id, newValue) }
        )) {
            HStack {
                Image(systemName: provider.symbolName)
                    .foregroundStyle(.secondary)
                Text(provider.displayName)
                if !configured {
                    Text("No key")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }

        // Expand config fields when enabled.
        if isOn {
            configFields(for: provider)
        }
    }

    @ViewBuilder
    private func configFields(for provider: any AIProvider) -> some View {
        switch provider.id {
        case "claude":
            VStack(alignment: .leading, spacing: 4) {
                Text("Uses OAuth via Claude Code CLI. Run `claude` to log in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("npm install -g @anthropic-ai/claude-code")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 20)

        case "codex":
            VStack(alignment: .leading, spacing: 4) {
                Text("Uses OAuth via Codex CLI. Run `codex login` to authenticate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("npm install -g @openai/codex")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 20)

        case "kimi":
            SecureField("API Key", text: $viewModel.kimiKey)
                .onChange(of: viewModel.kimiKey) { _ in viewModel.saveKimiKey() }
                .padding(.leading, 20)

        case "minimax":
            Picker("Region", selection: $minimaxRegion) {
                Text("International (minimax.io)").tag("international")
                Text("China (minimaxi.com)").tag("china")
            }
            .padding(.leading, 20)
            SecureField("API Key", text: $viewModel.minimaxKey)
                .onChange(of: viewModel.minimaxKey) { _ in viewModel.saveMinimaxKey() }
                .padding(.leading, 20)

        case "zai":
            Picker("Region", selection: $zaiRegion) {
                Text("International (z.ai)").tag("international")
                Text("China (bigmodel.cn)").tag("china")
            }
            .padding(.leading, 20)
            SecureField("API Key", text: $viewModel.zaiKey)
                .onChange(of: viewModel.zaiKey) { _ in viewModel.saveZaiKey() }
                .padding(.leading, 20)

        case "deepseek":
            SecureField("API Key", text: $viewModel.deepSeekKey)
                .onChange(of: viewModel.deepSeekKey) { _ in viewModel.saveDeepSeekKey() }
                .padding(.leading, 20)

        case "openrouter":
            SecureField("API Key", text: $viewModel.openRouterKey)
                .onChange(of: viewModel.openRouterKey) { _ in viewModel.saveOpenRouterKey() }
                .padding(.leading, 20)

        default:
            EmptyView()
        }
    }
}

// MARK: - About

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 6) {
            Spacer()
            Text("AIMonitor")
                .font(.title3.bold())
            Text("Version 0.1.0")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Monitor AI service quotas from your menu bar.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com/mgks/AIMonitor")!)
                    .font(.caption)
                Link("Issues", destination: URL(string: "https://github.com/mgks/AIMonitor/issues")!)
                    .font(.caption)
            }
            .padding(.top, 4)
            Spacer()
            Text("MIT \u{00B7} mgks.dev")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding()
    }
}
