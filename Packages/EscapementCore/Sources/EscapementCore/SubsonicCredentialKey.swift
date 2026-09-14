import Foundation

/// Под каким ключом пароль Subsonic лежит в связке.
///
/// Запись определяется парой `(host, username)` — порт, путь, схема и завершающий
/// слеш в адресе на неё не влияют. Сравнение строк адреса вместо этого ключа стирало
/// только что сохранённый пароль: `https://music.example:4533` →
/// `https://music.example:4534` при том же логине — это одна и та же запись
/// (R01, перепроверка аудита 13.09.2026).
public struct SubsonicCredentialKey: Equatable, Sendable {
    public let host: String
    public let username: String

    public init(host: String, username: String) {
        self.host = host
        self.username = username
    }

    /// Ключ из строки адреса. Пустой `host` означает, что адрес не разбирается —
    /// вызывающая сторона показывает ошибку и ничего не трогает в связке.
    public init(serverURL: String, username: String) {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(host: URL(string: trimmed)?.host ?? "", username: username)
    }

    /// Старая запись, которую можно удалить ПОСЛЕ успешного сохранения нового пароля
    /// и источника. `nil` — когда старая запись и есть новая: удалять нечего, иначе
    /// уничтожается только что записанный секрет.
    public static func stale(old: SubsonicCredentialKey?, new: SubsonicCredentialKey)
        -> SubsonicCredentialKey?
    {
        guard let old, old != new, !old.host.isEmpty else { return nil }
        return old
    }
}
