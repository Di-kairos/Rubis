import Foundation

/// Разбор CUE-листа: одна большая запись плюс текстовый файл с границами
/// дорожек (D-013). Так лежат рипы дисков одним FLAC — без CUE такой альбом
/// играется одной сорокаминутной дорожкой.
///
/// Разбираем ровно то, что нужно библиотеке: заголовок альбома, исполнителя,
/// год, жанр и границы треков. `CATALOG`, `ISRC`, `FLAGS`, `SONGWRITER`,
/// `POSTGAP` пропускаются молча — на воспроизведение они не влияют.
public struct CueSheet: Equatable, Sendable {

    public struct Track: Equatable, Sendable {
        public var number: Int
        public var title: String?
        public var performer: String?
        /// Начало дорожки в секундах от начала файла — `INDEX 01`.
        public var start: Double
        /// Конец — начало следующей дорожки того же файла; `nil` у последней:
        /// она играет до конца файла, длина которого известна только декодеру.
        public var end: Double?

        public init(
            number: Int, title: String? = nil, performer: String? = nil, start: Double,
            end: Double? = nil
        ) {
            self.number = number
            self.title = title
            self.performer = performer
            self.start = start
            self.end = end
        }
    }

    /// Дорожки одного аудиофайла. Обычный рип — один файл на весь диск;
    /// встречаются и CUE, где у каждой дорожки свой файл (тогда границ нет).
    public struct File: Equatable, Sendable {
        public var name: String
        public var tracks: [Track]

        public init(name: String, tracks: [Track]) {
            self.name = name
            self.tracks = tracks
        }
    }

    public var title: String?
    public var performer: String?
    public var date: Int?
    public var genre: String?
    public var files: [File]

    /// Все дорожки листа подряд — порядок как в файле.
    public var tracks: [Track] { files.flatMap(\.tracks) }

    // MARK: - Reading

    /// Чтение с диска. CUE родом из эпохи до UTF-8: рипы 2000-х приходят в
    /// windows-1251 или UTF-16, и упереться в кодировку значит потерять
    /// кириллические названия целиком.
    public static func read(contentsOf url: URL) throws -> CueSheet? {
        let data = try Data(contentsOf: url)
        let encodings: [String.Encoding] = [.utf8, .utf16, .windowsCP1251, .isoLatin1]
        for encoding in encodings {
            guard var text = String(data: data, encoding: encoding) else { continue }
            // BOM остаётся первым символом строки и ломает первую команду.
            if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
            guard let sheet = parse(text), !sheet.files.isEmpty else { continue }
            return sheet
        }
        return nil
    }

    // MARK: - Parsing

    public static func parse(_ text: String) -> CueSheet? {
        var sheet = CueSheet(files: [])
        var files: [File] = []
        var currentFile: String?
        var currentTracks: [Track] = []
        var pending: (number: Int, title: String?, performer: String?, start: Double?)?

        func closeTrack() {
            guard let track = pending else { return }
            // Дорожка без INDEX 01 нам бесполезна: начало неизвестно.
            if let start = track.start {
                currentTracks.append(
                    Track(
                        number: track.number, title: track.title, performer: track.performer,
                        start: start))
            }
            pending = nil
        }

        func closeFile() {
            closeTrack()
            guard let name = currentFile else {
                currentTracks = []
                return
            }
            files.append(File(name: name, tracks: withEnds(currentTracks)))
            currentTracks = []
            currentFile = nil
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let (command, rest) = split(line)
            switch command.uppercased() {
            case "FILE":
                // Дорожка, начатая до строки FILE, продолжается в следующем
                // файле: рип «дорожка в файл» пишет предзазор концом прошлого
                // (INDEX 00), а начало — уже после FILE (INDEX 01). Бросить её
                // здесь значит потерять и дорожку, и её название.
                let carried = pending?.start == nil ? pending : nil
                closeFile()
                currentFile = unquoteFileName(rest)
                pending = carried
            case "TRACK":
                closeTrack()
                let parts = rest.split(separator: " ", omittingEmptySubsequences: true)
                // «TRACK 03 AUDIO»; дорожки данных (MODE1/2352) пропускаем —
                // их нельзя играть, а нумерацию они сдвигают.
                guard let number = parts.first.flatMap({ Int($0) }),
                    parts.count < 2 || parts[1].uppercased() == "AUDIO"
                else { continue }
                pending = (number, nil, nil, nil)
            case "TITLE":
                if pending != nil {
                    pending?.title = unquote(rest)
                } else {
                    sheet.title = unquote(rest)
                }
            case "PERFORMER":
                if pending != nil {
                    pending?.performer = unquote(rest)
                } else {
                    sheet.performer = unquote(rest)
                }
            case "INDEX":
                let parts = rest.split(separator: " ", omittingEmptySubsequences: true)
                guard parts.count >= 2, let index = Int(parts[0]),
                    let seconds = time(String(parts[1]))
                else { continue }
                // INDEX 00 — предзазор предыдущей дорожки, начало не он.
                if index == 1 { pending?.start = seconds }
            case "REM":
                let (keyword, value) = split(rest)
                switch keyword.uppercased() {
                case "DATE": sheet.date = year(unquote(value))
                case "GENRE": sheet.genre = unquote(value)
                default: break
                }
            default:
                continue
            }
        }
        closeFile()
        sheet.files = files
        return files.isEmpty ? nil : sheet
    }

