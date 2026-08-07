import DesignSystem
import EscapementCore
import MusicLibrary
import SwiftUI

struct Sidebar: View {
    @Binding var section: LibrarySection
    @Environment(AppEnvironment.self) private var env
    @State private var sources: [Source] = []

    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var env = env
        VStack(alignment: .leading, spacing: 0) {
            DSSearchField(text: $env.searchText)
                .focused($searchFocused)
                .padding(DS.Space.md)
                .onChange(of: env.searchFocusTrigger) { searchFocused = true }
                .onChange(of: searchFocused) { env.searchFieldFocused = searchFocused }
                // ↓ из поля — фокус в результаты, дальше стрелками (SPEC §7.2).
                .onKeyPress(.downArrow) {
                    guard !env.searchText.isEmpty else { return .ignored }
                    env.searchResultsFocusTrigger += 1
                    return .handled
                }
                // Esc из поля сбрасывает поиск, не заставляя чистить руками.
                .onKeyPress(.escape) {
                    guard !env.searchText.isEmpty else { return .ignored }
                    env.searchText = ""
                    return .handled
                }

            // Содержимое скроллится: десятки источников не должны распирать
            // колонку и ломать layout окна (краш в NSViewUpdateConstraints).
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DSSectionHeader("Library")
                    ForEach(LibrarySection.allCases) { item in
                        sidebarRow(item)
                    }

                    Spacer(minLength: DS.Space.xl)

                    DSSectionHeader("Sources")
                    ForEach(sources) { source in
                        HStack(spacing: DS.Space.sm) {
                            Image(systemName: source.kind == .local ? "folder" : "server.rack")
                                .font(.system(size: 12))
                                .foregroundStyle(DS.Color.textTertiary)
                                .accessibilityHidden(true)
                            DSText(
                                source.displayName, style: .body,
                                color: source.enabled
                                    ? DS.Color.textSecondary : DS.Color.textDisabled)
                            Spacer()
                        }
                        .padding(.horizontal, DS.Space.md)
                        .frame(height: DS.Metrics.sidebarRow)
                    }
                }
            }

            if case .reading(let done, let total) = env.scanProgress {
                // Ненавязчивая полоска прогресса скана (SPEC §5.2)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    DSText(
                        "Scanning \(done)/\(total)", style: .caption,
                        color: DS.Color.textTertiary)
                    DSProgressBar(progress: total > 0 ? Double(done) / Double(total) : 0)
                }
                .padding(DS.Space.md)
            }

            Spacer(minLength: DS.Space.sm)
        }
        .background(DS.Color.bgRaised)
        .task { reloadSources() }
        .onChange(of: env.scanProgress == nil) { reloadSources() }
    }

    private func sidebarRow(_ item: LibrarySection) -> some View {
        Button {
            section = item
        } label: {
            HStack(spacing: DS.Space.sm) {
                // Активный раздел — золотая нить слева, не заливная пилюля (D-007).
                Rectangle()
                    .fill(section == item ? DS.Color.accent : .clear)
                    .frame(width: 2)
                Image(systemName: item.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(section == item ? DS.Color.accent : DS.Color.textTertiary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                DSText(
                    item.rawValue, style: .body,
                    color: section == item ? DS.Color.textPrimary : DS.Color.textSecondary)
                Spacer()
            }
            .padding(.leading, DS.Space.md - 2)
            .padding(.trailing, DS.Space.md)
            .frame(height: DS.Metrics.sidebarRow)
            .background(section == item ? DS.Color.bgSelected : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.rawValue)
        .accessibilityAddTraits(section == item ? .isSelected : [])
    }

    private func reloadSources() {
        sources = (try? env.sourceRepo.all()) ?? []
    }
}
