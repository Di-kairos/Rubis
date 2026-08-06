import DesignSystem
import EscapementCore
import SwiftUI

/// Значок «файла нет на месте» с путём в тултипе (SPEC §9).
/// Пустое место, когда с треком всё в порядке.
struct UnavailableMark: View {
    let track: Track

    var body: some View {
        if track.unavailable {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(DS.Color.warning)
                .help(track.relativePath ?? "file not found")
                .accessibilityLabel("File not found")
        }
    }
}

extension Track {
    /// Цвет названия в списках: играющий → акцент, пропавший → приглушённый.
    func titleColor(isPlaying: Bool) -> SwiftUI.Color {
        if unavailable { return DS.Color.textDisabled }
        return isPlaying ? DS.Color.accent : DS.Color.textPrimary
    }
}
