import AppKit

/// Пробел и стрелки без модификаторов — пункты меню (Play/Pause, Seek), а
/// меню видит нажатие раньше текстового поля. Флаги «сейчас печатают» на
/// каждое поле не масштабируются: URL, логин, пароль и ключ API в Settings в
/// них не входили, и пробел в адресе сервера ставил музыку на паузу.
/// Решение принимается по настоящему первому ответчику ключевого окна: если
/// это редактор текста, событие уходит ему напрямую, минуя меню.
@MainActor
final class TextFieldKeyGuard {
    private var monitor: Any?

    /// Space, ←, →.
    private static let guardedKeyCodes: Set<UInt16> = [49, 123, 124]

    init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard Self.guardedKeyCodes.contains(event.keyCode),
                event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
                let editor = NSApp.keyWindow?.firstResponder as? NSTextView
            else { return event }
            editor.keyDown(with: event)
            return nil
        }
    }

    /// Монитор снимается явно; объект живёт вместе с `AppEnvironment` — до
    /// конца процесса, так что вызов нужен только тестам и симметрии.
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
