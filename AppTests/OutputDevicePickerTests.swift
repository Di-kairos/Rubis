import Testing

@testable import Rubis_Music

/// Выбранный, но отключённый ЦАП остаётся виден в списке выхода: иначе Picker
/// показывает пустое поле, и непонятно, почему звука нет.
struct OutputDevicePickerTests {
    private let qx13 = "AppleUSBAudioEngine:GuangZhou FIIO Electronics Co.,Ltd:FIIO QX13:2100000:1"

    @Test func systemDefaultNeedsNoExtraRow() {
        #expect(AudioSettings.missingDeviceLabel(uid: "", connected: []) == nil)
    }

    @Test func connectedDeviceNeedsNoExtraRow() {
        #expect(AudioSettings.missingDeviceLabel(uid: qx13, connected: [qx13]) == nil)
    }

    @Test func unpluggedUSBDACIsNamedFromItsUID() {
        #expect(
            AudioSettings.missingDeviceLabel(uid: qx13, connected: ["BuiltInSpeakerDevice"])
                == "FIIO QX13 — not connected")
    }

    @Test func unknownUIDFormatFallsBackToGenericName() {
        #expect(
            AudioSettings.missingDeviceLabel(uid: "00-11-22-33-44-55:output", connected: [])
                == "Selected device — not connected")
    }
}
