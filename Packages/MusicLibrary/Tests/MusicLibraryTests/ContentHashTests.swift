import Foundation
import Testing

@testable import MusicLibrary

struct ContentHashTests {
    /// Минимальный FLAC: «fLaC» + заголовок STREAMINFO (последний блок, тип 0,
    /// 34 байта) + тело, где последние 16 байт — MD5.
    private func flac(md5: [UInt8]) -> Data {
        var data = Data("fLaC".utf8)
        data.append(contentsOf: [0x80, 0x00, 0x00, 0x22])
        data.append(contentsOf: [UInt8](repeating: 0x11, count: 18))
        data.append(contentsOf: md5)
        data.append(contentsOf: [UInt8](repeating: 0xAB, count: 100))
        return data
    }

    @Test func flacTakesStreamInfoMD5() throws {
        let md5 = (0..<16).map { UInt8($0 + 1) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "hash-\(UUID()).flac")
        defer { try? FileManager.default.removeItem(at: url) }
        try flac(md5: md5).write(to: url)
        #expect(ContentHash.compute(url: url) == "md5:0102030405060708090a0b0c0d0e0f10")
    }

    @Test func flacWithoutMD5FallsBackToHead() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "hash-\(UUID()).flac")
        defer { try? FileManager.default.removeItem(at: url) }
        try flac(md5: [UInt8](repeating: 0, count: 16)).write(to: url)
        #expect(ContentHash.compute(url: url)?.hasPrefix("sha256:") == true)
    }

    @Test func sampledHashSeesSizeHeadMiddleAndTail() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hash-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func write(_ name: String, _ bytes: [UInt8]) throws -> String? {
            let url = dir.appendingPathComponent(name)
            try Data(bytes).write(to: url)
            return ContentHash.compute(url: url)
        }
        // Четыре окна с лишним: голова, середина и хвост не пересекаются.
        let base = [UInt8](repeating: 7, count: ContentHash.windowLength * 4 + 10)
        let same = try write("a.wav", base)
        #expect(same == (try write("b.wav", base)))
        var longer = base
        longer.append(9)
        #expect(same != (try write("c.wav", longer)), "size is part of the fingerprint")
        var head = base
        head[0] = 8
        #expect(same != (try write("d.wav", head)))
        var middle = base
        middle[base.count / 2] = 8
        #expect(same != (try write("e.wav", middle)), "same head, different middle")
        var tail = base
        tail[base.count - 1] = 8
        #expect(same != (try write("f.wav", tail)), "same head, different tail")
        var short = [UInt8](repeating: 7, count: 100)
        let small = try write("g.wav", short)
        short[99] = 8
        #expect(small != (try write("h.wav", short)), "files under one window hash whole")
        #expect(try write("i.wav", []) == nil)
    }
}
