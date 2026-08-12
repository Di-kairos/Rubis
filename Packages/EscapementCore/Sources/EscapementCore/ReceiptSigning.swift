import CryptoKit
import Foundation

/// Подпись отчёта о тракте (D-012).
///
/// Ключ — Ed25519, свой у каждой установки; приватная половина живёт в связке
/// ключей машины, публичная печатается в самом отчёте. Что это доказывает:
/// отчёт не правили после выпуска, и два отчёта с одним ключом вышли из одной
/// установки. Чего не доказывает: что плеер не пересобран — ключ локальный, а
/// не «сертификат Rubis». Обещать больше было бы ровно тем враньём, против
/// которого написан отчёт.
public enum ReceiptSigning {

    /// Публичная половина в отчёте и подпись тела — обе base64.
    public struct Signature: Sendable, Equatable {
        public let publicKey: String
        public let value: String

        public init(publicKey: String, value: String) {
            self.publicKey = publicKey
            self.value = value
        }
    }

    public static func sign(_ body: String, with key: Curve25519.Signing.PrivateKey) throws
        -> Signature
    {
        let signature = try key.signature(for: Data(body.utf8))
        return Signature(
            publicKey: key.publicKey.rawRepresentation.base64EncodedString(),
            value: signature.base64EncodedString())
    }

    /// Проверка подписи: подпись, ключ и тело — как они лежат в тексте отчёта.
    public static func verify(body: String, signature: Signature) -> Bool {
        guard let keyData = Data(base64Encoded: signature.publicKey),
            let signatureData = Data(base64Encoded: signature.value),
            let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        else { return false }
        return key.isValidSignature(signatureData, for: Data(body.utf8))
    }

    /// Тот же публичный ключ в PEM — чтобы отчёт проверялся и без Rubis:
    /// `openssl pkeyutl -verify -pubin -inkey key.pem -rawin -in body.txt
    /// -sigfile sig.bin`. Ed25519 SubjectPublicKeyInfo — это фиксированные
    /// двенадцать байт заголовка и тридцать два байта ключа, разбирать ASN.1
    /// ради них не нужно.
    public static func pem(publicKey: String) -> String? {
        guard let raw = Data(base64Encoded: publicKey), raw.count == 32 else { return nil }
        let header = Data([
            0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00,
        ])
        let body = (header + raw).base64EncodedString()
        return "-----BEGIN PUBLIC KEY-----\n\(body)\n-----END PUBLIC KEY-----"
    }

    /// Разбор отчёта обратно на тело и подпись — обратная сторона
    /// `SignalPathReceipt.rendered(signedBy:)`. Тело берётся дословно: любой
    /// лишний пробел внутри него обязан ломать проверку.
    ///
    /// Подпись обязана быть последними двумя строками. Иначе к подписанному
    /// отчёту дописывался бы свой «вердикт» ниже подписи — текст врал бы, а
    /// проверка проходила.
    public static func parse(receipt text: String) -> (body: String, signature: Signature)? {
        // CRLF: отчёт ходит через чаты и редакторы, которые правят переводы
        // строк молча. Возвращаем ровно те байты, что подписывались.
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        guard lines.count > 2 else { return nil }
        let keyLine = lines[lines.count - 2]
        let signatureLine = lines[lines.count - 1]
        // Точное поле, а не «строка начинается на Key»: иначе трек «Key Largo»
        // сходил бы за строку ключа.
        guard keyLine.hasPrefix(SignalPathReceipt.keyField + " "),
            signatureLine.hasPrefix(SignalPathReceipt.signatureField + " ")
        else { return nil }
        return (
            lines[..<(lines.count - 2)].joined(separator: "\n"),
            Signature(publicKey: value(of: keyLine), value: value(of: signatureLine))
        )
    }

    private static func value(of line: String) -> String {
        String(line.drop(while: { $0 != " " })).trimmingCharacters(in: .whitespaces)
    }
}
