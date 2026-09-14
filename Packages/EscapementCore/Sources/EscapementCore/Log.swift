import Foundation
import os

/// Central logging facade. One subsystem, four categories (SPEC §9).
/// Real-time audio code must never log — see CLAUDE.md "Аудио — особый режим".
public enum Log {
    /// Matches PRODUCT_BUNDLE_IDENTIFIER in Config/Escapement.xcconfig.
    public static let subsystem = "com.dikairos.escapement"

    public static let audio = Logger(subsystem: subsystem, category: "audio")
    public static let library = Logger(subsystem: subsystem, category: "library")
    public static let network = Logger(subsystem: subsystem, category: "network")
    public static let ui = Logger(subsystem: subsystem, category: "ui")

    /// Ошибка для журнала без секретов. `NSError` из URL Loading System несёт
    /// в `userInfo` failing URL целиком — у Subsonic это `u`, `t` и `s`, то
    /// есть логин и материал авторизации; `localizedDescription` местами
    /// тоже цитирует адрес. Наружу уходят домен, код и хост, не больше.
    /// Свои Swift-ошибки (домен вида `Module.Type`) описывают себя сами и
    /// адресов не содержат.
    public static func describe(_ error: any Error) -> String {
        let nsError = error as NSError
        let foundation =
            nsError.domain.hasPrefix("NS") || nsError.domain.hasPrefix("k")
            || nsError.domain == NSURLErrorDomain
        guard foundation else { return String(describing: error) }
        let failing =
            (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL)
            ?? (nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String).flatMap {
                URL(string: $0)
            }
        var text = "\(nsError.domain) \(nsError.code)"
        if let host = failing?.host { text += " (\(host))" }
        return text
    }
}
