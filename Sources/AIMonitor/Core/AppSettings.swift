import Foundation

/// UserDefaults keys and defaults for AIMonitor preferences.
/// Kept as an enum namespace; @AppStorage reads these directly in views.
public enum AppSettings {
    public enum Keys {
        public static let launchAtLogin     = "launchAtLogin"
        public static let refreshInterval   = "refreshIntervalSeconds"
        public static let appearance        = "appearance"
        public static let notifyUnder20     = "notifyUnder20"
        public static let notifyUnder10     = "notifyUnder10"
        public static let notifyExhausted   = "notifyExhausted"
        public static let notifyReset       = "notifyResetAvailable"

        // Per-provider enable toggles (shown in the popover when ON + configured).
        public static let enabledMinimax    = "enabled.minimax"
        public static let enabledZai        = "enabled.zai"

        // Menu bar stat summary.
        public static let showSummary       = "menubar.showSummary"
        public static let summaryMode       = "menubar.summaryMode"
        public static let summaryProvider   = "menubar.summaryProvider"   // which provider to show
    }

    public static let defaultRefreshInterval: TimeInterval = 60
    public static let appearanceOptions = ["system", "light", "dark"]
    public static let summaryModes = ["remaining", "used"]
}
