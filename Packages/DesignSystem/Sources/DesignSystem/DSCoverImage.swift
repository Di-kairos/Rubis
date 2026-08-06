import AppKit
import SwiftUI

/// Album cover with the DesignSystem placeholder (DESIGN.md §5) —
/// never the stock Apple template icon.
public struct DSCoverImage: View {
    private let image: NSImage?
    private let size: CGFloat
    private let radius: CGFloat

    public init(image: NSImage? = nil, size: CGFloat, radius: CGFloat = DS.Radius.small) {
        self.image = image
        self.size = size
        self.radius = radius
    }

    public var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    DS.Color.bgOverlay
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.28, weight: .light))
                        .foregroundStyle(DS.Color.textDisabled)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .overlay(
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(DS.Color.strokeHairline, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}

#Preview("DSCoverImage — dark") {
    HStack(spacing: DS.Space.lg) {
        DSCoverImage(size: DS.Metrics.transportCover)
        DSCoverImage(size: DS.Metrics.albumGridCover, radius: DS.Radius.card)
    }
    .padding(DS.Space.xl)
    .background(DS.Color.bgBase)
    .preferredColorScheme(.dark)
}

#Preview("DSCoverImage — light") {
    DSCoverImage(size: DS.Metrics.albumGridCover, radius: DS.Radius.card)
        .padding(DS.Space.xl)
        .background(DS.Color.bgBase)
        .preferredColorScheme(.light)
}
