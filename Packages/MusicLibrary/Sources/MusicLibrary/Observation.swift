import EscapementCore
import Foundation
import GRDB

/// ValueObservation wrappers (SPEC §10): DB changes arrive as AsyncSequences
/// delivered on the main actor for direct consumption by @Observable view models.
public enum LibraryObservation {
    /// Emits the full album list whenever the album table changes.
    public static func albums(db: any DatabaseAccess)
        -> AsyncValueObservation<[Album]>
    {
        ValueObservation
            .tracking { try Album.order(Column("sort_title")).fetchAll($0) }
            .values(in: db.reader, scheduling: .mainActor)
    }

    /// Emits tracks of one album whenever they change.
    public static func tracks(inAlbum albumId: Int64, db: any DatabaseAccess)
        -> AsyncValueObservation<[Track]>
    {
        ValueObservation
            .tracking {
                try Track
                    .filter(Column("album_id") == albumId)
                    .order(Column("disc_no").ascNullsLast, Column("track_no").ascNullsLast)
                    .fetchAll($0)
            }
            .values(in: db.reader, scheduling: .mainActor)
    }

    /// Emits the playlist list whenever playlists change.
    public static func playlists(db: any DatabaseAccess)
        -> AsyncValueObservation<[Playlist]>
    {
        ValueObservation
            .tracking { try Playlist.order(Column("name")).fetchAll($0) }
            .values(in: db.reader, scheduling: .mainActor)
    }
}
