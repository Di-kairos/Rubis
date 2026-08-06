import DesignSystem
import EscapementCore
import MusicLibrary
import SwiftUI

/// FTS search results (SPEC §7.2): live while typing, double-click plays.
struct SearchResults: View {
    @Binding var selectedAlbum: Album?
    @Environment(AppEnvironment.self) private var env
    @State private var hits: [SearchHit] = []

    var body: some View {
        Group {
            if hits.isEmpty {
                DSText("Nothing found", style: .body, color: DS.Color.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        DSSectionHeader("Tracks")
                        ForEach(Array(hits.enumerated()), id: \.offset) { index, hit in
                            DSListRow(height: DS.Metrics.trackRowWithCover) {
                                HStack(spacing: DS.Space.md) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        DSText(hit.track.title, style: .headline)
                                        DSText(
                                            [hit.artistName, hit.albumTitle]
                                                .compactMap(\.self).joined(separator: " — "),
                                            style: .caption, color: DS.Color.textSecondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    DSText(
                                        AlbumDetail.format(duration: hit.track.duration),
                                        style: .numeric, color: DS.Color.textTertiary)
                                }
                            }
                            .onTapGesture(count: 2) {
                                env.play(tracks: hits.map(\.track), startAt: index)
                            }
                            .draggable(hit.track.dragPayload)
                        }
                    }
                }
            }
        }
        .background(DS.Color.bgBase)
        .task(id: env.searchText) {
            // лёгкий дебаунс набора
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            hits = (try? env.trackRepo.search(env.searchText)) ?? []
        }
    }
}
