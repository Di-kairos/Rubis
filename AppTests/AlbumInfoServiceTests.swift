import EscapementCore
import Foundation
import Testing

@testable import Rubis_Music

/// Ворота одного запроса: тест решает, когда Wikipedia «ответит».
private actor RequestGate {
    private var held: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func hold() async {
        await withCheckedContinuation { continuation in
            held = continuation
            for waiter in waiters { waiter.resume() }
            waiters.removeAll()
        }
    }

    func waitUntilHeld() async {
        if held != nil { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        held?.resume()
        held = nil
    }
}

/// Хосты, к которым ходил транспорт, — по ним видно, был ли запрос писателю.
private actor HostLog {
    private(set) var hosts: [String] = []
    func note(_ host: String) { hosts.append(host) }
}

/// R07 (перепроверка аудита 13.09.2026): выключение заметок во время запроса
/// к Wikipedia не должно приводить к запросу писателю после промаха.
@MainActor
struct AlbumInfoServiceTests {
    private final class Permission: @unchecked Sendable {
        var allowed = true
    }

    private nonisolated static func miss() -> (Data, URLResponse) {
        let body = Data(#"{"pages":[]}"#.utf8)
        let url = URL(string: "https://en.wikipedia.org/")!
        return (
            body, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }

    @Test func switchingNotesOffDuringWikipediaStopsTheWriterRequest() async throws {
        let gate = RequestGate()
        let log = HostLog()
        let permission = Permission()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "album-info-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let ledgerFile = root.appendingPathComponent("ledger.json")
        let service = AlbumInfoService(
            ledger: NetworkLedger(fileURL: ledgerFile),
            transport: { request in
                let host = request.url?.host ?? ""
                await log.note(host)
                if host.hasSuffix("wikipedia.org") { await gate.hold() }
                return Self.miss()
            },
            permission: { permission.allowed },
            apiKeys: { _ in "test-key" },
            cacheRoot: root.appendingPathComponent("cache"))
        let album = Album(title: "Unknown Record", sortTitle: "unknown record", artistId: nil)
        var album2 = album
        album2.id = 42

        let fetch = Task { await service.info(for: album2) }
        await gate.waitUntilHeld()
        // Пользователь выключил заметки, пока Wikipedia ещё отвечала.
        permission.allowed = false
        await gate.release()
        let result = await fetch.value

        #expect(result == nil)
        let hosts = await log.hosts
        #expect(
            hosts.allSatisfy { $0.hasSuffix("wikipedia.org") }, "писателю запросов нет: \(hosts)")
    }

    @Test func withPermissionTheWriterIsAskedAfterAWikipediaMiss() async throws {
        let log = HostLog()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "album-info-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let service = AlbumInfoService(
            ledger: NetworkLedger(fileURL: root.appendingPathComponent("ledger.json")),
            transport: { request in
                await log.note(request.url?.host ?? "")
                return Self.miss()
            },
            permission: { true },
            apiKeys: { _ in "test-key" },
            cacheRoot: root.appendingPathComponent("cache"))
        var album = Album(title: "Unknown Record", sortTitle: "unknown record", artistId: nil)
        album.id = 43
        _ = await service.info(for: album)
        let hosts = await log.hosts
        // Контроль контрольного: тот же путь с разрешением доходит до писателя.
        #expect(hosts.contains { !$0.hasSuffix("wikipedia.org") }, "\(hosts)")
    }
}
