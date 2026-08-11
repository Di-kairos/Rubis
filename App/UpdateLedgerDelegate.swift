import EscapementCore
import Foundation
import Sparkle

/// Проверки обновлений тоже уходят в журнал соединений (SPEC §1.2): панель
/// обязана показывать ВСЕ исходящие запросы приложения, а не только те,
/// которые делает наш собственный код. Sparkle ходит своим URLSession,
/// поэтому событие снимается с его цикла проверки.
final class UpdateLedgerDelegate: NSObject, SPUUpdaterDelegate {
    private let ledger: NetworkLedger

    init(ledger: NetworkLedger) {
        self.ledger = ledger
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        let host = updater.feedURL?.host ?? "raw.githubusercontent.com"
        let succeeded = error == nil
        Task { [ledger] in
            // Размер ответа Sparkle нам не отдаёт — в журнале это честный ноль,
            // а не выдуманное число.
            await ledger.record(
                host: host, purpose: "Update check", succeeded: succeeded, bytes: 0)
        }
    }
}
