import DesignSystem
import EscapementCore
import MusicLibrary
import SwiftUI

/// Ширины неэластичных колонок; заголовок и строки берут их отсюда,
/// иначе колонки разъезжаются.
private enum Col {
    static let mark: CGFloat = 12
    static let index: CGFloat = 34
    /// Хватает на слово DURATION в стиле `label` — иначе заголовок обрезается.
    static let duration: CGFloat = 76
    static let format: CGFloat = 64
    /// Артист и альбом ограничены, чтобы остаток ширины доставался названию:
    /// при равных третях названия обрезались первыми.
    static let secondary: CGFloat = 200
}

/// Tracks section: вся библиотека с сортировкой по колонкам и
/// мультивыделением (⌘/⇧-клик, стрелки — от List). Двойной клик или Return
/// играет с этой строки в текущем порядке сортировки.
struct TracksList: View {
    @Environment(AppEnvironment.self) private var env
    /// Всегда в порядке показа: пересортировываем при смене колонки, а не в `body`.
    @State private var rows: [SearchHit] = []
    /// Номер строки без `enumerated()` на каждый рендер — на 100k это заметно.
    @State private var positions: [Int64: Int] = [:]
    @State private var column: TrackSort = .title
    @State private var ascending = true
    @State private var selection: Set<Int64> = []
    /// Счётчик пересортировок: результат устаревшей задачи не применяем.
    @State private var generation = 0
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            TrackListHeader(column: $column, ascending: $ascending)
            Rectangle()
                .fill(DS.Color.strokeHairline)
                .frame(height: 1)
            if isLoading {
                DSText("Loading library…", style: .body, color: DS.Color.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                trackList
            }
        }
        .background(DS.Color.bgBase)
        .task {
            let repo = env.trackRepo
            let loaded = await Task.detached(priority: .userInitiated) {
                (try? repo.allWithNames()) ?? []
            }.value
            // Сортируем по колонке, выбранной к этому моменту: клик по заголовку
            // во время загрузки не теряется.
            await resort(loading: loaded)
            isLoading = false
            #if DEBUG
            // Для снимка окна харнессом: показать, как выглядит выделение.
            if ProcessInfo.processInfo.environment["RUBIS_DEBUG_SELECT"] != nil {
                selection = Set(rows.prefix(2).map(\.id))
            }
            #endif
        }
        // Пока список грузится, сортировать нечего — порядок подхватит загрузка.
        .onChange(of: column) { if !isLoading { Task { await resort() } } }
        .onChange(of: ascending) { if !isLoading { Task { await resort() } } }
    }

    private var trackList: some View {
        List(selection: $selection) {
            ForEach(rows) { row in
                TrackListRow(
                    row: row,
                    index: (positions[row.id] ?? 0) + 1,
                    isCurrent: isCurrent(row.track),
                    isSelected: selection.contains(row.id)
                )
                .onTapGesture(count: 2) { play(from: positions[row.id]) }
                .draggable(row.track.dragPayload)
                .contextMenu { QueueMenuItems(tracks: menuTargets(row), env: env) }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(DS.Color.bgBase)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Return играет с верхней выделенной строки.
        .onKeyPress(.return) {
            guard let index = selection.compactMap({ positions[$0] }).min() else {
                return .ignored
            }
            play(from: index)
            return .handled
        }
    }

    /// Загрузка и сортировка уходят с главного потока: на 100k это 1.5 с и 0.4 с
    /// (release), на MainActor окно бы вставало колом.
    /// ponytail: библиотека целиком в памяти; упрётся — страничная выборка.
    private func resort(loading loaded: [SearchHit]? = nil) async {
        let source = loaded ?? rows
        let (field, ascending) = (column, self.ascending)
        // Быстрые клики по заголовкам запускают сортировки внахлёст; применяем
        // только последнюю, иначе порядок разойдётся со стрелкой в заголовке.
        generation += 1
        let token = generation
        let result = await Task.detached(priority: .userInitiated) {
            let sorted = TrackSort.sorted(source, by: field, ascending: ascending)
            let positions = Dictionary(
                sorted.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            return (sorted, positions)
        }.value
        guard token == generation else { return }
        rows = result.0
        positions = result.1
    }

    /// Контекстное меню по строке внутри выделения работает на всё выделение,
    /// по строке вне его — только на неё (поведение Finder).
    private func menuTargets(_ row: SearchHit) -> [Track] {
        guard selection.count > 1, selection.contains(row.id) else { return [row.track] }
        return rows.filter { selection.contains($0.id) }.map(\.track)
    }

    private func isCurrent(_ track: Track) -> Bool {
        if case .playing(let current) = env.playbackState { return current.id == track.id }
        if case .paused(let current) = env.playbackState { return current.id == track.id }
        return false
    }

    private func play(from index: Int?) {
        guard let index else { return }
        env.play(tracks: rows.map(\.track), startAt: index)
    }
}

/// Заголовки колонок: `label`/`text.tertiary`, активная — со стрелкой (DESIGN §5.2).
struct TrackListHeader: View {
    @Binding var column: TrackSort
    @Binding var ascending: Bool

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Spacer().frame(width: Col.mark)
            DSText("#", style: .label, color: DS.Color.textTertiary)
                .frame(width: Col.index, alignment: .trailing)
            button(.title).frame(maxWidth: .infinity, alignment: .leading)
            button(.artist).frame(maxWidth: Col.secondary, alignment: .leading)
            button(.album).frame(maxWidth: Col.secondary, alignment: .leading)
            button(.duration).frame(width: Col.duration, alignment: .trailing)
            button(.format).frame(width: Col.format, alignment: .trailing)
        }
        .padding(.horizontal, DS.Space.md)
        .frame(height: DS.Metrics.trackRowCompact)
    }

    private func button(_ target: TrackSort) -> some View {
        Button {
            if column == target {
                ascending.toggle()
            } else {
                column = target
                ascending = true
            }
        } label: {
            HStack(spacing: DS.Space.xs) {
                DSText(
                    target.label, style: .label,
                    color: column == target ? DS.Color.textSecondary : DS.Color.textTertiary)
                if column == target {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort by \(target.label)")
    }
}

/// Строка списка треков: номер (или ◆ у играющего), название, артист,
/// альбом, длительность, формат.
struct TrackListRow: View {
    let row: SearchHit
    let index: Int
    let isCurrent: Bool
    let isSelected: Bool

    var body: some View {
        DSListRow(isSelected: isSelected) {
            HStack(spacing: DS.Space.md) {
                ZStack { UnavailableMark(track: row.track) }
                    .frame(width: Col.mark)
                Group {
                    if isCurrent {
                        PlayingMark(isPlaying: true)
                    } else {
                        DSText("\(index)", style: .numeric, color: DS.Color.textTertiary)
                    }
                }
                .frame(width: Col.index, alignment: .trailing)
                DSText(
                    row.track.title, style: .headline,
                    color: row.track.titleColor(isPlaying: isCurrent)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                DSText(row.artistName ?? "—", style: .body, color: DS.Color.textSecondary)
                    .frame(maxWidth: Col.secondary, alignment: .leading)
                DSText(row.albumTitle ?? "—", style: .body, color: DS.Color.textSecondary)
                    .frame(maxWidth: Col.secondary, alignment: .leading)
                DSText(
                    AlbumDetail.format(duration: row.track.duration), style: .numeric,
                    color: DS.Color.textTertiary
                )
                .frame(width: Col.duration, alignment: .trailing)
                DSText(
                    row.track.codec.uppercased(), style: .caption,
                    color: DS.Color.textTertiary
                )
                .frame(width: Col.format, alignment: .trailing)
            }
        }
    }
}

#if DEBUG
private func previewRow(_ title: String, _ codec: String, _ seconds: Double) -> SearchHit {
    SearchHit(
        track: Track(
            id: Int64(abs(title.hashValue % 10_000)), sourceId: "preview", title: title,
            duration: seconds, codec: codec, sampleRate: 44100),
        artistName: "Miles Davis",
        albumTitle: "Kind of Blue")
}

private struct TrackListPreview: View {
    @State private var column: TrackSort = .title
    @State private var ascending = true

    var body: some View {
        VStack(spacing: 0) {
            TrackListHeader(column: $column, ascending: $ascending)
            Rectangle().fill(DS.Color.strokeHairline).frame(height: 1)
            TrackListRow(
                row: previewRow("So What", "flac", 545), index: 1, isCurrent: false,
                isSelected: false)
            TrackListRow(
                row: previewRow("Blue in Green", "flac", 337), index: 2, isCurrent: true,
                isSelected: false)
            TrackListRow(
                row: previewRow("All Blues", "alac", 693), index: 3, isCurrent: false,
                isSelected: true)
        }
        .frame(width: 640)
        .background(DS.Color.bgBase)
    }
}

#Preview("TracksList — dark") {
    TrackListPreview().preferredColorScheme(.dark)
}

#Preview("TracksList — light") {
    TrackListPreview().preferredColorScheme(.light)
}
#endif
