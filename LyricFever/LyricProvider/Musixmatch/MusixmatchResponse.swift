//
//  MusixmatchResponse.swift
//  Lyric Fever
//

struct MusixmatchTokenResponse: Decodable {
    let message: Message

    struct Message: Decodable {
        let header: MusixmatchHeader?
        let body: Body?

        enum CodingKeys: String, CodingKey {
            case header, body
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            header = try? container.decode(MusixmatchHeader.self, forKey: .header)
            body = try? container.decode(Body.self, forKey: .body)
        }
    }

    struct Body: Decodable {
        let userToken: String?

        enum CodingKeys: String, CodingKey {
            case userToken = "user_token"
        }
    }
}

struct MusixmatchMacroResponse: Decodable {
    let message: Message

    struct Message: Decodable {
        let header: MusixmatchHeader?
        let body: Body?

        enum CodingKeys: String, CodingKey {
            case header, body
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            header = try? container.decode(MusixmatchHeader.self, forKey: .header)
            body = try? container.decode(Body.self, forKey: .body)
        }
    }

    struct Body: Decodable {
        let macroCalls: MacroCalls?

        enum CodingKeys: String, CodingKey {
            case macroCalls = "macro_calls"
        }
    }

    struct MacroCalls: Decodable {
        let matcherTrackGet: TrackCall?
        let trackSubtitlesGet: SubtitleCall?

        enum CodingKeys: String, CodingKey {
            case matcherTrackGet = "matcher.track.get"
            case trackSubtitlesGet = "track.subtitles.get"
        }
    }

    struct TrackCall: Decodable {
        let message: TrackMessage?
    }

    struct TrackMessage: Decodable {
        let body: TrackBody?

        enum CodingKeys: String, CodingKey {
            case body
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Failed macro sub-calls may encode body as a non-object. Treat that as absent.
            body = try? container.decode(TrackBody.self, forKey: .body)
        }
    }

    struct TrackBody: Decodable {
        let track: Track?
    }

    struct Track: Decodable {
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let trackLength: Int?
        let instrumental: Int?
        let hasSubtitles: Int?

        enum CodingKeys: String, CodingKey {
            case trackName = "track_name"
            case artistName = "artist_name"
            case albumName = "album_name"
            case trackLength = "track_length"
            case instrumental
            case hasSubtitles = "has_subtitles"
        }
    }

    struct SubtitleCall: Decodable {
        let message: SubtitleMessage?
    }

    struct SubtitleMessage: Decodable {
        let body: SubtitleBody?

        enum CodingKeys: String, CodingKey {
            case body
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // No-subtitle and failed sub-calls do not always use the successful body shape.
            body = try? container.decode(SubtitleBody.self, forKey: .body)
        }
    }

    struct SubtitleBody: Decodable {
        let subtitleList: [SubtitleListItem]?

        enum CodingKeys: String, CodingKey {
            case subtitleList = "subtitle_list"
        }
    }

    struct SubtitleListItem: Decodable {
        let subtitle: Subtitle?
    }

    struct Subtitle: Decodable {
        let subtitleBody: String?

        enum CodingKeys: String, CodingKey {
            case subtitleBody = "subtitle_body"
        }
    }
}

struct MusixmatchHeader: Decodable {
    let statusCode: Int?
    let hint: String?

    enum CodingKeys: String, CodingKey {
        case statusCode = "status_code"
        case hint
    }
}
