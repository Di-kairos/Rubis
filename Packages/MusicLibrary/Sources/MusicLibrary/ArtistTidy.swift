import EscapementCore
import GRDB

/// Уборка таблицы `artist` в конце скана.
///
/// Двойники — наследие ключа по сырому ARTISTSORT: тег давал «Kamasi
/// Washington», альбомный исполнитель — «kamasi washington», и у одного
/// имени выходило две строки, одна из них без альбомов (S23). Сироты
/// остаются после перетегивания: трек уходит к новому имени, старое висит
/// в списке Artists пустым.
enum ArtistTidy {
    /// Сливает строки с одним нормализованным именем в самую раннюю и
    /// удаляет артистов, на которых не ссылается ни трек, ни альбом.
    /// ponytail: SubsonicSync создаёт артиста отдельной транзакцией до вставки
    /// альбома — уборка, вклинившаяся между ними, снимет его, и синк этого
    /// альбома упадёт до следующего прохода. Закрывать общей транзакцией синка.
    static func run(_ database: Database) throws {
        var survivors: [String: Int64] = [:]
        for artist in try Artist.order(Column("id")).fetchAll(database) {
            guard let id = artist.id else { continue }
            let key = Normalize.sortName(for: artist.name)
            guard let survivor = survivors[key] else {
                survivors[key] = id
                continue
            }
            for table in ["track", "album"] {
                try database.execute(
                    sql: "UPDATE \(table) SET artist_id = ? WHERE artist_id = ?",
                    arguments: [survivor, id])
            }
            _ = try Artist.deleteOne(database, key: id)
        }
        // Ключ выжившего мог прийти из тега — выравниваем, иначе следующий
        // скан по нормализованному ключу снова создал бы двойника.
        for (key, id) in survivors {
            try database.execute(
                sql: "UPDATE artist SET sort_name = ? WHERE id = ? AND sort_name <> ?",
                arguments: [key, id, key])
        }
        try database.execute(
            sql: """
                DELETE FROM artist
                WHERE id NOT IN (SELECT artist_id FROM track WHERE artist_id IS NOT NULL)
                  AND id NOT IN (SELECT artist_id FROM album WHERE artist_id IS NOT NULL)
                """)
    }
}
