import SwiftUI

/// Клавиатурная навигация по коллекции: ↑↓ двигают фокус, Return активирует.
///
/// Только вертикаль даже в сетке: `←`/`→` заняты перемоткой ±5 с (SPEC §7.6),
/// и отнимать их у плеера ради горизонтального шага по сетке не стоит —
/// последовательный обход ↑↓ добирается до любой карточки.
///
/// `count == 0` полностью выключает навигацию — так вызывающий гасит её,
/// например на время переименования в текстовом поле.
struct KeyboardListNavigation: ViewModifier {
    let count: Int
    @Binding var index: Int?
    let activate: (Int) -> Void

    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focusable(count > 0)
            // Свой индикатор фокуса — золотое выделение (D-007); системное
            // синее кольцо вокруг всей области (macOS 26) не нужно.
            .focusEffectDisabled()
            .focused($isFocused)
            // Клик по строке забирает и клавиатурный фокус, не отбирая тап у строки.
            .simultaneousGesture(TapGesture().onEnded { isFocused = true })
            .onKeyPress(keys: [.upArrow, .downArrow, .return]) { press in
                guard count > 0 else { return .ignored }
                switch press.key {
                case .return:
                    guard let index, (0..<count).contains(index) else { return .ignored }
                    activate(index)
                case .upArrow:
                    move(-1)
                case .downArrow:
                    move(1)
                default:
                    return .ignored
                }
                return .handled
            }
            // Коллекция живая (скан, удаление) — фокус не должен указывать в пустоту.
            .onChange(of: count) {
                guard let current = index else { return }
                index = count == 0 ? nil : min(current, count - 1)
            }
    }

    private func move(_ delta: Int) {
        let next = (index ?? (delta > 0 ? -1 : count)) + delta
        index = min(max(next, 0), count - 1)
    }
}

extension View {
    /// ↑↓ по `count` элементам с Return на текущем.
    func keyboardNavigable(
        count: Int, index: Binding<Int?>, activate: @escaping (Int) -> Void
    ) -> some View {
        modifier(KeyboardListNavigation(count: count, index: index, activate: activate))
    }
}
