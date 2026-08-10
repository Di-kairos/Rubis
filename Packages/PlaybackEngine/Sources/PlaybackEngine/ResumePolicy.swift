import Foundation

/// Что делать по нажатию Play из паузы (SPEC §4.2, §9). Логика чистая:
/// железо трогает `Player`, решение принимается здесь и проверяется тестами.
public enum ResumePolicy {

    public enum Decision: Equatable, Sendable {
        /// Обычная пауза — движок продолжает с того же места.
        case continueEngine
        /// Выход пропадал (наушники выдернули, ЦАП отключили): движок держит
        /// мёртвое устройство и продолжить не сможет — трек поднимается заново
        /// с этой секунды. Это не авто-возобновление, запрещённое SPEC §9:
        /// перезапуск случается только по явному нажатию Play.
        case restart(from: TimeInterval?)
    }

    public static func decide(deviceLost: Bool, offset: TimeInterval?) -> Decision {
        deviceLost ? .restart(from: offset) : .continueEngine
    }
}
