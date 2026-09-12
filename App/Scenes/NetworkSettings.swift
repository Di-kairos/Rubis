import DesignSystem
import EscapementCore
import SwiftUI

/// Settings → Network: журнал записанных исходящих операций приложения.
/// Смысл раздела — не настройка, а свидетельство: SPEC §1.2 обещает ноль
/// запросов по умолчанию, и это обещание должно быть видно глазами. Панель
/// описывает содержимое журнала, а не утверждает, что запросов не было:
/// журнал держит последние N записей и знает только то, что в него
/// записал наш код.
struct NetworkSettings: View {
    @Environment(AppEnvironment.self) private var env

    @State private var hosts: [NetworkHostSummary] = []
    @State private var total = 0
    @State private var clearedAt: Date?
    @State private var capacity = 1000

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            DSText(headline, style: .title)
            DSText(
                "Rubis talks to the network only when you switch something on. "
                    + "Album notes are off by default; update checks come from Sparkle.",
                style: .caption, color: DS.Color.textSecondary)
            DSText(
                "Shows up to \(capacity.formatted()) recent recorded network operations. "
                    + "Some network activity may not appear here.",
                style: .caption, color: DS.Color.textSecondary)

            if hosts.isEmpty {
                Spacer()
                DSText(
                    clearedAt == nil
                        ? "No network activity recorded yet."
                        : "No network activity recorded since the log was cleared.",
                    style: .body, color: DS.Color.textSecondary
                )
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
        case 0: return "No recorded network operations"
        case 1: return "1 recorded network operation"
        default: return "\(total) recorded network operations"
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
                    color: DS.Color.textMuted)
            }
        }
    }

    private func reload() {
        Task {
            let events = await env.networkLedger.events()
            total = events.count
            hosts = NetworkLedger.summarize(events)
            clearedAt = await env.networkLedger.clearedAt()
            capacity = await env.networkLedger.capacity
        }
    }
}
