import CoreAudio
import Foundation

/// Всё, что `Player` спрашивает у слоя устройств.
///
/// Настоящий `AudioDeviceController` ходит в CoreAudio, поэтому логику стыка
/// (заряд → active → очистка очереди) без этого протокола пришлось бы проверять
/// на живом железе. Подмена нужна только тестам: боевой путь — тот же контроллер
/// (R03, перепроверка аудита 13.09.2026).
protocol AudioDevicesProviding: Sendable {
    func defaultOutputDevice() async throws -> AudioDeviceController.DeviceInfo?
    func device(uid: String) async throws -> AudioDeviceController.DeviceInfo?
    func isBuiltInDevice(deviceID: UInt32) async -> Bool
    func startHogging(deviceID: UInt32) async -> Bool
    func stopHogging(deviceID: UInt32) async
    func disableMixing(deviceID: UInt32) async -> Bool
    func availableSampleRates(deviceID: UInt32) async throws -> [Double]
    func physicalFormats(deviceID: UInt32) async throws -> [AudioDeviceController.PhysicalFormat]
    func nominalSampleRate(deviceID: UInt32) async throws -> Double
    func setNominalSampleRate(deviceID: UInt32, rate: Double) async throws
    func hasVolumeControl(deviceID: UInt32) async -> Bool
    func volumeScalar(deviceID: UInt32) async -> Float?
    func setVolumeScalar(deviceID: UInt32, value: Float) async throws
    func observeDeviceDeath(
        deviceID: UInt32, onDeath: @escaping @Sendable () -> Void
    ) async throws
    func stopObservingDeviceDeath() async
}

extension AudioDeviceController: AudioDevicesProviding {}
