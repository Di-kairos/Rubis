import SubsonicKit
import Testing

struct SubsonicKitTests {
    @Test func linksAgainstCore() {
        #expect(SubsonicKitInfo.logSubsystem == "com.dikairos.escapement")
    }
}
