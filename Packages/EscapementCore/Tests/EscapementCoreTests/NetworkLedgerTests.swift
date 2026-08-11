import Foundation
import Testing

@testable import EscapementCore

struct NetworkLedgerTests {

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-\(UUID().uuidString)/net.json")
    }

    private func event(
        _ host: String, _ purpose: String = "Album notes", ok: Bool = true, bytes: Int = 10,
        secondsAgo: TimeInterval = 0
    ) -> NetworkEvent {
        NetworkEvent(
            date: Date(timeIntervalSince1970: 1_000_000 - secondsAgo), host: host,
            purpose: purpose, succeeded: ok, bytes: bytes)
    }

    @Test func summaryGroupsByHostAndCountsFailures() {
        let summary = NetworkLedger.summarize([
            event("en.wikipedia.org", secondsAgo: 30),
            event("en.wikipedia.org", ok: false, bytes: 0),
            event("api.anthropic.com", "Album notes", bytes: 900),
        ])

        #expect(summary.count == 2)
        let wiki = try? #require(summary.first)
        #expect(wiki?.host == "en.wikipedia.org")
        #expect(wiki?.count == 2)
        #expect(wiki?.failures == 1)
        #expect(wiki?.bytes == 10)
        #expect(wiki?.last == Date(timeIntervalSince1970: 1_000_000))
        #expect(summary.last?.host == "api.anthropic.com")
    }

    @Test func oneHostWithSeveralPurposesListsThemOnce() {
        let summary = NetworkLedger.summarize([
            event("raw.githubusercontent.com", "Update check"),
            event("raw.githubusercontent.com", "Update check"),
            event("raw.githubusercontent.com", "Album notes"),
        ])
        #expect(summary.first?.purposes == ["Album notes", "Update check"])
    }

    @Test func emptyLedgerSummarisesToNothing() {
        #expect(NetworkLedger.summarize([]).isEmpty)
    }

    @Test func recordingSurvivesReopening() async {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let ledger = NetworkLedger(fileURL: file)
        await ledger.record(
            host: "en.wikipedia.org", purpose: "Album notes", succeeded: true, bytes: 42)

        let reopened = NetworkLedger(fileURL: file)
        let events = await reopened.events()
        #expect(events.count == 1)
        #expect(events.first?.host == "en.wikipedia.org")
        #expect(events.first?.bytes == 42)
    }

    @Test func oldestEntriesFallOffTheLimit() async {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let ledger = NetworkLedger(fileURL: file, limit: 3)
        for index in 0..<5 {
            await ledger.record(
                host: "host-\(index)", purpose: "Album notes", succeeded: true, bytes: 1)
        }
        let events = await ledger.events()
        #expect(events.count == 3)
        #expect(events.map(\.host) == ["host-2", "host-3", "host-4"])
    }

    @Test func clearingLeavesNothingBehind() async {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let ledger = NetworkLedger(fileURL: file)
        await ledger.record(
            host: "api.deepseek.com", purpose: "Album notes", succeeded: true, bytes: 5)
        await ledger.clear()

        #expect(await ledger.events().isEmpty)
        #expect(await NetworkLedger(fileURL: file).events().isEmpty)
    }

    @Test func requestWithoutHostIsNotRecorded() async {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let ledger = NetworkLedger(fileURL: file)
        await ledger.record(host: "", purpose: "Album notes", succeeded: true, bytes: 1)
        #expect(await ledger.events().isEmpty)
    }
}
