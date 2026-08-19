//
//  NetEaseLyricsProvider.swift
//  Lyric Fever
//
//  Created by Avi Wadhwa on 2025-06-16.
//

import Foundation
import StringMetric

class NetEaseLyricProvider: LyricProvider {
    private static let baseURL = URL(string: "https://music.163.com/api")!

    private static func searchURL(trackName: String, artistName: String, limit: Int) -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent("search/get"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "s", value: "\(trackName) \(artistName)"),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        return components?.url
    }

    private static func lyricURL(songID: Int) -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent("song/lyric"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "id", value: String(songID)),
            URLQueryItem(name: "lv", value: "1"),
            URLQueryItem(name: "kv", value: "1"),
            URLQueryItem(name: "tv", value: "-1")
        ]
        return components?.url
    }

    var providerName = "NetEase Lyric Provider"
    // Fake Spotify User Agent
    // Spotify's started blocking my app's useragent. A win honestly 🤣
    let fakeSpotifyUserAgentconfig = URLSessionConfiguration.default
    let fakeSpotifyUserAgentSession: URLSession
    
    init() {
        // Set user agents for Spotify and LRCLIB
        fakeSpotifyUserAgentconfig.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_7_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15"]
        fakeSpotifyUserAgentSession = URLSession(configuration: fakeSpotifyUserAgentconfig)
    }
    
    func fetchNetworkLyrics(trackName: String, trackID: String, currentlyPlayingArtist: String?, currentAlbumName: String?, duration: Int?) async throws -> NetworkFetchReturn {
        if let currentlyPlayingArtist, let currentAlbumName, let url = Self.searchURL(trackName: trackName, artistName: currentlyPlayingArtist, limit: 8) {
            print("the netease search call is \(url.absoluteString)")
            let request = URLRequest(url: url)
            let urlResponseAndData = try await fakeSpotifyUserAgentSession.data(for: request)
            let neteasesearch = try JSONDecoder().decode(NetEaseSearch.self, from: urlResponseAndData.0)
            print("NetEase: \(neteasesearch.result.songs.count) candidates")

            var acceptableCandidates: [(song: NetEaseSearch.Result.Song, durationDifference: Int?, ground: String, order: Int)] = []
            for (order, neteaseResult) in neteasesearch.result.songs.enumerated() {
                guard let neteaseArtist = neteaseResult.artists.first else { continue }

                let trackSimilarity = trackName.distance(between: neteaseResult.name)
                let albumSimilarity = currentAlbumName.distance(between: neteaseResult.album.name)
                let artistSimilarity = currentlyPlayingArtist.distance(between: neteaseArtist.name)
                let trueCount = [trackSimilarity, artistSimilarity, albumSimilarity].filter { $0 > 0.75 }.count
                let durationDifference = duration.map { abs($0 - neteaseResult.duration) }
                let durationMatches = durationDifference.map { $0 <= 2_000 } ?? false
                let textMatches = trueCount >= 2

                print("Similarity index: for track \(trackName) and netease reply \(neteaseResult.name) is \(trackSimilarity)")
                print("Similarity index: for album \(currentAlbumName) and netease reply \(neteaseResult.album.name) is \(albumSimilarity)")
                print("Similarity index: for artist \(currentlyPlayingArtist) and netease reply \(neteaseArtist.name) is \(artistSimilarity)")

                guard durationMatches || textMatches else {
                    print("similarity conditions passed for NetEase: \(trueCount) is less than 2 and duration does not match, therefore failing this NetEase candidate.")
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
                acceptableCandidates.append((neteaseResult, durationDifference, ground, order))
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
                guard let lyricURL = Self.lyricURL(songID: candidate.song.id) else { continue }
                let lyricRequest = URLRequest(url: lyricURL)
                let urlResponseAndDataLyrics = try await fakeSpotifyUserAgentSession.data(for: lyricRequest)
                let neteaseLyrics = try JSONDecoder().decode(NetEaseLyrics.self, from: urlResponseAndDataLyrics.0)
                guard let neteaselrc = neteaseLyrics.lrc, let neteaseLrcString = neteaselrc.lyric else { continue }

                // Sanitize HTML entities and stray escapes before parsing
                let cleaned = unescapeHTMLEntities(in: neteaseLrcString)

                let parser = LyricsParser(lyrics: cleaned)
                // NetEase incorrectly advertises lyrics for EVERY song when it only has the name, artist, composer at 0.0 *sigh*
                if parser.lyrics.last?.startTimeMS == 0.0 {
                    continue
                }
                print("NetEase chose candidate \(candidate.song.name) by \(candidate.ground).")
                return NetworkFetchReturn(lyrics: parser.lyrics)
            }
        }
        return NetworkFetchReturn(lyrics: [])
    }
}


// MARK: - HTML entity unescape
private func unescapeHTMLEntities(in text: String) -> String {
    var s = text
    // Common named entities
    s = s.replacingOccurrences(of: "&apos;", with: "'")
    s = s.replacingOccurrences(of: "&quot;", with: "\"")
    s = s.replacingOccurrences(of: "&amp;", with: "&")
    s = s.replacingOccurrences(of: "&lt;", with: "<")
    s = s.replacingOccurrences(of: "&gt;", with: ">")
    // Common numeric entity often used for apostrophe
    s = s.replacingOccurrences(of: "&#39;", with: "'")
    s = s.replacingOccurrences(of: "&#x27;", with: "'")
    // Normalize stray backslashes that sometimes trail lines from API payloads
    // Keep escaped newlines for LyricsParser to convert, but remove trailing backslashes.
    s = s.replacingOccurrences(of: "\\\n", with: "\n")
    // If payload includes escaped newline markers already, LyricsParser handles "\\n" -> "\n".
    return s
}

// MARK: - New: Search implementation
extension NetEaseLyricProvider {
    func search(trackName: String, artistName: String) async throws -> [SongResult] {
        // Ask for up to 5
        guard let url = Self.searchURL(trackName: trackName, artistName: artistName, limit: 5) else {
            return []
        }
        let request = URLRequest(url: url)
        let urlResponseAndData = try await fakeSpotifyUserAgentSession.data(for: request)
        let neteasesearch = try JSONDecoder().decode(NetEaseSearch.self, from: urlResponseAndData.0)
        
        var results: [SongResult] = []
        for song in neteasesearch.result.songs {
            guard let firstArtist = song.artists.first else { continue }
//            // Similarity checks (reuse thresholds)
//            let conditions = [
//                track.distance(between: song.name) > 0.75,
//                artist.distance(between: firstArtist.name) > 0.75,
//                (album ?? "").distance(between: song.album.name) > 0.75
//            ]
//            let trueCount = conditions.filter { $0 }.count
//            if trueCount < 2 { continue }
            
            // Fetch lyrics
            guard let lyricURL = Self.lyricURL(songID: song.id) else { continue }
            do {
                let lyricsData = try await fakeSpotifyUserAgentSession.data(from: lyricURL).0
                let neteaseLyrics = try JSONDecoder().decode(NetEaseLyrics.self, from: lyricsData)
                guard let lrcText = neteaseLyrics.lrc?.lyric else { continue }
                let cleaned = unescapeHTMLEntities(in: lrcText)
                let parsed = LyricsParser(lyrics: cleaned).lyrics
                if parsed.last?.startTimeMS == 0.0 { continue }
                
                results.append(SongResult(lyricType: "NetEase", songName: song.name, albumName: song.album.name, artistName: firstArtist.name, lyrics: parsed))
            } catch {
                // ignore per-item failure
            }
        }
        return results
    }
}
