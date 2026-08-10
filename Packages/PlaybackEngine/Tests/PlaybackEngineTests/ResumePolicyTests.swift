import Testing

@testable import PlaybackEngine

/// Play после пропажи выхода (наушники выдернули из гнезда).
struct ResumePolicyTests {

    @Test func ordinaryPauseJustContinues() {
        #expect(ResumePolicy.decide(deviceLost: false, offset: 71) == .continueEngine)
        #expect(ResumePolicy.decide(deviceLost: false, offset: nil) == .continueEngine)
    }

    @Test func lostDeviceRestartsFromTheSameSecond() {
        // До 0.8.7 здесь был отказ: Play не делал ничего, пока трек не запустят
        // заново вручную. Движок держит мёртвое устройство — продолжать нечем.
        #expect(ResumePolicy.decide(deviceLost: true, offset: 71) == .restart(from: 71))
    }

    @Test func lostDeviceWithoutKnownPositionRestartsFromTheTop() {
        #expect(ResumePolicy.decide(deviceLost: true, offset: nil) == .restart(from: nil))
    }
}
