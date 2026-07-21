import Foundation

/// UserDefaults keys and defaults for AIStat preferences.
/// Kept as an enum namespace; @AppStorage reads these directly in views.
public enum AppSettings {
    public enum Keys {
        public static let launchAtLogin    = "launchAtLogin"
        public static let refreshInterval  = "refreshIntervalSeconds"
        public static let appearance       = "appearance"          // system | light | dark
        public static let notifyUnder20    = "notifyUnder20"
        public static let notifyUnder10    = "notifyUnder10"
        public static let notifyExhausted  = "notifyExhausted"
        public static let notifyReset      = "notifyResetAvailable"
        public static let enabledProviders = "enabledProviders"
    }

    public static let defaultRefreshInterval: TimeInterval = 60

    /// Appearance string -> SwiftUI scheme label.
    public static let appearanceOptions = ["system", "light", "dark"]
}
