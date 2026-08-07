import AppKit
import DesignSystem
import SwiftUI

/// Опциональная иконка в меню-баре (SPEC §7.5): текущий трек и транспорт без
/// поднятия главного окна.
///
/// Сделано на `NSStatusItem`, а не на SwiftUI `MenuBarExtra`: со сценой
/// `MenuBarExtra` в иерархии главное окно перестаёт подниматься при запуске —
/// приложение стартует без единого окна (проверено на macOS 15, запуск и через
/// LaunchServices, и напрямую). Статус-айтем этим не грозит.
@MainActor
final class MenuBarPresence {
    private let env: AppEnvironment
    private var item: NSStatusItem?
    private let popover = NSPopover()

    init(env: AppEnvironment) {
        self.env = env
        popover.behavior = .transient
        popover.contentSize = DS.Metrics.miniPlayerSize
        popover.contentViewController = NSHostingController(
            rootView: MiniPlayer().environment(env))
    }

    /// Идемпотентно: повторные вызовы с тем же значением ничего не делают.
    ///
    /// Снятие айтема — только отсюда: `deinit` под strict concurrency не имеет
    /// права трогать MainActor-состояние. Дубликатов не будет, потому что
    /// объект создаётся один раз за жизнь приложения (см. `EscapementApp`).
    func setEnabled(_ enabled: Bool) {
        guard enabled != (item != nil) else { return }
        if enabled {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(
                systemSymbolName: "diamond.fill", accessibilityDescription: "Rubis Music")
            item.button?.target = self
            item.button?.action = #selector(toggle)
            self.item = item
        } else {
            popover.performClose(nil)
            item.map(NSStatusBar.system.removeStatusItem)
            item = nil
        }
    }

    @objc private func toggle() {
        guard let button = item?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
