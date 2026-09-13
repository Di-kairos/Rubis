import Foundation

/// Актуальность команды транспорта: Play, Stop, следующий/предыдущий трек.
///
/// Серверный трек уходит в сеть ДО обращения к плееру. Пока качается A,
/// пользователь успевает нажать Play B или Stop — и докачавшийся A запускал звук
/// поверх них: для плеера этот запоздавший вызов выглядит новой командой, а
/// отмена `Task` без проверки после `await` его не останавливает
/// (R02, перепроверка аудита 13.09.2026).
///
/// Отметка выдаётся на пользовательском действии, до сети, и проверяется после
/// загрузки — перед тем, как тронуть плеер.
@MainActor
public final class TransportCommands {
    private var epoch = 0

    public init() {}

    /// Новая команда: всё, что было начато раньше, перестаёт быть актуальным.
    @discardableResult
    public func begin() -> Int {
        epoch += 1
        return epoch
    }

    /// Отметка текущей команды БЕЗ начала новой: фоновым работам (префетч,
    /// повтор сорванного трека) нужна граница актуальности, но перебивать
    /// нажатие пользователя они не должны.
    public func current() -> Int { epoch }

    /// Команда всё ещё последняя?
    public func isCurrent(_ token: Int) -> Bool { token == epoch }

    /// Отменяет начатое, не начиная своего: Stop и пауза тоже перебивают загрузку.
    public func invalidate() { epoch += 1 }

    /// Подготовка (сеть, диск) и затем действие — но только если за время
    /// подготовки не пришла новая команда.
    /// - Returns: `true`, если действие выполнено.
    @discardableResult
    public func run(
        load: @MainActor () async -> Void,
        act: @MainActor () async -> Void
    ) async -> Bool {
        let token = begin()
        await load()
        guard isCurrent(token) else { return false }
        await act()
        return true
    }
}
