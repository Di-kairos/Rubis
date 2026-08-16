import Foundation
import Testing

@testable import MusicLibrary

struct CueSheetTests {

    private let kindOfBlue = """
        REM GENRE "Jazz"
        REM DATE 1959
        PERFORMER "Miles Davis"
        TITLE "Kind of Blue"
        FILE "Kind of Blue.flac" WAVE
          TRACK 01 AUDIO
            TITLE "So What"
            PERFORMER "Miles Davis"
            INDEX 00 00:00:00
            INDEX 01 00:33:00
          TRACK 02 AUDIO
            TITLE "Freddie Freeloader"
            INDEX 01 09:22:15
          TRACK 03 AUDIO
            TITLE "Blue in Green"
            INDEX 01 19:00:00
        """

    @Test func readsAlbumHeader() throws {
        let sheet = try #require(CueSheet.parse(kindOfBlue))
        #expect(sheet.title == "Kind of Blue")
        #expect(sheet.performer == "Miles Davis")
        #expect(sheet.date == 1959)
        #expect(sheet.genre == "Jazz")
        #expect(sheet.files.count == 1)
        #expect(sheet.files[0].name == "Kind of Blue.flac")
    }

    @Test func trackStartsAtIndexOneNotAtThePregap() throws {
        let sheet = try #require(CueSheet.parse(kindOfBlue))
        // INDEX 00 — предзазор; играть с него значит начать с тишины.
        // 00:33:00 — тридцать три секунды, а не тридцать три кадра.
        #expect(sheet.tracks[0].start == 33)
    }

    @Test func framesAreSeventyFifthsOfASecond() {
        #expect(CueSheet.time("00:00:00") == 0)
        #expect(CueSheet.time("09:22:15") == 562.2)
        #expect(CueSheet.time("bogus") == nil)
    }

    @Test func eachTrackEndsWhereTheNextBegins() throws {
        let sheet = try #require(CueSheet.parse(kindOfBlue))
        #expect(sheet.tracks[0].end == sheet.tracks[1].start)
        #expect(sheet.tracks[1].end == 1140)
        // Последняя дорожка играет до конца файла — длину знает только декодер.
        #expect(sheet.tracks[2].end == nil)
    }

