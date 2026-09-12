import EscapementCore
import Foundation
import Security
import SubsonicKit

/// Пароль от Subsonic-сервера — только в Keychain (SPEC §6.1):
/// `kSecClassInternetPassword`, account = имя пользователя, server = хост.
/// В UserDefaults, БД и логах его нет.
enum SubsonicPasswordStore {

    /// Обновление на месте, добавление — только когда записи нет. Delete→Add
    /// терял пароль, если добавление не удавалось (связка заблокирована), и
    /// пересоздавал запись, стирая выданное ей «Always Allow». Статус —
    /// вызывающему: UI не пишет Saved, пока связка не подтвердила.
    @discardableResult
    static func save(_ password: String, host: String, username: String) -> OSStatus {
        let query = base(host: host, username: username)
        guard !password.isEmpty, let data = password.data(using: .utf8) else {
            return SecItemDelete(query as CFDictionary)
        }
        let update = SecItemUpdate(
            query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard update == errSecItemNotFound else { return update }
        var add = query
        add[kSecValueData as String] = data
        return SecItemAdd(add as CFDictionary, nil)
    }

    /// Человеческое имя статуса связки для строки состояния.
    static func message(for status: OSStatus) -> String {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
    }

    /// Чтение НИЧЕГО не меняет в связке: пересохранение стирает выданное
    /// «Always Allow» вместе со старой записью — урок 0.8.3/0.8.4.
    static func load(host: String, username: String) -> String? {
        var query = base(host: host, username: username)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(host: String, username: String) {
        SecItemDelete(base(host: host, username: username) as CFDictionary)
    }

    private static func base(host: String, username: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: host,
            kSecAttrAccount as String: username,
        ]
    }
}

/// Сборка клиента из записи источника: адрес и логин лежат в БД, пароль — в связке.
enum SubsonicAccount {

    /// Хост, под которым пароль лежит в связке. Пустая строка означает,
    /// что адрес не разбирается — вызывающая сторона покажет ошибку.
    static func host(of serverURL: String) -> String {
        URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines))?.host ?? ""
    }

    /// Клиент для существующего источника или `nil`, если источник неполон
    /// (нет адреса, логина или пароля в связке).
    static func client(for source: Source) -> SubsonicClient? {
        guard source.kind == .subsonic,
            let serverURL = source.serverUrl,
            let username = source.username,
            let password = SubsonicPasswordStore.load(
                host: host(of: serverURL), username: username)
        else { return nil }
        return try? SubsonicClient(
            serverURL: serverURL, username: username, password: password)
    }
}
