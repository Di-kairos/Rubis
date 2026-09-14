import Testing

@testable import EscapementCore

/// Повторяет границу интеграции AppEnvironment: run вызывается внутри Task.
/// Сам TransportCommands.begin/run работает по своему контракту; проблема —
/// поздняя выдача отметки после уже принятой синхронной команды паузы.
@MainActor
struct AuditFollowupTests {
    @Test func queuedPlayMustNotBecomeNewerThanALaterPause() async {
        let commands = TransportCommands()
        var played: [String] = []
        let play = Task {
            await commands.run(load: {}, act: { played.append("A") })
        }
        // Как togglePlayPause/next: инвалидируем прямо в обработчике, до Task.
        commands.invalidate()
        let acted = await play.value
        print("FOLLOWUP dispatch: acted=\(acted), played=\(played)")
        #expect(!acted)
        #expect(played.isEmpty)
    }
}
