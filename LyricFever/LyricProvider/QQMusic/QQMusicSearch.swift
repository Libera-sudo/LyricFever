//
//  QQMusicSearch.swift
//  Lyric Fever
//

struct QQMusicSearch: Decodable {
    let data: SearchData

    struct SearchData: Decodable {
        let song: SongData
    }

    struct SongData: Decodable {
        let list: [Song]
    }

    struct Song: Decodable {
        let songmid: String
        let songname: String
        let albumname: String
        let interval: Int // seconds
        let singer: [Singer]
    }

    struct Singer: Decodable {
        let name: String
    }
}
