import CryptoKit
import Foundation

/// Отпечаток содержимого аудиофайла для доказательства тождества (F03).
///
/// FLAC хранит в STREAMINFO MD5 несжатого PCM — это подлинный отпечаток
/// звука, не зависящий от тегов. У остальных форматов такого поля нет: берём
/// SHA-256 трёх окон по 64 КиБ (начало, середина, конец) плюс размер файла —
/// два разных рипа с одинаковой тишиной в начале так не совпадут. Префикс
/// схемы в строке не даёт перепутать отпечатки разных схем.
/// ponytail: окна, а не весь файл — полный хеш WAV/DSF читал бы гигабайты
/// на первом скане; переходить на полный, если всплывёт коллизия.
enum ContentHash {
    static let windowLength = 64 * 1024

    static func compute(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: windowLength), !head.isEmpty,
            let size = try? handle.seekToEnd()
        else { return nil }
        if let md5 = flacStreamInfoMD5(head) { return "md5:\(md5)" }
        var hasher = SHA256()
        hasher.update(data: head)
        let window = UInt64(windowLength)
        if size > window {
            let tail = size - window
            for offset in Set([tail / 2, tail]).sorted() where offset > 0 {
                guard (try? handle.seek(toOffset: offset)) != nil,
                    let chunk = try? handle.read(upToCount: windowLength)
                else { return nil }
                hasher.update(data: chunk)
            }
        }
        withUnsafeBytes(of: size.littleEndian) { hasher.update(bufferPointer: $0) }
        return "sha256:" + hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// MD5 из STREAMINFO: «fLaC», заголовок блока (4 байта, тип 0), в блоке
    /// 34 байта, MD5 — последние 16. Энкодер, не посчитавший MD5, пишет нули —
    /// тогда отпечатка нет и файл идёт по общей схеме.
    static func flacStreamInfoMD5(_ head: Data) -> String? {
        let start = head.startIndex
        guard head.count >= 42, head[start..<start + 4].elementsEqual("fLaC".utf8),
            head[start + 4] & 0x7F == 0
        else { return nil }
        let md5 = head[(start + 26)..<(start + 42)]
        guard md5.contains(where: { $0 != 0 }) else { return nil }
        return md5.map { String(format: "%02x", $0) }.joined()
    }
}
