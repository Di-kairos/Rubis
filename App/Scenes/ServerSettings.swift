import DesignSystem
import EscapementCore
import MusicLibrary
import SubsonicKit
import SwiftUI

/// Settings → Server (SPEC §6.1, §8): адрес Navidrome, логин и пароль.
/// Пароль уходит в связку ключей, всё остальное — в таблицу `source`.
/// В v1 сервер один: второй адрес заменяет первый, чтобы не плодить
/// полусохранённые источники.
struct ServerSettings: View {
    @Environment(AppEnvironment.self) private var env

    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var status = Status.idle
    @State private var existing: Source?
    /// Идёт синхронизация каталога — кнопка занята.
    @State private var syncing = false

    /// Результат «Test connection» — явный, как требует acceptance фазы 6.
    private enum Status: Equatable {
        case idle
        case testing
        case ok(String)
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            Form {
                TextField("Server URL", text: $serverURL, prompt: Text("https://music.example.com"))
                    .textContentType(.URL)
                TextField("Username", text: $username)
                    .textContentType(.username)
                SecureField("Password", text: $password)
                    .textContentType(.password)
            }
            .onChange(of: serverURL) { status = .idle }
            .onChange(of: username) { status = .idle }
            .onChange(of: password) { status = .idle }

            HStack(spacing: DS.Space.md) {
                Button("Test connection") { test() }
                    .disabled(!isFilled || status == .testing)
                Button("Save") { save() }
                    .disabled(!isFilled)
                if let existing {
                    // Каталог тянется по явной команде: приложение не ходит
                    // в сеть само (SPEC §1.2). ⌘R делает то же для всех источников.
                    Button(syncing ? "Syncing…" : "Sync now") { syncNow(existing) }
                        .disabled(syncing)
                    Button("Remove", role: .destructive) { remove() }
                }
                Spacer()
            }

            statusLine
        }
        .padding(DS.Space.xl)
        .frame(width: 520, alignment: .leading)
        .task { load() }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case .idle:
            // Место под строку держится всегда — иначе кнопки прыгают
            // в момент появления результата (урок 0.8.4 про указатель).
            DSText(" ", style: .caption, color: DS.Color.textTertiary)
        case .testing:
            DSText("Checking…", style: .caption, color: DS.Color.textSecondary)
        case .ok(let text):
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "checkmark.circle").foregroundStyle(DS.Color.accent)
                    .accessibilityHidden(true)
                DSText(text, style: .caption, color: DS.Color.textSecondary)
            }
        case .failed(let text):
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(DS.Color.warning)
                    .accessibilityHidden(true)
                DSText(text, style: .caption, color: DS.Color.textSecondary)
            }
        }
    }

    private var isFilled: Bool {
        !serverURL.trimmingCharacters(in: .whitespaces).isEmpty && !username.isEmpty
            && !password.isEmpty
    }

    // MARK: - Действия

    /// Синхронизация каталога по кнопке. Прогресс показывает та же полоска
    /// в сайдбаре, что и скан папок.
    private func syncNow(_ source: Source) {
        syncing = true
        Task {
            await env.sync(server: source)
            syncing = false
        }
    }

    private func load() {
        existing = (try? env.sourceRepo.all())?.first { $0.kind == .subsonic }
        guard let source = existing else { return }
        serverURL = source.serverUrl ?? ""
        username = source.username ?? ""
        password =
            SubsonicPasswordStore.load(
                host: SubsonicAccount.host(of: serverURL), username: username) ?? ""
    }

    private func test() {
        status = .testing
        let url = serverURL
        let user = username
        let secret = password
        Task {
            do {
                let client = try SubsonicClient(
                    serverURL: url, username: user, password: secret)
                try await client.ping()
                status = .ok("Connected as \(user)")
            } catch {
                status = .failed(
                    (error as? SubsonicError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    private func save() {
        let trimmed = serverURL.trimmingCharacters(in: .whitespaces)
        let host = SubsonicAccount.host(of: trimmed)
        guard !host.isEmpty else {
            status = .failed(SubsonicError.invalidServerURL.errorDescription ?? "")
            return
        }
        // Смена адреса или логина оставляет старый пароль сиротой — убираем.
        if let old = existing, let oldURL = old.serverUrl, let oldUser = old.username,
            oldURL != trimmed || oldUser != username
        {
            SubsonicPasswordStore.delete(host: SubsonicAccount.host(of: oldURL), username: oldUser)
        }
        SubsonicPasswordStore.save(password, host: host, username: username)

        var source =
            existing ?? Source(kind: .subsonic, displayName: host, serverUrl: trimmed)
        source.displayName = host
        source.serverUrl = trimmed
        source.username = username
        do {
            try env.sourceRepo.upsert(source)
            existing = source
            status = .ok("Saved")
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func remove() {
        guard let source = existing else { return }
        if let url = source.serverUrl, let user = source.username {
            SubsonicPasswordStore.delete(host: SubsonicAccount.host(of: url), username: user)
        }
        try? env.sourceRepo.delete(id: source.id)
        existing = nil
        serverURL = ""
        username = ""
        password = ""
        status = .idle
    }
}
