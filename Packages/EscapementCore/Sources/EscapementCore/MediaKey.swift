import Foundation

/// Медиа-клавиша клавиатуры, разобранная из системного события.
///
/// AppKit отдаёт такие нажатия одним `NSEvent` типа `.systemDefined` с
/// подтипом 8, где всё упаковано в `data1`. Разбор — чистая арифметика,
/// поэтому живёт здесь и проверяется тестом, а не глазами на живой клавиатуре.
public enum MediaKey: Equatable, Sendable {
    case playPause
    case next
    case previous

    /// Коды из IOKit (`NX_KEYTYPE_*`), которые нас интересуют.
    private static let playPauseCode = 16
    private static let nextCode = 19
    private static let previousCode = 20

    /// nil, если это не медиа-клавиша или это отпускание — реагируем только
    /// на нажатие, иначе каждое нажатие срабатывало бы дважды.
    public static func from(data1: Int) -> MediaKey? {
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let keyFlags = data1 & 0x0000_FFFF
        let isKeyDown = ((keyFlags & 0xFF00) >> 8) == 0x0A
        guard isKeyDown else { return nil }
        switch keyCode {
        case playPauseCode: return .playPause
        case nextCode: return .next
        case previousCode: return .previous
        default: return nil
        }
    }
}
