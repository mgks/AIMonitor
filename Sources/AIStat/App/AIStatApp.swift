import SwiftUI
import AppKit

@main
struct AIStatApp: App {

    // AppDelegate runs setActivationPolicy after NSApp exists. Calling it in
    // init() crashes because NSApp is still nil during App construction.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppViewModel()
    @AppStorage(AppSettings.Keys.refreshInterval) private var storedInterval = AppSettings.defaultRefreshInterval

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(viewModel: viewModel)
        } label: {
            MenuBarLabel(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}

/// Handles lifecycle hooks SwiftUI does not expose directly. Used only to
/// force the accessory activation policy so `swift run` (no .app bundle,
/// no LSUIElement) also stays out of the Dock.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
