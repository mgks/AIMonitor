import Foundation
import AppKit
import ServiceManagement

/// Launch-at-login via SMAppService (macOS 13+). No separate helper app needed.
/// Only effective when running from a real .app bundle; harmless otherwise.
public enum LoginItem {
    public static var isEnabled: Bool {
        // .enabled is the steady-state of a successfully registered login item.
        SMAppService.mainApp.status == .enabled
    }

    @MainActor
    public static func set(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Surface in the run log; not fatal. Often happens for unsigned dev builds.
            NSLog("[AIMonitor] login item toggle failed: \(error.localizedDescription)")
        }
    }
}

/// Opens the Settings window. The selector name changed between macOS 13 and 14.
/// Also re-activates the app so the window comes to the front even after the
/// popover dismissed it.
public enum SettingsOpener {
    @MainActor
    public static func open() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14, *) {
            // Try the new selector first; fall back to the 13.0 one.
            if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
                bringSettingsToFront()
                return
            }
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        bringSettingsToFront()
    }

    @MainActor
    private static func bringSettingsToFront() {
        // Defer so the window exists by the time we search for it.
        DispatchQueue.main.async {
            for window in NSApp.windows where window.title.contains("Settings")
                || window.title.contains("Preferences")
                || window.frameAutosaveName.contains("Settings") {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

/// Small formatting helpers for the card and menu bar label.
public enum Formatting {
    /// Compact relative label: "Updated 2 min ago".
    public static func relativeShort(from date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Never" }
        let secs = Int(now.timeIntervalSince(date))
        if secs < 5 { return "Just now" }
        if secs < 60 { return "\(secs)s ago" }
        if secs < 3600 { return "\(secs / 60)m ago" }
        if secs < 86400 { return "\(secs / 3600)h ago" }
        return "\(secs / 86400)d ago"
    }

    /// "3h 18m" style for a reset countdown.
    public static func countdown(to date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let secs = max(0, Int(date.timeIntervalSince(now)))
        if secs == 0 { return "now" }
        let h = secs / 3600
        let m = (secs % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(secs)s"
    }

    /// "Clock" form for a reset time: "Today 11:00 PM".
    public static func clockTime(_ date: Date?) -> String? {
        guard let date else { return nil }
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }

    /// Currency with two decimals, e.g. "$17.43".
    public static func credits(_ value: Double?, currency: String = "USD") -> String? {
        guard let value else { return nil }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        return f.string(from: NSNumber(value: value))
    }

    /// Whole-number percent with no decimals.
    public static func percent(_ value: Double?) -> String? {
        guard let value else { return nil }
        return "\(Int(value.rounded()))%"
    }

    /// Compact token counts, e.g. "12.4k".
    public static func tokens(_ value: Int?) -> String? {
        guard let value else { return nil }
        if value < 1000 { return "\(value)" }
        return String(format: "%.1fk", Double(value) / 1000)
    }
}
