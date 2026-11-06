import Testing

@testable import Rubis_Music

/// Ошибка скана папки видна пользователю строкой, а не только в логе.
struct SourceStatusTests {
    @Test func noFailuresNoLine() {
        #expect(AppEnvironment.sourceStatus(unreadable: [:]) == nil)
    }

    @Test func oneFolderIsNamed() {
        let line = AppEnvironment.sourceStatus(unreadable: ["a": "Collective Of Sound"])
        #expect(line == "Collective Of Sound can't be read — add the folder again")
    }

    @Test func severalFoldersAreCounted() {
        let line = AppEnvironment.sourceStatus(unreadable: ["a": "A", "b": "B"])
        #expect(line == "2 folders can't be read — add them again")
    }
}

/// Строка о молчащем сервере и её судьба после удаления источника.
struct ServerStatusTests {
    @Test func oneServerIsNamed() {
        #expect(AppEnvironment.serverStatus(offline: ["s": "localhost"]) == "localhost is offline")
    }

    @Test func severalServersAreCounted() {
        let line = AppEnvironment.serverStatus(offline: ["a": "A", "b": "B"])
        #expect(line == "2 servers are offline")
    }

    @Test func removedSourceDropsItsLine() {
        let kept = AppEnvironment.pruned(["gone": "localhost", "here": "Navidrome"], to: ["here"])
        #expect(kept == ["here": "Navidrome"])
        #expect(
            AppEnvironment.serverStatus(
                offline: AppEnvironment.pruned(["gone": "localhost"], to: [])) == nil)
    }
}
