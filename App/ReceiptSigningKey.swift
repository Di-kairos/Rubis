import CryptoKit
import Foundation
import Security

/// Ключ подписи отчётов о тракте (D-012): Ed25519, свой у каждой установки.
/// Приватная половина живёт в связке ключей и наружу не выходит; публичная
/// печатается в каждом отчёте, поэтому «опубликовать ключ» отдельным действием
/// не нужно.
enum ReceiptSigningKey {
    private static let service = "Rubis Music"
    private static let account = "signal-path-receipt-key"

    /// Ключ установки. Создаётся при первом отчёте, дальше только читается:
    /// перезапись стирает выданное «Always Allow» вместе со старой записью
    /// (урок 0.8.3/0.8.4, тот же, что у пароля Subsonic).
    ///
    /// `nil` — связка недоступна (заблокирована, отказ пользователя): отчёт
    /// выйдет с отпечатком вместо подписи, а не без ничего.
    static func load() -> Curve25519.Signing.PrivateKey? {
        var query = base()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &item) {
        case errSecSuccess:
            if let data = item as? Data,
                let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data)
            {
                return key
            }
            // Запись есть, но это не ключ — она мертва. Только в этом случае
            // её и заменяем: иначе отчёт навсегда остался бы с отпечатком.
            SecItemDelete(base() as CFDictionary)
            return create()
        case errSecItemNotFound:
            return create()
        default:
            // Связка заблокирована, доступ запрещён, диалог невозможен —
            // временная беда. Ключ установки не трогаем: ротация по отказу
            // доступа меняла бы идентичность отчётов без причины.
            return nil
        }
    }

    private static func create() -> Curve25519.Signing.PrivateKey? {
        let key = Curve25519.Signing.PrivateKey()
        return store(key) ? key : nil
    }

    private static func store(_ key: Curve25519.Signing.PrivateKey) -> Bool {
        var add = base()
        add[kSecValueData as String] = key.rawRepresentation
        // ThisDeviceOnly: отчёт утверждает «одна установка». Ключ, уехавший на
        // другой Mac в резервной копии связки, сделал бы это утверждение ложью.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    private static func base() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
