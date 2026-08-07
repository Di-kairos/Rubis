import AppKit
import EscapementCore

/// Глобальные медиа-клавиши (TASKS фаза 7): работают, когда активно чужое
/// приложение. Без них медиа-клавиши всё равно ходят через
/// `MPRemoteCommandCenter`, но только пока Now Playing принадлежит нам.
///
/// Accessibility спрашиваем ТОЛЬКО при включении функции — не на старте
/// приложения и не «на всякий случай».
@MainActor
final class GlobalMediaKeys {
    private let env: AppEnvironment
    private var monitor: Any?

    init(env: AppEnvironment) {
        self.env = env
    }

    var isEnabled: Bool { monitor != nil }

    /// Уже выданное разрешение — проверка без диалога.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Показывает системный диалог Accessibility. Возвращает состояние на
    /// момент вызова: разрешение обычно выдают уже после, в System Settings.
    @discardableResult
    static func requestTrust() -> Bool {
        // Строкой, а не через `kAXTrustedCheckOptionPrompt`: та константа —
        // глобальная `var` и под strict concurrency недоступна. Значение
        // ключа зафиксировано в API и не меняется.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Включение без разрешения бессмысленно: монитор молча не получал бы
    /// событий. Возвращает, удалось ли включить.
    ///
    /// Снятие монитора — только отсюда: `deinit` под strict concurrency не
    /// имеет права трогать это состояние. Объект живёт столько же, сколько
    /// `AppEnvironment`, поэтому утечки монитора не возникает.
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        guard enabled else {
            monitor.map(NSEvent.removeMonitor)
            monitor = nil
            return false
        }
        guard monitor == nil else { return true }
        guard Self.isTrusted else { return false }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) {
            [weak self] event in
            // Медиа-клавиши приходят системными событиями подтипа 8.
            guard event.subtype.rawValue == 8,
                let key = MediaKey.from(data1: event.data1)
            else { return }
            MainActor.assumeIsolated { self?.handle(key) }
        }
        return monitor != nil
    }

    private func handle(_ key: MediaKey) {
        switch key {
        case .playPause: env.togglePlayPause()
        case .next: env.next()
        case .previous: env.previous()
        }
    }
}
