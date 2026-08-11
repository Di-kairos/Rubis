import EscapementCore
import Foundation
import Testing

@testable import SubsonicKit

struct SubsonicCatalogTests {

    private func song(
        id: String = "so-1", title: String = "Sleep", suffix: String? = "flac",
        contentType: String? = nil, rate: Int? = 44100, bits: Int? = 24, channels: Int? = 2,
        duration: Int? = 214
    ) -> SubsonicSong {
        let json = """
            {"id":"\(id)","title":"\(title)","album":"Eternal","artist":"All India Radio",
            "albumId":"al-1","artistId":"ar-1","coverArt":"al-1","track":1,"discNumber":1,
            "year":2019,"duration":\(duration.map(String.init) ?? "null"),"size":12345,
            \(suffix.map { "\"suffix\":\"\($0)\"," } ?? "")
            \(contentType.map { "\"contentType\":\"\($0)\"," } ?? "")
            "bitRate":1000
            \(rate.map { ",\"samplingRate\":\($0)" } ?? "")
            \(bits.map { ",\"bitDepth\":\($0)" } ?? "")
            \(channels.map { ",\"channelCount\":\($0)" } ?? "")}
            """
        // swift-format-ignore: NeverForceUnwrap — фикстура теста, не продакшн.
        return try! JSONDecoder().decode(SubsonicSong.self, from: Data(json.utf8))
    }

    @Test func trackCarriesTheRemoteIdAndNoPath() {
        let track = SubsonicCatalog.track(
            from: song(), sourceId: "src-1", artistId: 7, albumId: 3)
        #expect(track.remoteId == "so-1")
        #expect(track.relativePath == nil)
        #expect(track.sourceId == "src-1")
        #expect(track.artistId == 7)
        #expect(track.albumId == 3)
        #expect(track.duration == 214)
        #expect(track.sampleRate == 44100)
        #expect(track.bitDepth == 24)
    }

    @Test func oldServerLeavesTheFormatUnknownInsteadOfGuessing() {
        // Без расширений OpenSubsonic частота неизвестна. Ноль честнее, чем
        // выдуманные 44100: на формате стоит весь контракт §4.
        let track = SubsonicCatalog.track(
            from: song(rate: nil, bits: nil, channels: nil), sourceId: "src-1",
            artistId: nil, albumId: nil)
        #expect(track.sampleRate == 0)
        #expect(track.bitDepth == nil)
        #expect(track.channels == 2)
    }

    @Test func codecComesFromSuffixThenContentType() {
        #expect(SubsonicCatalog.codec(for: song(suffix: "FLAC")) == "flac")
        #expect(
            SubsonicCatalog.codec(for: song(suffix: nil, contentType: "audio/mpeg")) == "mpeg")
        #expect(SubsonicCatalog.codec(for: song(suffix: nil, contentType: nil)) == "unknown")
    }

    @Test func emptyTitleDoesNotProduceANamelessRow() {
        let track = SubsonicCatalog.track(
            from: song(title: "  "), sourceId: "src-1", artistId: nil, albumId: nil)
        #expect(track.title == "Untitled")
    }

    @Test func albumGetsASortTitleTheSameWayLocalOnesDo() {
        let json = """
            {"id":"al-9","name":"The Köln Concert","artist":"Keith Jarrett",
            "artistId":"ar-9","year":1975}
            """
        // swift-format-ignore: NeverForceUnwrap — фикстура теста.
        let remote = try! JSONDecoder().decode(SubsonicAlbum.self, from: Data(json.utf8))
        let album = SubsonicCatalog.album(from: remote, artistId: 4)
        #expect(album.title == "The Köln Concert")
        #expect(album.sortTitle == "koln concert")
        #expect(album.albumArtist == "Keith Jarrett")
        #expect(album.year == 1975)
    }

    @Test func diffAddsWhatIsNewAndRemovesWhatTheServerDropped() {
        let result = SubsonicCatalog.diff(
            remoteIds: ["a", "b", "c"], localIds: ["b", "d"])
        #expect(result.added == ["a", "c"])
        #expect(result.removed == ["d"])
    }

    @Test func diffOfAnEmptyServerRemovesEverything() {
        // Пустой ответ — не повод стереть библиотеку молча; решение принимает
        // вызывающий, но сам расчёт обязан быть честным.
        let result = SubsonicCatalog.diff(remoteIds: [], localIds: ["a", "b"])
        #expect(result.added.isEmpty)
        #expect(result.removed == ["a", "b"])
    }
}
