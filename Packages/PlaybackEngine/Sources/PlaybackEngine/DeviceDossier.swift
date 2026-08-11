import Foundation

/// Досье на подключённый ЦАП (фишка B, локальная половина): что железо
/// действительно умеет — по опросу HAL, а не по обещаниям коробки.
///
/// Публичной базы устройств здесь нет и не будет: она означала бы бэкенд и
/// сбор данных, а SPEC §1.2 обещает обратное.
public struct DeviceDossier: Sendable, Equatable {
    public let name: String
    public let uid: String
    /// USB / Built-in / Bluetooth / Thunderbolt — как его видит система.
    public let transport: String
    /// Частоты, которые устройство действительно принимает.
    public let sampleRates: [Double]
    /// Разрядности физических форматов (16/24/32).
    public let bitDepths: [Int]
    /// Устройство объявляет физический формат DSD — редкость, но встречается.
    public let nativeDSD: Bool
    /// Есть аппаратная ручка громкости (SPEC §4.4 — программной не бывает).
    public let hardwareVolume: Bool
    /// HAL разрешает снять микшер (SPEC §4.2.2).
    public let mixingControl: Bool
    /// Встроенный выход машины: hog к нему не применяем принципиально.
    public let builtIn: Bool
    /// Отдаёт ли эксклюзивный доступ — nil, пока не проверяли живьём.
    public var hogging: Bool?

    public init(
        name: String, uid: String, transport: String, sampleRates: [Double], bitDepths: [Int],
        nativeDSD: Bool, hardwareVolume: Bool, mixingControl: Bool, builtIn: Bool,
        hogging: Bool? = nil
    ) {
        self.name = name
        self.uid = uid
        self.transport = transport
        self.sampleRates = sampleRates
        self.bitDepths = bitDepths
        self.nativeDSD = nativeDSD
        self.hardwareVolume = hardwareVolume
        self.mixingControl = mixingControl
        self.builtIn = builtIn
        self.hogging = hogging
    }

    /// Потолок DSD через DoP. DoP везёт поток DSD внутри 24-битного PCM,
    /// поэтому частота нужна ровно в 16 раз меньше частоты DSD: DSD64 —
    /// 176.4 кГц, DSD128 — 352.8, DSD256 — 705.6, DSD512 — 1411.2.
    /// Без 24 бит DoP невозможен вовсе.
    public var dopCeiling: String? {
        Self.dopCeiling(rates: sampleRates, bitDepths: bitDepths)
    }

    public static func dopCeiling(rates: [Double], bitDepths: [Int]) -> String? {
        guard bitDepths.contains(where: { $0 >= 24 }), let top = rates.max() else { return nil }
        switch top {
        case 1_411_200...: return "DSD512"
        case 705_600...: return "DSD256"
        case 352_800...: return "DSD128"
        case 176_400...: return "DSD64"
        default: return nil
        }
    }

    /// Частоты, которые вообще имеет смысл спрашивать у устройства: обе
    /// семьи до DoP-потолка. Шире, чем список воспроизведения
    /// (`SampleRatePolicy`), — досье интересует железо, а не наша политика.
    public static let probedRates: [Double] = [
        44100, 48000, 88200, 96000, 176_400, 192_000, 352_800, 384_000,
        705_600, 768_000, 1_411_200, 1_536_000,
    ]
}
