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
        if let existing = read() { return existing }
        let key = Curve25519.Signing.PrivateKey()
        if store(key) { return key }
        // Запись есть, но не читается или не разбирается в ключ — она мертва.
        // Оставить её значило бы навсегда остаться с отпечатком вместо подписи.
        SecItemDelete(base() as CFDictionary)
        return store(key) ? key : nil
    }

    private static func read() -> Curve25519.Signing.PrivateKey? {
        var query = base()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data
        else { return nil }
        return try? Curve25519.Signing.PrivateKey(rawRepresentation: data)
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
