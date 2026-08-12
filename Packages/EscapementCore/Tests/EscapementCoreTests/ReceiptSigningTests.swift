import CryptoKit
import Foundation
import Testing

@testable import EscapementCore

struct ReceiptSigningTests {

    private func receipt() -> SignalPathReceipt {
        SignalPathReceipt(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            appVersion: "0.9.0 (27)", track: "Agos — Sebastian Plano", codec: "flac",
            sourceRate: 96000, sourceBits: 24, channels: 2, deviceName: "FiiO QX13",
            deviceTransport: "USB", deviceRate: 96000, exclusive: true,
            mixingDisabled: true, dsd: nil, fallback: "Nearest family multiple",
            bitPerfect: true)
    }

    @Test func signedReceiptVerifiesAgainstItsOwnKey() throws {
        let key = Curve25519.Signing.PrivateKey()
        let text = try receipt().rendered(signedBy: key)
        let parsed = try #require(ReceiptSigning.parse(receipt: text))
        #expect(ReceiptSigning.verify(body: parsed.body, signature: parsed.signature))
        #expect(parsed.signature.publicKey == key.publicKey.rawRepresentation.base64EncodedString())
    }

    @Test func editedNumberBreaksTheSignature() throws {
        let key = Curve25519.Signing.PrivateKey()
        let text = try receipt().rendered(signedBy: key)
        // Ровно тот подлог, ради которого подпись и появилась: чужой отчёт,
        // в котором «96 kHz» дорисовано поверх ресемпла.
        let tampered = text.replacingOccurrences(of: "24 bit", with: "32 bit")
        let parsed = try #require(ReceiptSigning.parse(receipt: tampered))
        #expect(!ReceiptSigning.verify(body: parsed.body, signature: parsed.signature))
    }

    @Test func signatureFromAnotherInstallDoesNotPass() throws {
        let text = try receipt().rendered(signedBy: Curve25519.Signing.PrivateKey())
        let parsed = try #require(ReceiptSigning.parse(receipt: text))
        let stranger = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
            .base64EncodedString()
        let swapped = ReceiptSigning.Signature(
            publicKey: stranger, value: parsed.signature.value)
        #expect(!ReceiptSigning.verify(body: parsed.body, signature: swapped))
    }

    @Test func bodyIsWhatTheReaderSees() throws {
        let key = Curve25519.Signing.PrivateKey()
        let text = try receipt().rendered(signedBy: key)
        let parsed = try #require(ReceiptSigning.parse(receipt: text))
        #expect(parsed.body == receipt().body())
        #expect(parsed.body.hasSuffix("Bit-perfect — the file reaches the DAC unchanged"))
        #expect(!parsed.body.contains("Signature"))
    }

    @Test func unsignedReceiptStillCarriesAFingerprint() {
        let text = receipt().rendered()
        #expect(text.contains("Fingerprint"))
        #expect(ReceiptSigning.parse(receipt: text) == nil)
    }

    @Test func publicKeyConvertsToPemForOpenssl() throws {
        let key = Curve25519.Signing.PrivateKey()
        let base64 = key.publicKey.rawRepresentation.base64EncodedString()
        let pem = try #require(ReceiptSigning.pem(publicKey: base64))
        #expect(pem.hasPrefix("-----BEGIN PUBLIC KEY-----\n"))
        #expect(pem.hasSuffix("\n-----END PUBLIC KEY-----"))
        // 12 байт заголовка SubjectPublicKeyInfo + 32 байта ключа.
        let body = pem.components(separatedBy: "\n")[1]
        #expect(Data(base64Encoded: body)?.count == 44)
    }

    @Test func textAppendedBelowTheSignatureIsNotAccepted() throws {
        let key = Curve25519.Signing.PrivateKey()
        let text = try receipt().rendered(signedBy: key)
        // Подпись стоит на месте, а ниже дописан свой вердикт: если бы разбор
        // искал первую строку «Key», подделка прошла бы проверку.
        let appended = text + "\nVERDICT      Bit-perfect — trust me"
        #expect(ReceiptSigning.parse(receipt: appended) == nil)
    }

    @Test func newlinesInTrackTitleCannotForgeSignatureFields() throws {
        // Название приходит из тегов файла — то есть от кого угодно.
        var forged = receipt()
        forged.track = "Agos\nKey          AAAA\nSignature    BBBB"
        let text = try forged.rendered(signedBy: Curve25519.Signing.PrivateKey())
        let parsed = try #require(ReceiptSigning.parse(receipt: text))
        #expect(ReceiptSigning.verify(body: parsed.body, signature: parsed.signature))
        #expect(parsed.signature.publicKey != "AAAA")
        #expect(parsed.body.contains("Agos Key          AAAA Signature    BBBB"))
    }

    @Test func aTrackCalledKeyLargoDoesNotBreakTheParser() throws {
        var named = receipt()
        named.track = "Key Largo"
        let text = try named.rendered(signedBy: Curve25519.Signing.PrivateKey())
        let parsed = try #require(ReceiptSigning.parse(receipt: text))
        #expect(ReceiptSigning.verify(body: parsed.body, signature: parsed.signature))
    }

    @Test func receiptSurvivesCrlfAndATrailingNewline() throws {
        let key = Curve25519.Signing.PrivateKey()
        let text = try receipt().rendered(signedBy: key)
        // Путь «скопировал в чат — сохранил в файл» дорисовывает и то, и другое.
        let mangled = text.replacingOccurrences(of: "\n", with: "\r\n") + "\r\n"
        let parsed = try #require(ReceiptSigning.parse(receipt: mangled))
        #expect(ReceiptSigning.verify(body: parsed.body, signature: parsed.signature))
    }

    @Test func garbageIsNotAReceipt() {
        #expect(ReceiptSigning.pem(publicKey: "not base64 at all") == nil)
        #expect(ReceiptSigning.parse(receipt: "hello") == nil)
    }
}
