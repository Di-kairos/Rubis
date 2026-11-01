import Testing

@testable import Rubis_Music

/// Имя нового плейлиста спрашивается до создания: пустое имя — отказ,
/// плейлиста с именем-заглушкой не остаётся.
struct PlaylistNameTests {
    @Test func emptyDraftCreatesNothing() {
        #expect(AppEnvironment.playlistName(from: "") == nil)
    }

    @Test func whitespaceOnlyDraftCreatesNothing() {
        #expect(AppEnvironment.playlistName(from: "  \n ") == nil)
    }

    @Test func edgeWhitespaceIsTrimmed() {
        #expect(AppEnvironment.playlistName(from: "  Night Drive  ") == "Night Drive")
    }

    @Test func innerSpacingSurvives() {
        #expect(AppEnvironment.playlistName(from: "Night  Drive") == "Night  Drive")
    }
}
