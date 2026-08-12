import CryptoKit
import Foundation

/// Отчёт о тракте (фишка A): что именно происходит между файлом и ЦАПом —
/// в виде, который можно скопировать целиком и показать кому угодно.
///
/// Badge в транспорте отвечает «да» или «нет» одним взглядом; отчёт отвечает
/// «почему» и переживает копирование в чужой чат.
public struct SignalPathReceipt: Sendable, Equatable {
    public var date: Date
    /// «0.8.9 (26)» — версия и билд приложения.
    public var appVersion: String
    /// Название трека и артист; nil, когда ничего не играет.
    public var track: String?
    public var codec: String
    public var sourceRate: Double
    public var sourceBits: Int
    public var channels: Int
    public var deviceName: String
    /// USB / Built-in / Thunderbolt — как устройство видит система.
    public var deviceTransport: String
    public var deviceRate: Double
    public var exclusive: Bool
    /// nil — микшер не спрашивали (устройство не наше или проверка не шла).
    public var mixingDisabled: Bool?
    public var dsd: String?
    /// Политика при несовпадении частоты — из настроек Audio.
    public var fallback: String
    public var bitPerfect: Bool

    public init(
        date: Date, appVersion: String, track: String?, codec: String, sourceRate: Double,
        sourceBits: Int, channels: Int, deviceName: String, deviceTransport: String,
        deviceRate: Double, exclusive: Bool, mixingDisabled: Bool?, dsd: String?,
        fallback: String, bitPerfect: Bool
    ) {
        self.date = date
        self.appVersion = appVersion
        self.track = track
        self.codec = codec
        self.sourceRate = sourceRate
        self.sourceBits = sourceBits
        self.channels = channels
        self.deviceName = deviceName
        self.deviceTransport = deviceTransport
        self.deviceRate = deviceRate
        self.exclusive = exclusive
        self.mixingDisabled = mixingDisabled
        self.dsd = dsd
        self.fallback = fallback
        self.bitPerfect = bitPerfect
    }

    /// Вердикт словами — то же правило, что у badge, но с причиной.
    public var verdict: String {
        if bitPerfect {
            return "Bit-perfect — the file reaches the DAC unchanged"
        }
        if deviceRate != sourceRate {
            return "Resampled — the device is running at a different rate"
        }
        if !exclusive {
            return "Shared — CoreAudio mixes this output with other apps"
        }
        return "Not bit-perfect"
    }

    /// Имена полей подписи — по ним же отчёт разбирается обратно
    /// (`ReceiptSigning.parse`).
    public static let keyField = "Key"
    public static let signatureField = "Signature"

    /// Готовый к вставке текст с подписью (D-012). Подписывается ровно то тело,
    /// что видно выше подписи, — байт в байт.
    public func rendered(signedBy key: Curve25519.Signing.PrivateKey) throws -> String {
        let body = self.body()
        let signature = try ReceiptSigning.sign(body, with: key)
        return body + "\n"
            + field(Self.keyField, signature.publicKey) + "\n"
            + field(Self.signatureField, signature.value)
    }

    /// Готовый к вставке текст. Моноширинная сетка: колонка значений начинается
    /// на одном месте, чтобы отчёт читался и в чате без форматирования.
    ///
    /// Без ключа — с отпечатком вместо подписи: он ловит правку цифр в
    /// скопированном тексте, но авторства не доказывает.
    public func rendered() -> String {
        let body = self.body()
        return body + "\n" + field("Fingerprint", Self.fingerprint(of: body))
    }

    /// Тело отчёта: всё, кроме строк подписи.
    public func body() -> String {
        var lines = [
            "RUBIS MUSIC — SIGNAL PATH RECEIPT",
            "\(Self.stamp(date)) · Rubis Music \(appVersion)",
            "",
        ]
        if let track { lines.append(field("Track", track)) }
        lines.append(
            field(
                "Source",
                "\(codec.uppercased()) · \(Self.khz(sourceRate)) · \(sourceBits) bit "
                    + "· \(channels) ch"))
        lines.append(field("Device", "\(deviceName) (\(deviceTransport))"))
        lines.append(field("Device rate", Self.khz(deviceRate)))
        lines.append(field("Exclusive", exclusive ? "yes (hog mode)" : "no"))
        if let mixingDisabled {
            lines.append(field("Mixer", mixingDisabled ? "switched off" : "left on"))
        }
        if let dsd { lines.append(field("DSD", dsd)) }
        lines.append(field("Rate policy", fallback))
        lines.append(String(repeating: "-", count: 52))
        lines.append(field("VERDICT", verdict))
        return lines.joined(separator: "\n")
    }

    /// Отпечаток тела отчёта. Не подпись — доказать авторство он не может,
    /// но замену пары цифр в скопированном тексте выдаёт сразу.
    public static func fingerprint(of text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).uppercased()
    }

    /// Значение всегда в одну строку. Название трека приходит из тегов файла,
    /// то есть от кого угодно: перевод строки внутри него дорисовал бы отчёту
    /// собственные строки `Key` и `Signature` (D-012).
    private func field(_ name: String, _ value: String) -> String {
        let single =
            value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return name.padding(toLength: max(name.count, 12), withPad: " ", startingAt: 0) + " "
            + single
    }

    /// Килогерцы через POSIX: на русской локали `formatted()` даёт «44,1»,
    /// а отчёт должен читаться одинаково везде.
    static func khz(_ rate: Double) -> String {
        String(format: "%g", locale: Locale(identifier: "en_US_POSIX"), rate / 1000) + " kHz"
    }

    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
