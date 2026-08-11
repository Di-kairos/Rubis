import Testing

@testable import PlaybackEngine

struct DeviceDossierTests {

    @Test func dopCeilingFollowsTheHighestRate() {
        #expect(DeviceDossier.dopCeiling(rates: [44100, 96000], bitDepths: [24]) == nil)
        #expect(DeviceDossier.dopCeiling(rates: [176_400], bitDepths: [24]) == "DSD64")
        #expect(DeviceDossier.dopCeiling(rates: [192_000, 352_800], bitDepths: [24]) == "DSD128")
        #expect(DeviceDossier.dopCeiling(rates: [705_600], bitDepths: [16, 24]) == "DSD256")
        #expect(DeviceDossier.dopCeiling(rates: [1_536_000], bitDepths: [32]) == "DSD512")
    }

    @Test func dopNeedsTwentyFourBits() {
        // DoP везёт DSD внутри 24-битного слова: на 16 битах его нет,
        // какой бы высокой ни была частота.
        #expect(DeviceDossier.dopCeiling(rates: [352_800], bitDepths: [16]) == nil)
    }

    @Test func deviceWithoutRatesHasNoCeiling() {
        #expect(DeviceDossier.dopCeiling(rates: [], bitDepths: [24]) == nil)
    }

    @Test func probedRatesCoverBothFamiliesUpToDSD512() {
        #expect(DeviceDossier.probedRates.contains(44100))
        #expect(DeviceDossier.probedRates.contains(48000))
        #expect(DeviceDossier.probedRates.contains(1_411_200))
        // Список отсортирован — досье показывает частоты по возрастанию.
        #expect(DeviceDossier.probedRates == DeviceDossier.probedRates.sorted())
    }
}
