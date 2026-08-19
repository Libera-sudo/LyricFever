//
//  QQMusicLyricProvider.swift
//  Lyric Fever
//

import Foundation
import StringMetric

class QQMusicLyricProvider: LyricProvider {
    private static let searchBaseURL = URL(string: "https://c.y.qq.com/soso/fcgi-bin/client_search_cp")!
    private static let lyricBaseURL = URL(string: "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg")!
    private static let lyricReferer = "https://y.qq.com/portal/player.html"

    private static func searchURL(trackName: String, artistName: String, limit: Int) -> URL? {
        var components = URLComponents(url: searchBaseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "w", value: "\(trackName) \(artistName)"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "n", value: String(limit)),
            URLQueryItem(name: "p", value: "1")
        ]
        return components?.url
    }

    private static func lyricRequest(songMID: String) -> URLRequest? {
        var components = URLComponents(url: lyricBaseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "songmid", value: songMID),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "nobase64", value: "1")
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue(lyricReferer, forHTTPHeaderField: "Referer")
        return request
    }

    var providerName = "QQ Music Lyric Provider"
    let fakeSafariUserAgentConfiguration = URLSessionConfiguration.default
    let fakeSafariUserAgentSession: URLSession

    init() {
        fakeSafariUserAgentConfiguration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_7_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15"
        ]
        fakeSafariUserAgentSession = URLSession(configuration: fakeSafariUserAgentConfiguration)
    }

    func fetchNetworkLyrics(trackName: String, trackID: String, currentlyPlayingArtist: String?, currentAlbumName: String?, duration: Int?) async throws -> NetworkFetchReturn {
        if let currentlyPlayingArtist, let currentAlbumName, let url = Self.searchURL(trackName: trackName, artistName: currentlyPlayingArtist, limit: 8) {
            print("the QQ Music search call is \(url.absoluteString)")
            let request = URLRequest(url: url)
            let searchData = try await fakeSafariUserAgentSession.data(for: request).0
            let search = try JSONDecoder().decode(QQMusicSearch.self, from: searchData)
            print("QQ Music: \(search.data.song.list.count) candidates")

            var acceptableCandidates: [(song: QQMusicSearch.Song, durationDifference: Int?, ground: String, order: Int)] = []
            for (order, song) in search.data.song.list.enumerated() {
                guard let artist = song.singer.first else { continue }

                let trackSimilarity = trackName.distance(between: song.songname)
                let albumSimilarity = currentAlbumName.distance(between: song.albumname)
                let artistSimilarity = currentlyPlayingArtist.distance(between: artist.name)
                let trueCount = [trackSimilarity, artistSimilarity, albumSimilarity].filter { $0 > 0.75 }.count
                let candidateDurationMS = song.interval * 1_000
                let durationDifference = duration.map { abs($0 - candidateDurationMS) }
                let durationMatches = durationDifference.map { $0 <= 2_000 } ?? false
                let textMatches = trueCount >= 2

                print("Similarity index: for track \(trackName) and QQ Music reply \(song.songname) is \(trackSimilarity)")
                print("Similarity index: for album \(currentAlbumName) and QQ Music reply \(song.albumname) is \(albumSimilarity)")
                print("Similarity index: for artist \(currentlyPlayingArtist) and QQ Music reply \(artist.name) is \(artistSimilarity)")

                guard durationMatches || textMatches else {
                    print("similarity conditions passed for QQ Music: \(trueCount) is less than 2 and duration does not match, therefore failing this QQ Music candidate.")
                    continue
                }

                let ground: String
                if durationMatches && textMatches {
                    ground = "duration and text agreement"
                } else if durationMatches {
                    ground = "duration agreement"
                } else {
                    ground = "text agreement"
                }
                acceptableCandidates.append((song, durationDifference, ground, order))
            }

            acceptableCandidates.sort {
                switch ($0.durationDifference, $1.durationDifference) {
                case let (lhs?, rhs?) where lhs != rhs:
                    return lhs < rhs
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return $0.order < $1.order
                }
            }

            for candidate in acceptableCandidates {
                guard let lyricRequest = Self.lyricRequest(songMID: candidate.song.songmid) else { continue }
                do {
                    let lyricData = try await fakeSafariUserAgentSession.data(for: lyricRequest).0
                    let response = try JSONDecoder().decode(QQMusicLyrics.self, from: lyricData)
                    guard let lyric = response.lyric, !lyric.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        continue
                    }

                    let cleaned = unescapeQQMusicHTMLEntities(in: lyric)
                    let parsed = LyricsParser(lyrics: cleaned).lyrics
                    guard !parsed.isEmpty else { continue }

                    print("QQ Music chose candidate \(candidate.song.songname) by \(candidate.ground).")
                    return NetworkFetchReturn(lyrics: parsed)
                } catch {
                    // A failed candidate should not prevent trying the remaining matches.
                    continue
                }
            }
        }
        return NetworkFetchReturn(lyrics: [])
    }
}

extension QQMusicLyricProvider {
    func search(trackName: String, artistName: String) async throws -> [SongResult] {
        guard let url = Self.searchURL(trackName: trackName, artistName: artistName, limit: 5) else {
            return []
        }
        let request = URLRequest(url: url)
        let searchData = try await fakeSafariUserAgentSession.data(for: request).0
        let search = try JSONDecoder().decode(QQMusicSearch.self, from: searchData)

        var results: [SongResult] = []
        for song in search.data.song.list {
            guard let firstArtist = song.singer.first,
                  let lyricRequest = Self.lyricRequest(songMID: song.songmid) else {
                continue
            }

            do {
                let lyricData = try await fakeSafariUserAgentSession.data(for: lyricRequest).0
                let response = try JSONDecoder().decode(QQMusicLyrics.self, from: lyricData)
                guard let lyric = response.lyric, !lyric.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }

                let cleaned = unescapeQQMusicHTMLEntities(in: lyric)
                let parsed = LyricsParser(lyrics: cleaned).lyrics
                guard !parsed.isEmpty else { continue }

                results.append(SongResult(lyricType: "QQ Music", songName: song.songname, albumName: song.albumname, artistName: firstArtist.name, lyrics: parsed))
            } catch {
                // Ignore per-item failure so the remaining results are preserved.
            }
        }
        return results
    }
}

private func unescapeQQMusicHTMLEntities(in text: String) -> String {
    var cleaned = text
    cleaned = cleaned.replacingOccurrences(of: "&apos;", with: "'")
    cleaned = cleaned.replacingOccurrences(of: "&quot;", with: "\"")
    cleaned = cleaned.replacingOccurrences(of: "&amp;", with: "&")
    cleaned = cleaned.replacingOccurrences(of: "&lt;", with: "<")
    cleaned = cleaned.replacingOccurrences(of: "&gt;", with: ">")
    cleaned = cleaned.replacingOccurrences(of: "&#39;", with: "'")
    cleaned = cleaned.replacingOccurrences(of: "&#x27;", with: "'")
    cleaned = cleaned.replacingOccurrences(of: "\\\n", with: "\n")
    return cleaned
}
