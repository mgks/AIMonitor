import SwiftUI
import AppKit

@main
struct AIMonitorApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppViewModel()
    @AppStorage(AppSettings.Keys.appearance) private var appearance = "system"

    init() {}

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

/// Handles lifecycle hooks SwiftUI does not expose directly.
/// Applies the appearance preference and the accessory activation policy.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppearanceManager.apply()
    }
}

/// Reads the appearance preference from UserDefaults and applies it to NSApp.
/// Called on launch and whenever the preference changes.
enum AppearanceManager {
    static func apply() {
        let mode = UserDefaults.standard.string(forKey: AppSettings.Keys.appearance) ?? "system"
        switch mode {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil
        }
    }
}
