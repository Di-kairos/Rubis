/// Ключи `@AppStorage`, которые читают несколько сцен сразу. Одиночные ключи
/// живут прямо в своей сцене — сюда попадают только общие, чтобы строка не
/// разъезжалась между читателем и писателем.
enum SettingsKey {
    static let menuBarIcon = "ui.menuBarIcon"
    static let miniPlayerOnTop = "ui.miniPlayerOnTop"
    static let globalMediaKeys = "keys.globalMediaKeys"
}
