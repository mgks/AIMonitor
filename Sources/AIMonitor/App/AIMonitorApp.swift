import SwiftUI
import AppKit
import UserNotifications

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
/// Registers the app as a notification delegate so alerts appear even for
/// unsigned menu-bar apps, and applies the appearance preference.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearanceManager.apply()
        // Set the notification delegate so alerts fire even without a signing identity.
        UNUserNotificationCenter.current().delegate = self
    }

    /// Show notifications even when the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
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
