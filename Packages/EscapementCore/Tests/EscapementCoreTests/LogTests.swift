import EscapementCore
import Foundation
import Testing

struct LogTests {
    @Test func describeDropsTheAuthorisedURL() {
        let secret = URL(
            string: "https://music.example.com/rest/download?u=di&t=deadbeef&s=salt&id=1")!
        let error = NSError(
            domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
            userInfo: [
                NSURLErrorFailingURLErrorKey: secret,
                NSLocalizedDescriptionKey: "timed out \(secret)",
            ])
        let text = Log.describe(error)
        #expect(text.contains("music.example.com"))
        #expect(!text.contains("deadbeef"))
        #expect(!text.contains("u=di"))
        #expect(!text.contains("salt"))
    }

    @Test func describeKeepsOwnErrorsReadable() {
        enum Local: Error { case refused(code: Int) }
        #expect(Log.describe(Local.refused(code: 40)).contains("refused"))
    }

    @Test func subsystemMatchesBundleIdentifier() {
        #expect(Log.subsystem == "com.dikairos.escapement")
    }
}