    /// Конец дорожки — начало следующей в том же файле. У последней конца нет.
    ///
    /// Дорожка, начинающаяся не позже предыдущей, отбрасывается: лист врёт, а
    /// отрицательная или нулевая длина дальше по коду превращается в мусорную
    /// длительность и регион, который декодер не сможет отдать.
    private static func withEnds(_ tracks: [Track]) -> [Track] {
        var ordered: [Track] = []
        for track in tracks {
            guard let last = ordered.last else {
                ordered.append(track)
                continue
            }
            if track.start > last.start { ordered.append(track) }
        }
        return ordered.enumerated().map { index, track in
            var copy = track
            copy.end = index + 1 < ordered.count ? ordered[index + 1].start : nil
            return copy
        }
    }

    /// Потолок поля минут. CD длиннее 99 минут не бывает, но некоторые
    /// утилиты пишут трёхзначные минуты для длинных образов; предел держит
    /// произведение «секунды × частота» далеко внутри `Int64` при любой
    /// поддерживаемой частоте — иначе `Int64(Double)` в регионе аварийно
    /// завершает приложение.
    static let maxMinutes = 100_000

    /// `MM:SS:FF`, где FF — кадры CD, их в секунде ровно 75.
    ///
    /// Только целые поля в своих диапазонах: `Double("inf")`, `nan`, `1e300`
    /// и `00:99:99` разбираются без ошибки, а потом рушат преобразование в
    /// кадры. Невалидное время — это отсутствующий INDEX, дорожка без начала
    /// отбрасывается выше по коду.
    static func time(_ value: String) -> Double? {
        let parts = value.split(separator: ":")
        guard parts.count == 3, let minutes = Int(parts[0]), let seconds = Int(parts[1]),
            let frames = Int(parts[2]),
            (0...maxMinutes).contains(minutes), (0..<60).contains(seconds),
            (0..<75).contains(frames)
        else { return nil }
        return Double(minutes) * 60 + Double(seconds) + Double(frames) / 75
    }

    private static func split(_ line: String) -> (String, String) {
        guard let space = line.firstIndex(of: " ") else { return (line, "") }
        return (
            String(line[line.startIndex..<space]),
            String(line[line.index(after: space)...]).trimmingCharacters(in: .whitespaces)
        )
    }

    private static func unquote(_ value: String) -> String? {
        var text = value.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("\""), text.hasSuffix("\""), text.count >= 2 {
            text = String(text.dropFirst().dropLast())
        }
        return text.isEmpty ? nil : text
    }

    /// `FILE "Kind of Blue.flac" WAVE` — имя в кавычках, тип после них.
    /// Без кавычек имя не может содержать пробел, так что берём первое слово.
    private static func unquoteFileName(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("\""), let closing = text.dropFirst().firstIndex(of: "\"") {
            let name = String(text[text.index(after: text.startIndex)..<closing])
            return name.isEmpty ? nil : name
        }
        return text.split(separator: " ").first.map(String.init)
    }

    /// `REM DATE` бывает и «1959», и «1959-08-17», и «Recorded 1959».
    private static func year(_ value: String?) -> Int? {
        guard let value else { return nil }
        var digits = ""
        for character in value {
            if character.isNumber {
                digits.append(character)
                if digits.count == 4 { break }
            } else if !digits.isEmpty {
                digits = ""
            }
        }
        guard digits.count == 4, let year = Int(digits), year > 1000, year < 2200 else {
            return nil
        }
        return year
    }

    public init(
        title: String? = nil, performer: String? = nil, date: Int? = nil, genre: String? = nil,
        files: [File]
    ) {
        self.title = title
        self.performer = performer
        self.date = date
        self.genre = genre
        self.files = files
    }
}
