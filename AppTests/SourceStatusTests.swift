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
