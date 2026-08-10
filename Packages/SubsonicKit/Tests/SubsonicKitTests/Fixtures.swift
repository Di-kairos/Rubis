import Foundation

/// Зафиксированные ответы Navidrome (TASKS фаза 6). Тесты не ходят в сеть —
/// транспорт клиента подменяется и отдаёт эти строки.
enum Fixtures {
    static let ping = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","type":"navidrome",
        "serverVersion":"0.53.3","openSubsonic":true}}
        """

    static let pingFailed = """
        {"subsonic-response":{"status":"failed","version":"1.16.1",
        "error":{"code":40,"message":"Wrong username or password"}}}
        """

    static let artists = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","artists":{"index":[
        {"name":"A","artist":[{"id":"ar-1","name":"All India Radio","albumCount":3}]},
        {"name":"B","artist":[
        {"id":"ar-2","name":"Buddha-Bar","albumCount":28},
        {"id":"ar-3","name":"Bill Evans","albumCount":12}]}]}}}
        """

    static let artistsEmpty = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","artists":{"index":[]}}}
        """

    static let albumList = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","albumList2":{"album":[
        {"id":"al-1","name":"Eternal","artist":"All India Radio","artistId":"ar-1",
        "coverArt":"al-1","songCount":14,"duration":3120,"year":2019},
        {"id":"al-2","name":"XXVIII","artist":"Buddha-Bar","artistId":"ar-2",
        "coverArt":"al-2","songCount":30,"duration":9591}]}}}
        """

    static let albumListEmpty = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","albumList2":{}}}
        """

    /// Треки с расширениями OpenSubsonic (samplingRate/bitDepth/channelCount)
    /// и без них — второй трек проверяет старый сервер.
    static let album = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","album":{
        "id":"al-1","name":"Eternal","artist":"All India Radio","artistId":"ar-1",
        "coverArt":"al-1","songCount":2,"duration":429,"year":2019,"song":[
        {"id":"tr-1","title":"The Hidden One","album":"Eternal","artist":"All India Radio",
        "albumId":"al-1","artistId":"ar-1","coverArt":"al-1","track":1,"discNumber":1,
        "year":2019,"duration":193,"size":33554432,"suffix":"flac",
        "contentType":"audio/flac","bitRate":1411,"samplingRate":44100,"bitDepth":24,
        "channelCount":2},
        {"id":"tr-2","title":"Moviestar","album":"Eternal","artist":"All India Radio",
        "albumId":"al-1","track":2,"duration":236,"suffix":"flac"}]}}}
        """

    static let artist = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","artist":{
        "id":"ar-1","name":"All India Radio","albumCount":1,"album":[
        {"id":"al-1","name":"Eternal","artist":"All India Radio","artistId":"ar-1",
        "songCount":14,"duration":3120,"year":2019}]}}}
        """

    static let notJSON = "<html><body>gateway timeout</body></html>"
}
