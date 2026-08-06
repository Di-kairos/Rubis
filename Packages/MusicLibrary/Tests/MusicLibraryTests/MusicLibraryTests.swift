import MusicLibrary
import Testing

struct MusicLibraryTests {
    @Test func linksAgainstCore() {
        #expect(MusicLibraryInfo.logSubsystem == "com.dikairos.escapement")
    }
}
