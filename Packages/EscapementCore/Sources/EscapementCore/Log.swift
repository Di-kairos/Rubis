import os

/// Central logging facade. One subsystem, four categories (SPEC §9).
/// Real-time audio code must never log — see CLAUDE.md "Аудио — особый режим".
public enum Log {
    /// Matches PRODUCT_BUNDLE_IDENTIFIER in Config/Escapement.xcconfig.
    public static let subsystem = "com.dikairos.escapement"

    public static let audio = Logger(subsystem: subsystem, category: "audio")
    public static let library = Logger(subsystem: subsystem, category: "library")
    public static let network = Logger(subsystem: subsystem, category: "network")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
}