    @Test func trackTitleFallsBackToNothingRatherThanTheAlbumTitle() throws {
        let sheet = try #require(
            CueSheet.parse(
                """
                TITLE "Album"
                FILE "a.flac" WAVE
                  TRACK 01 AUDIO
                    INDEX 01 00:00:00
                """))
        #expect(sheet.title == "Album")
        #expect(sheet.tracks[0].title == nil)
        #expect(sheet.tracks[0].performer == nil)
    }

    @Test func onePerTrackFileLayoutIsAlsoACueSheet() throws {
        // Такие листы делает EAC в режиме «файл на дорожку»: границ нет,
        // каждая дорожка — свой файл целиком.
        let sheet = try #require(
            CueSheet.parse(
                """
                TITLE "Split"
                FILE "01 - One.flac" WAVE
                  TRACK 01 AUDIO
                    TITLE "One"
                    INDEX 01 00:00:00
                FILE "02 - Two.flac" WAVE
                  TRACK 02 AUDIO
                    TITLE "Two"
                    INDEX 01 00:00:00
                """))
        #expect(sheet.files.count == 2)
        #expect(sheet.files[0].tracks[0].end == nil)
        #expect(sheet.files[1].tracks[0].start == 0)
    }

    @Test func dataTracksAreSkipped() throws {
        // Смешанный диск: дорожка данных не играется и не должна попасть
        // в библиотеку, сдвинув нумерацию.
        let sheet = try #require(
            CueSheet.parse(
                """
                FILE "mixed.flac" WAVE
                  TRACK 01 AUDIO
                    INDEX 01 00:00:00
                  TRACK 02 MODE1/2352
                    INDEX 01 05:00:00
                """))
        #expect(sheet.tracks.count == 1)
        #expect(sheet.tracks[0].number == 1)
    }

    @Test func trackWithoutIndexIsDropped() throws {
        let sheet = try #require(
            CueSheet.parse(
                """
                FILE "a.flac" WAVE
                  TRACK 01 AUDIO
                    TITLE "No index"
                  TRACK 02 AUDIO
                    INDEX 01 01:00:00
                """))
        #expect(sheet.tracks.count == 1)
        #expect(sheet.tracks[0].number == 2)
    }

    @Test func unquotedFileNameIsAccepted() throws {
        let sheet = try #require(
            CueSheet.parse(
                """
                FILE album.flac WAVE
                  TRACK 01 AUDIO
                    INDEX 01 00:00:00
                """))
        #expect(sheet.files[0].name == "album.flac")
    }

    @Test func datesComeInSeveralShapes() throws {
        func date(_ line: String) -> Int? {
            CueSheet.parse(
                """
                \(line)
                FILE "a.flac" WAVE
                  TRACK 01 AUDIO
                    INDEX 01 00:00:00
                """)?.date
        }
        #expect(date("REM DATE 1959") == 1959)
        #expect(date("REM DATE \"1971-05-03\"") == 1971)
        #expect(date("REM DATE Recorded 1967") == 1967)
        #expect(date("REM DATE unknown") == nil)
    }

    @Test func windowsLineEndingsAndTrailingSpacesDoNotMatter() throws {
        let sheet = try #require(
            CueSheet.parse("FILE \"a.flac\" WAVE\r\n  TRACK 01 AUDIO  \r\n INDEX 01 00:10:00\r\n"))
        #expect(sheet.tracks[0].start == 10)
    }

    @Test func textWithoutAFileIsNotACueSheet() {
        #expect(CueSheet.parse("TITLE \"Nothing here\"") == nil)
        #expect(CueSheet.parse("") == nil)
    }

    @Test func cyrillicInWindows1251IsReadFromDisk() throws {
        let text = """
            PERFORMER "Аквариум"
            TITLE "Русский альбом"
            FILE "album.flac" WAVE
              TRACK 01 AUDIO
                TITLE "Никита Рязанский"
                INDEX 01 00:00:00
            """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cp1251-\(UUID().uuidString).cue")
        try #require(text.data(using: .windowsCP1251)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let sheet = try #require(try CueSheet.read(contentsOf: url))
        #expect(sheet.performer == "Аквариум")
        #expect(sheet.tracks[0].title == "Никита Рязанский")
    }

    @Test func utf8WithBomIsReadFromDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bom-\(UUID().uuidString).cue")
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(
            Data(
                """
                TITLE "With BOM"
                FILE "a.flac" WAVE
                  TRACK 01 AUDIO
                    INDEX 01 00:00:00
                """.utf8))
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let sheet = try #require(try CueSheet.read(contentsOf: url))
        #expect(sheet.title == "With BOM")
    }

    /// Рип «дорожка в файл»: EAC пишет предзазор концом прошлого файла
    /// (INDEX 00), а начало дорожки — уже после строки FILE.
    @Test func aTrackSurvivesTheFileBoundary() throws {
        let sheet = try #require(
            CueSheet.parse(
                """
                PERFORMER "4hero"
                TITLE "Creating Patterns"
                FILE "01. Conceptions.wav" WAVE
                  TRACK 01 AUDIO
                    TITLE "Conceptions"
                    INDEX 01 00:00:00
                  TRACK 02 AUDIO
                    TITLE "Time"
                    INDEX 00 05:37:46
                FILE "02. Time.wav" WAVE
                    INDEX 01 00:00:00
                """))
        #expect(sheet.files.count == 2)
        #expect(sheet.files.map(\.name) == ["01. Conceptions.wav", "02. Time.wav"])
        #expect(sheet.tracks.map(\.title) == ["Conceptions", "Time"])
        #expect(sheet.tracks.map(\.number) == [1, 2])
        // Каждый файл целиком свой: резать нечего, границ нет.
        #expect(sheet.tracks.allSatisfy { $0.start == 0 && $0.end == nil })
    }
}
