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
        .frame(width: 440, height: 420)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var viewModel: AppViewModel
    @AppStorage(AppSettings.Keys.launchAtLogin) private var launchAtLogin = false
    @AppStorage(AppSettings.Keys.refreshInterval) private var interval = AppSettings.defaultRefreshInterval
    @AppStorage(AppSettings.Keys.appearance) private var appearance = "system"
    @AppStorage(AppSettings.Keys.notifyUnder20) private var notifyUnder20 = true
    @AppStorage(AppSettings.Keys.notifyUnder10) private var notifyUnder10 = true
    @AppStorage(AppSettings.Keys.notifyExhausted) private var notifyExhausted = true
    @AppStorage(AppSettings.Keys.notifyReset) private var notifyReset = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch AIStat on login", isOn: $launchAtLogin)
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
            }

            Section("Notifications") {
                Toggle("Warn under 20%", isOn: $notifyUnder20)
                Toggle("Warn under 10%", isOn: $notifyUnder10)
                Toggle("When exhausted", isOn: $notifyExhausted)
                Toggle("When quota resets", isOn: $notifyReset)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Providers

private struct ProvidersTab: View {
    @ObservedObject var viewModel: AppViewModel
    @AppStorage(AppSettings.Keys.enabledProviders) private var enabledData = ""

    private var enabled: Set<String> {
        get { Set(enabledData.split(separator: ",").map(String.init)) }
    }

    var body: some View {
        Form {
            Section("Enabled providers") {
                ForEach(viewModel.providers, id: \.id) { provider in
                    let isOn = enabled.contains(provider.id)
                    Toggle(provider.displayName, isOn: Binding(
                        get: { isOn },
                        set: { newValue in toggle(provider.id, on: newValue) }
                    ))
                    .disabled(true)   // enable/disable wiring lands with the Providers UI v1.1
                }
            }
            Section {
                Text("Enable/disable toggles take effect in the next release. All configured providers run today.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func toggle(_ id: String, on: Bool) {
        var set = enabled
        if on { set.insert(id) } else { set.remove(id) }
        enabledData = set.sorted().joined(separator: ",")
    }
}

// MARK: - Credentials

private struct CredentialsTab: View {
    @ObservedObject var viewModel: AppViewModel
    @AppStorage("minimax.region") private var minimaxRegion = "international"
    @AppStorage("zai.region") private var zaiRegion = "international"

    private let secrets = KeychainStore()

    var body: some View {
        Form {
            Section("MiniMax") {
                Picker("Region", selection: $minimaxRegion) {
                    Text("International (minimax.io)").tag("international")
                    Text("China (minimaxi.com)").tag("china")
                }
                SecureCredentialField(label: "API Key", account: "minimax.apiKey", secrets: secrets) {
                    viewModel.refreshAll()
                }
            }

            Section("Z.ai (GLM)") {
                Picker("Region", selection: $zaiRegion) {
                    Text("International (z.ai)").tag("international")
                    Text("China (bigmodel.cn)").tag("china")
                }
                SecureCredentialField(label: "API Key", account: "zai.apiKey", secrets: secrets) {
                    viewModel.refreshAll()
                }
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
}

/// Backing store for a Keychain-backed field. ObservableObject is used
/// instead of @State because the SwiftUI @State macro plugin is unavailable
/// when building with Command Line Tools (no Xcode.app installed).
private final class CredentialValue: ObservableObject {
    var value: String = ""
    var loaded = false
}

/// A SecureField bound to the Keychain. Loads on first appear, writes
/// through on every change.
private struct SecureCredentialField: View {
    let label: String
    let account: String
    let secrets: KeychainStore
    let onChange: () -> Void

    @ObservedObject private var store = CredentialValue()

    var body: some View {
        SecureField(label, text: $store.value)
            .task {
                guard !store.loaded else { return }
                store.value = secrets.get(account) ?? ""
                store.loaded = true
            }
            .onChange(of: store.value) { newValue in
                persist(newValue)
            }
    }

    private func persist(_ newValue: String) {
        do {
            if newValue.isEmpty {
                secrets.remove(account)
            } else {
                try secrets.set(newValue, for: account)
            }
            onChange()
        } catch {
            NSLog("[AIStat] failed to save \(account): \(error)")
        }
    }
}
