import Foundation
import Testing

@testable import EscapementCore

/// Барьер: тест сам решает, когда «докачается» трек.
@MainActor
private final class Barrier {
    private var waiting: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private var hasStarted = false

    func hold() async {
        hasStarted = true
        started?.resume()
        started = nil
        await withCheckedContinuation { waiting = $0 }
    }

    func waitUntilStarted() async {
        if hasStarted { return }
        await withCheckedContinuation { started = $0 }
    }

    func release() {
        waiting?.resume()
        waiting = nil
    }
}

/// R02: поздняя загрузка не должна перебивать более новую команду.
@MainActor
struct TransportCommandsTests {
    @Test func lateLoadOfAYieldsToPlayB() async {
        let commands = TransportCommands()
        let barrier = Barrier()
        var played: [String] = []

        let a = Task {
            await commands.run(
                load: { await barrier.hold() },
                act: { played.append("A") })
        }
        await barrier.waitUntilStarted()

        // Пользователь выбрал B, пока A ещё качается: B играет сразу.
        await commands.run(load: {}, act: { played.append("B") })
        barrier.release()
        let didPlayA = await a.value

        #expect(didPlayA == false)
        #expect(played == ["B"])
    }

    @Test func lateLoadOfAYieldsToStop() async {
        let commands = TransportCommands()
        let barrier = Barrier()
        var played: [String] = []

        let a = Task {
            await commands.run(
                load: { await barrier.hold() },
                act: { played.append("A") })
        }
        await barrier.waitUntilStarted()

        // Stop не начинает своей загрузки, но отменяет чужую.
        commands.invalidate()
        barrier.release()
        let didPlayA = await a.value

        #expect(didPlayA == false)
        #expect(played.isEmpty, "после Stop остаётся idle")
    }

    @Test func undisturbedCommandStillPlays() async {
        let commands = TransportCommands()
        var played: [String] = []
        let done = await commands.run(load: {}, act: { played.append("A") })
        #expect(done)
        #expect(played == ["A"])
    }

    @Test func backgroundWorkMarksWithoutCancellingTheUser() async {
        let commands = TransportCommands()
        let barrier = Barrier()
        var played: [String] = []

        let user = Task {
            await commands.run(
                load: { await barrier.hold() },
                act: { played.append("user") })
        }
        await barrier.waitUntilStarted()
        // Префетч только запоминает границу — команда пользователя остаётся в силе.
        let prefetch = commands.current()
        #expect(commands.isCurrent(prefetch))
        barrier.release()

        #expect(await user.value)
        #expect(played == ["user"])
    }

    @Test func tokenOfAnOlderCommandIsNotCurrent() {
        let commands = TransportCommands()
        let first = commands.begin()
        let second = commands.begin()
        #expect(!commands.isCurrent(first))
        #expect(commands.isCurrent(second))
    }
}
