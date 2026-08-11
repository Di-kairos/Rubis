import AppKit

/// Ключи `@AppStorage`, которые читают несколько сцен сразу. Одиночные ключи
/// живут прямо в своей сцене — сюда попадают только общие, чтобы строка не
/// разъезжалась между читателем и писателем.
enum SettingsKey {
    static let menuBarIcon = "ui.menuBarIcon"
    static let miniPlayerOnTop = "ui.miniPlayerOnTop"
    static let globalMediaKeys = "keys.globalMediaKeys"
    static let appearance = "ui.appearance"
    /// Потолок кэша скачанных с сервера треков, в гигабайтах (SPEC §6.2).
    static let streamCacheSizeGB = "server.streamCacheSizeGB"

    static let defaultStreamCacheSizeGB = 8
}

/// Оформление плеера. По умолчанию следует macOS; выбор Light/Dark прибивает
/// палитру независимо от системы — токены DesignSystem разрешаются через
/// `NSAppearance`, поэтому одного `NSApp.appearance` хватает на все окна.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    private var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// Единственное место, где оформление применяется к приложению.
    @MainActor
    static func apply(_ rawValue: String) {
        NSApp.appearance = (AppAppearance(rawValue: rawValue) ?? .system).nsAppearance
    }
}
