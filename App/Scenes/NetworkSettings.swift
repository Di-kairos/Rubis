import DesignSystem
import EscapementCore
import SwiftUI

/// Settings → Network: все исходящие соединения приложения за всё время.
/// Смысл раздела — не настройка, а свидетельство: SPEC §1.2 обещает ноль
/// запросов по умолчанию, и это обещание должно быть видно глазами.
struct NetworkSettings: View {
    @Environment(AppEnvironment.self) private var env

    @State private var hosts: [NetworkHostSummary] = []
    @State private var total = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            DSText(headline, style: .title)
            DSText(
                "Rubis talks to the network only when you switch something on. "
                    + "Album notes are off by default; update checks come from Sparkle.",
                style: .caption, color: DS.Color.textSecondary)

            if hosts.isEmpty {
                Spacer()
                DSText("Nothing has left this machine.", style: .body, color: DS.Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.md) {
                        ForEach(hosts) { host in
                            row(host)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }

            HStack {
                Button("Refresh") { reload() }
                Spacer()
                Button("Clear log", role: .destructive) {
                    Task {
                        await env.networkLedger.clear()
                        reload()
                    }
                }
                .disabled(hosts.isEmpty)
            }
        }
        .padding(DS.Space.xl)
        .frame(width: 520, alignment: .leading)
        .task { reload() }
    }

    private var headline: String {
        switch total {
        case 0: return "No outgoing requests"
        case 1: return "1 outgoing request"
        default: return "\(total) outgoing requests"
        }
    }

    private func row(_ host: NetworkHostSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                DSText(host.host, style: .body)
                Spacer()
                DSText("\(host.count)", style: .numeric, color: DS.Color.textSecondary)
            }
            HStack(spacing: DS.Space.sm) {
                DSText(
                    host.purposes.joined(separator: " · "), style: .caption,
                    color: DS.Color.textSecondary)
                if host.failures > 0 {
                    DSText(
                        "\(host.failures) failed", style: .caption, color: DS.Color.warning)
                }
                Spacer()
                DSText(
                    host.last.formatted(date: .abbreviated, time: .shortened), style: .caption,
                    color: DS.Color.textTertiary)
            }
        }
    }

    private func reload() {
        Task {
            let events = await env.networkLedger.events()
            total = events.count
            hosts = NetworkLedger.summarize(events)
        }
    }
}
