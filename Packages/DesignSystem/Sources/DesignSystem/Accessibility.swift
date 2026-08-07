import SwiftUI

/// Анимация, уважающая Reduce Motion: при включённой настройке значение
/// меняется мгновенно, без подмены длительности на «почти ноль».
///
/// Все анимации интерфейса ходят через это — прямой `.animation(DS.Motion.…)`
/// в новых местах не заводить, иначе настройка снова начнёт протекать.
public struct DSAnimation<Value: Equatable>: ViewModifier {
    private let animation: Animation
    private let value: Value

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(animation: Animation, value: Value) {
        self.animation = animation
        self.value = value
    }

    public func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// `.animation(_:value:)` с оглядкой на Reduce Motion.
    public func dsAnimation<Value: Equatable>(_ animation: Animation, value: Value) -> some View {
        modifier(DSAnimation(animation: animation, value: value))
    }
}

extension DS {
    /// Усиление контраста по системной настройке Increase Contrast.
    ///
    /// ASSUMPTION (на ревью владельцу, DESIGN §2): при включённой настройке
    /// самый тусклый текстовый тон поднимается на ступень, а волосяная линия
    /// становится заметной. Палитра не меняется — берутся соседние токены.
    public enum Contrast {
        public static func text(
            _ color: SwiftUI.Color, increased: Bool
        ) -> SwiftUI.Color {
            guard increased else { return color }
            if color == DS.Color.textTertiary { return DS.Color.textSecondary }
            if color == DS.Color.textSecondary { return DS.Color.textPrimary }
            return color
        }

        public static func stroke(increased: Bool) -> SwiftUI.Color {
            increased ? DS.Color.strokeStrong : DS.Color.strokeHairline
        }
    }
}
