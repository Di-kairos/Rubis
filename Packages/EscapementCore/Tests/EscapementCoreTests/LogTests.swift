import EscapementCore
import Testing

struct LogTests {
    @Test func subsystemMatchesBundleIdentifier() {
        #expect(Log.subsystem == "com.dikairos.escapement")
    }
}
