import SwiftUI

/// Preferences window: General, Providers, Credentials.
struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        TabView {
            GeneralTab(viewModel: viewModel)
                .tabItem { Label("General", systemImage: "gearshape") }

            ProvidersTab(viewModel: viewModel)
                .tabItem { Label("Providers", systemImage: "list.bullet") }

            CredentialsTab(viewModel: viewModel)
                .tabItem { Label("Credentials", systemImage: "key.fill") }
        }
        .frame(width: 460, height: 440)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var viewModel: AppViewModel
    @AppStorage(AppSettings.Keys.launchAtLogin) private var launchAtLogin = false
    @AppStorage(AppSettings.Keys.refreshInterval) private var interval = AppSettings.defaultRefreshInterval
    @AppStorage(AppSettings.Keys.appearance) private var appearance = "system"
    @AppStorage(AppSettings.Keys.showSummary) private var showSummary = false
    @AppStorage(AppSettings.Keys.summaryMode) private var summaryMode = "remaining"
    @AppStorage(AppSettings.Keys.notifyUnder20) private var notifyUnder20 = true
    @AppStorage(AppSettings.Keys.notifyUnder10) private var notifyUnder10 = true
    @AppStorage(AppSettings.Keys.notifyExhausted) private var notifyExhausted = true
    @AppStorage(AppSettings.Keys.notifyReset) private var notifyReset = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch AIMonitor on login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in LoginItem.set(newValue) }
            }

            Section("Refresh") {
                Picker("Interval", selection: $interval) {
                    Text("30 seconds").tag(30.0)
                    Text("60 seconds").tag(60.0)
                    Text("5 minutes").tag(300.0)
                }
                .onChange(of: interval) { newValue in viewModel.applyRefreshInterval(newValue) }
            }

            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    ForEach(AppSettings.appearanceOptions, id: \.self) { Text($0.capitalized).tag($0) }
                }
                .onChange(of: appearance) { _ in AppearanceManager.apply() }
            }

            Section("Menu bar summary") {
                Toggle("Show usage summary in menu bar", isOn: $viewModel.showSummary)
                    .onChange(of: viewModel.showSummary) { newValue in
                        UserDefaults.standard.set(newValue, forKey: AppSettings.Keys.showSummary)
                    }
                if viewModel.showSummary {
                    Picker("Display mode", selection: $summaryMode) {
                        ForEach(AppSettings.summaryModes, id: \.self) {
                            Text($0.capitalized).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section("Notifications") {
                Toggle("Warn under 20%", isOn: $notifyUnder20)
                Toggle("Warn under 10%", isOn: $notifyUnder10)
                Toggle("When exhausted", isOn: $notifyExhausted)
                Toggle("When quota resets", isOn: $notifyReset)
            }

            Section {
                VStack(spacing: 6) {
                    Text("AIMonitor v0.1.0")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Link("View on GitHub", destination: URL(string: "https://github.com/mgks/AIQuota")!)
                        .font(.system(size: 10))
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Providers

private struct ProvidersTab: View {
    @ObservedObject var viewModel: AppViewModel
    @AppStorage(AppSettings.Keys.showSummary) private var showSummary = false

    var body: some View {
        Form {
            Section("Enabled providers") {
                ForEach(viewModel.providers, id: \.id) { provider in
                    let isOn = viewModel.isProviderEnabled(provider.id)
                    Toggle(isOn: Binding(
                        get: { isOn },
                        set: { newValue in
                            viewModel.setProviderEnabled(provider.id, newValue)
                        }
                    )) {
                        HStack {
                            Image(systemName: provider.symbolName)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading) {
                                Text(provider.displayName)
                                if !viewModel.isProviderConfigured(provider.id) {
                                    Text("No API key set")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }

                    // Per-provider summary toggle, shown when summary is on.
                    if showSummary && isOn {
                        Toggle(isOn: Binding(
                            get: { viewModel.isProviderInSummary(provider.id) },
                            set: { newValue in
                                viewModel.setProviderInSummary(provider.id, newValue)
                            }
                        )) {
                            Text("Show in menu bar summary")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 20)
                        }
                    }
                }
            }
            Section {
                Text("Enable a provider, then add its API key in the Credentials tab. Only enabled providers with keys appear in the menu bar popover.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Credentials

private struct CredentialsTab: View {
    @ObservedObject var viewModel: AppViewModel
    @AppStorage("minimax.region") private var minimaxRegion = "international"
    @AppStorage("zai.region") private var zaiRegion = "international"

    var body: some View {
        Form {
            Section {
                Text("Claude Code and Codex use OAuth credentials stored by their CLI tools. Log in with `claude` or `codex login` to enable them. No key needed here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Kimi") {
                SecureField("API Key", text: kimiKeyBinding)
            }

            Section("MiniMax") {
                Picker("Region", selection: $minimaxRegion) {
                    Text("International (minimax.io)").tag("international")
                    Text("China (minimaxi.com)").tag("china")
                }
                SecureField("API Key", text: $viewModel.minimaxKey)
                    .onChange(of: viewModel.minimaxKey) { _ in
                        viewModel.saveMinimaxKey()
                    }
            }

            Section("Z.ai (GLM)") {
                Picker("Region", selection: $zaiRegion) {
                    Text("International (z.ai)").tag("international")
                    Text("China (bigmodel.cn)").tag("china")
                }
                SecureField("API Key", text: $viewModel.zaiKey)
                    .onChange(of: viewModel.zaiKey) { _ in
                        viewModel.saveZaiKey()
                    }
            }

            Section("DeepSeek") {
                SecureField("API Key", text: deepSeekKeyBinding)
            }

            Section("OpenRouter") {
                SecureField("API Key", text: openRouterKeyBinding)
            }

            Section {
                Text("Keys are stored in the macOS Keychain, never synced, and sent only to the provider you choose.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // Generic Keychain-backed bindings for providers without dedicated AppViewModel fields.
    private var kimiKeyBinding: Binding<String> {
        Binding(
            get: { KeychainStore().get("kimi.apiKey") ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { KeychainStore().remove("kimi.apiKey") }
                else { try? KeychainStore().set(trimmed, for: "kimi.apiKey") }
                viewModel.refreshAll()
            }
        )
    }
    private var deepSeekKeyBinding: Binding<String> {
        Binding(
            get: { KeychainStore().get("deepseek.apiKey") ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { KeychainStore().remove("deepseek.apiKey") }
                else { try? KeychainStore().set(trimmed, for: "deepseek.apiKey") }
                viewModel.refreshAll()
            }
        )
    }

    private var openRouterKeyBinding: Binding<String> {
        Binding(
            get: { KeychainStore().get("openrouter.apiKey") ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { KeychainStore().remove("openrouter.apiKey") }
                else { try? KeychainStore().set(trimmed, for: "openrouter.apiKey") }
                viewModel.refreshAll()
            }
        )
    }
}
