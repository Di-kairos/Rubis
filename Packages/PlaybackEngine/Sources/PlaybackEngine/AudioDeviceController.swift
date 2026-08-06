import CAAudioHardware
import CoreAudio
import EscapementCore
import Foundation

/// HAL access for output devices (SPEC §4.2): enumeration, sample rates,
/// hog mode, mixing, hardware volume, death observation.
/// An actor because CAAudioHardware objects are not Sendable — all HAL
/// traffic is serialized here; calls are cheap and infrequent.
public actor AudioDeviceController {
    public struct DeviceInfo: Sendable, Equatable, Identifiable {
        public let id: UInt32
        public let uid: String
        public let name: String
    }

    public init() {}

    // MARK: - Enumeration

    public func outputDevices() throws -> [DeviceInfo] {
        try AudioDevice.devices
            .filter { (try? $0.streams(inScope: .output).isEmpty == false) ?? false }
            .map { try info(for: $0) }
    }

    public func defaultOutputDevice() throws -> DeviceInfo? {
        guard let device = try AudioDevice.defaultOutputDevice else { return nil }
        return try info(for: device)
    }

    public func device(uid: String) throws -> DeviceInfo? {
        guard let device = try AudioDevice.makeDevice(forUID: uid) else { return nil }
        return try info(for: device)
    }

    private func info(for device: AudioDevice) throws -> DeviceInfo {
        DeviceInfo(
            id: device.objectID,
            uid: (try? device.deviceUID) ?? "",
            name: (try? device.name) ?? "Unknown Device")
    }

    // MARK: - Sample rates

    /// Standard rates the device supports, flattened from HAL ranges.
    public func availableSampleRates(deviceID: UInt32) throws -> [Double] {
        let device = try requireDevice(deviceID)
        let ranges = try device.availableNominalSampleRates
        let candidates = SampleRatePolicy.family44 + SampleRatePolicy.family48
        return candidates.filter { rate in ranges.contains { $0.contains(rate) } }.sorted()
    }

    public func nominalSampleRate(deviceID: UInt32) throws -> Double {
        try requireDevice(deviceID).nominalSampleRate
    }

    public func setNominalSampleRate(deviceID: UInt32, rate: Double) throws {
        try requireDevice(deviceID).setNominalSampleRate(rate)
    }

    // MARK: - Hog mode & mixing

    /// Attempts exclusive access. Returns true on success; failure is a
    /// degradation, not an error (SPEC §4.2.1 — show status, keep playing).
    public func startHogging(deviceID: UInt32) -> Bool {
        guard let device = try? requireDevice(deviceID) else { return false }
        do {
            try device.startHogging()
            return try device.isHogOwner
        } catch {
            Log.audio.info("hog mode unavailable for device \(deviceID)")
            return false
        }
    }

    public func stopHogging(deviceID: UInt32) {
        guard let device = try? requireDevice(deviceID),
            (try? device.isHogOwner) == true
        else { return }
        try? device.stopHogging()
    }

    public func isHogOwner(deviceID: UInt32) -> Bool {
        ((try? requireDevice(deviceID).isHogOwner) ?? false)
    }

    /// Disables the HAL mixer where supported (SPEC §4.2.2). CAAudioHardware
    /// has no wrapper for this property — thin raw HAL write, as the spec allows.
    @discardableResult
    public func disableMixing(deviceID: UInt32) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertySupportsMixing,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var value: UInt32 = 0
        let status = AudioObjectSetPropertyData(
            deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        return status == noErr
    }

    // MARK: - Hardware volume (SPEC §4.4 — never software gain)

    public func hasVolumeControl(deviceID: UInt32) -> Bool {
        guard let device = try? requireDevice(deviceID) else { return false }
        return (try? device.volumeScalar(inScope: .output)) != nil
    }

    public func volumeScalar(deviceID: UInt32) -> Float? {
        try? requireDevice(deviceID).volumeScalar(inScope: .output)
    }

    public func setVolumeScalar(deviceID: UInt32, value: Float) throws {
        try requireDevice(deviceID).setVolumeScalar(
            min(max(value, 0), 1), inScope: .output)
    }

    // MARK: - Death observation (SPEC §9 — pause, no auto-resume)

    private var observedDevice: AudioDevice?

    /// Fires once when the observed device disappears.
    public func observeDeviceDeath(
        deviceID: UInt32, onDeath: @escaping @Sendable () -> Void
    ) throws {
        stopObservingDeviceDeath()
        let device = try requireDevice(deviceID)
        try device.whenSelectorChanges(.deviceIsAlive) { _ in
            onDeath()
        }
        observedDevice = device
    }

    public func stopObservingDeviceDeath() {
        if let device = observedDevice {
            try? device.whenSelectorChanges(.deviceIsAlive, perform: nil)
        }
        observedDevice = nil
    }

    // MARK: -

    private func requireDevice(_ id: UInt32) throws -> AudioDevice {
        guard let device = try AudioDevice.devices.first(where: { $0.objectID == id }) else {
            throw PlaybackError.deviceUnavailable
        }
        return device
    }
}
