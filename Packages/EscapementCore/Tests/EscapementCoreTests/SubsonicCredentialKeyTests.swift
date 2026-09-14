import Foundation
import Testing

@testable import EscapementCore

/// R01: смена адреса не должна уносить только что сохранённый пароль.
struct SubsonicCredentialKeyTests {
    private func key(_ url: String, _ user: String = "dan") -> SubsonicCredentialKey {
        SubsonicCredentialKey(serverURL: url, username: user)
    }

    @Test func portPathSchemeAndSlashKeepTheSameRecord() {
        let old = key("https://music.example:4533")
        for changed in [
            "https://music.example:4534",  // порт
            "https://music.example:4533/music",  // путь
            "http://music.example:4533",  // схема
            "https://music.example:4533/",  // завершающий слеш
            "  https://music.example:4533  ",  // пробелы по краям
        ] {
            let new = key(changed)
            #expect(new == old, "\(changed) — та же запись связки")
            #expect(SubsonicCredentialKey.stale(old: old, new: new) == nil, "\(changed) — не удалять")
        }
    }

    @Test func otherHostOrUserIsADifferentRecord() {
        let old = key("https://music.example:4533")
        let otherHost = key("https://other.example:4533")
        let otherUser = key("https://music.example:4533", "mia")
        #expect(SubsonicCredentialKey.stale(old: old, new: otherHost) == old)
        #expect(SubsonicCredentialKey.stale(old: old, new: otherUser) == old)
    }

    @Test func noOldRecordOrUnparsableAddressDeletesNothing() {
        let new = key("https://music.example")
        #expect(SubsonicCredentialKey.stale(old: nil, new: new) == nil)
        #expect(SubsonicCredentialKey.stale(old: key("не адрес"), new: new) == nil)
    }
}
