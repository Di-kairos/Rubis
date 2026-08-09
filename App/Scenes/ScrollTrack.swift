import SwiftUI

/// Геометрия одной оси скролла — питает `DSScrollIndicator` и переводит
/// тягу за ползунок обратно в смещение. Общая для полки альбомов
/// (горизонталь) и списков (вертикаль).
struct ScrollTrack: Equatable {
    var offset: CGFloat = 0
    var content: CGFloat = 0
    var container: CGFloat = 0

    /// Доля видимой части (1 — влезло целиком, указатель не нужен).
    var visible: Double {
        guard content > 0 else { return 1 }
        return min(1, Double(container / content))
    }

    var progress: Double {
        guard scrollable > 0 else { return 0 }
        return min(1, max(0, Double(offset / scrollable)))
    }

    /// Обратное к `progress`: куда увести содержимое, когда тянут указатель.
    func offset(forProgress progress: Double) -> CGFloat {
        scrollable * CGFloat(min(max(progress, 0), 1))
    }

    private var scrollable: CGFloat { max(0, content - container) }

    static func horizontal(_ geometry: ScrollGeometry) -> ScrollTrack {
        ScrollTrack(
            offset: geometry.contentOffset.x,
            content: geometry.contentSize.width,
            container: geometry.containerSize.width)
    }

    static func vertical(_ geometry: ScrollGeometry) -> ScrollTrack {
        ScrollTrack(
            offset: geometry.contentOffset.y,
            content: geometry.contentSize.height,
            container: geometry.containerSize.height)
    }
}
