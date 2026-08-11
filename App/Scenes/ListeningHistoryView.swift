import DesignSystem
import EscapementCore
import SwiftUI

/// History (фишка E): что и сколько слушали — целиком на этой машине.
/// Ни скроббла наружу: журнал соединений рядом это подтверждает.
struct ListeningHistoryView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var events: [PlayEvent] = []
    @State private var period: HistoryPeriod = .month

    private var visible: [PlayEvent] {
        guard let cutoff = period.cutoff else { return events }
        return ListeningHistory.since(cutoff, in: events)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack(alignment: .firstTextBaseline) {
                DSText(headline, style: .title)
                Spacer()
                Picker("", selection: $period) {
                    ForEach(HistoryPeriod.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 320)
                .accessibilityLabel("Period")
            }

            if visible.isEmpty {
                Spacer()
                DSText(
                    events.isEmpty
                        ? "Nothing played yet — history starts with the first track you hear."
                        : "Nothing in this period.",
                    style: .body, color: DS.Color.textTertiary
                )
                .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                HStack(alignment: .top, spacing: DS.Space.xxl) {
                    HistoryTallyList(
                        title: "Top artists", rows: ListeningHistory.topArtists(visible))
                    HistoryTallyList(
                        title: "Top tracks", rows: ListeningHistory.topTracks(visible))
                }
                recent
            }

            HStack {
                DSText(
                    "Plays are counted at half the track (or four minutes) and stay on this Mac.",
                    style: .caption, color: DS.Color.textSecondary)
                Spacer()
                Button("Clear history", role: .destructive) {
                    Task {
                        await env.listeningHistory.clear()
                        reload()
                    }
                }
                .disabled(events.isEmpty)
            }
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Color.bgBase)
        .task { reload() }
    }

    private var headline: String {
        switch visible.count {
        case 1: return "1 play"
        default: return "\(visible.count) plays"
        }
    }

    /// Лента последних прослушиваний — новое сверху.
    private var recent: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSSectionHeader("Recently played")
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    ForEach(Array(visible.reversed().prefix(50).enumerated()), id: \.offset) {
                        _, play in
                        HStack(spacing: DS.Space.md) {
                            DSText(play.title, style: .body)
                            DSText(
                                play.artist.isEmpty ? "Unknown artist" : play.artist,
                                style: .caption, color: DS.Color.textSecondary)
                            Spacer()
                            DSText(
                                play.date.formatted(date: .abbreviated, time: .shortened),
                                style: .caption, color: DS.Color.textTertiary)
                        }
                        .padding(.horizontal, DS.Space.md)
                    }
                }
                .padding(.vertical, DS.Space.xs)
            }
        }
    }

    private func reload() {
        Task { events = await env.listeningHistory.events() }
    }
}

/// Период сводки. `nil` — за всё время.
enum HistoryPeriod: String, CaseIterable, Identifiable {
    case week, month, year, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "7 days"
        case .month: return "30 days"
        case .year: return "Year"
        case .all: return "All time"
        }
    }

    var cutoff: Date? {
        switch self {
        case .week: return Date().addingTimeInterval(-7 * 86400)
        case .month: return Date().addingTimeInterval(-30 * 86400)
        case .year: return Date().addingTimeInterval(-365 * 86400)
        case .all: return nil
        }
    }
}

/// Колонка сводки: имя, число прослушиваний, наслушанное время.
struct HistoryTallyList: View {
    let title: String
    let rows: [HistoryTally]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSSectionHeader(title)
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        DSText(row.name.isEmpty ? "Unknown artist" : row.name, style: .body)
                        if !row.detail.isEmpty {
                            DSText(row.detail, style: .caption, color: DS.Color.textSecondary)
                        }
                    }
                    Spacer()
                    DSText(
                        Self.listened(row.seconds), style: .caption, color: DS.Color.textTertiary)
                    DSText("\(row.count)", style: .numeric, color: DS.Color.textSecondary)
                        .frame(minWidth: 28, alignment: .trailing)
                }
                .padding(.horizontal, DS.Space.md)
                .frame(height: DS.Metrics.sidebarRow)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Наслушанное: минуты до часа, дальше часы с минутами.
    static func listened(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        guard minutes >= 60 else { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }
}

#if DEBUG
private let previewTallies = [
    HistoryTally(
        name: "So What", detail: "Miles Davis", count: 12, seconds: 6540, last: Date()),
    HistoryTally(
        name: "Naima", detail: "John Coltrane", count: 5, seconds: 1400, last: Date()),
]

#Preview("History tallies — dark") {
    HistoryTallyList(title: "Top tracks", rows: previewTallies)
        .frame(width: 360)
        .padding(DS.Space.xl)
        .background(DS.Color.bgBase)
        .preferredColorScheme(.dark)
}

#Preview("History tallies — light") {
    HistoryTallyList(title: "Top tracks", rows: previewTallies)
        .frame(width: 360)
        .padding(DS.Space.xl)
        .background(DS.Color.bgBase)
        .preferredColorScheme(.light)
}
#endif
