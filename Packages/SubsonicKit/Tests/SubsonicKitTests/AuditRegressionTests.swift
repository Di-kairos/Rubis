import Foundation
import Testing

@testable import SubsonicKit

struct AuditRegressionTests {
    @Test func sameIdOnAnotherServerMustFetchOtherBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "audit-cache-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try StreamCache(root: root) { url in
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString)
            try Data((url.host ?? "").utf8).write(to: tmp)
            return tmp
        }
        let first = try #require(URL(string: "https://server-a.example/rest/download"))
        let second = try #require(URL(string: "https://server-b.example/rest/download"))
        _ = try await cache.file(remoteId: "123", codec: "flac", from: first)
        let file = try await cache.file(remoteId: "123", codec: "flac", from: second)
        let bytes = try String(contentsOf: file, encoding: .utf8)
        print("AUDIT second server returned: \(bytes)")
        #expect(bytes == "server-b.example")
    }
    @Test func serverURLMustRejectUnsupportedSchemesAndUserInfo() throws {
        #expect(throws: SubsonicError.invalidServerURL) {
            _ = try SubsonicClient(
                serverURL: "ftp://example.com", username: "test", password: "test")
        }
        #expect(throws: SubsonicError.invalidServerURL) {
            _ = try SubsonicClient(
                serverURL: "https://test:secret@example.com", username: "test", password: "test")
        }
    }
}
