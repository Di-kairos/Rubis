import PlaybackEngine
import Testing

struct PlaybackEngineTests {
    @Test func linksAgainstCore() {
        #expect(PlaybackEngineInfo.logSubsystem == "com.dikairos.escapement")
    }
}
