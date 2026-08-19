//
//  MusixmatchLyricProvider.swift
//  Lyric Fever
//

import Foundation

@MainActor
final class MusixmatchLyricProvider: LyricProvider {
    private static let tokenBaseURL = URL(string: "https://apic-desktop.musixmatch.com/ws/1.1/token.get")!
    private static let macroBaseURL = URL(string: "https://apic-desktop.musixmatch.com/ws/1.1/macro.subtitles.get")!
    private static let appID = "web-desktop-app-v1.0"

    let providerName = "Musixmatch Lyric Provider"

    private let session: URLSession
    private var cachedUserToken: String?
    private var tokenTask: Task<String?, Never>?

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = ["Cookie": "x-mxm-token-guid="]
        session = URLSession(configuration: configuration)
    }

    func fetchNetworkLyrics(
        trackName: String,
        trackID: String,
        currentlyPlayingArtist: String?,
        currentAlbumName: String?,
        duration: Int?
    ) async throws -> NetworkFetchReturn {
        guard let currentlyPlayingArtist,
              let match = try await fetchMatch(trackName: trackName, artistName: currentlyPlayingArtist) else {
            return NetworkFetchReturn(lyrics: [])
        }

        if let duration {
            guard let trackLength = match.track.trackLength else {
                return NetworkFetchReturn(lyrics: [])
            }
            let matchedDurationMS = trackLength * 1_000
            guard abs(duration - matchedDurationMS) <= 2_000 else {
                print("Musixmatch: rejecting the best match because its duration differs by more than 2000 ms")
                return NetworkFetchReturn(lyrics: [])
            }
        }

        if match.track.instrumental == 1 {
            return NetworkFetchReturn(lyrics: [], isInstrumental: true)
        }

        guard let subtitleBody = match.subtitleBody,
              !subtitleBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return NetworkFetchReturn(lyrics: [])
        }
        let parsed = LyricsParser(lyrics: subtitleBody).lyrics
        guard !parsed.isEmpty, parsed.last?.startTimeMS != 0.0 else {
            return NetworkFetchReturn(lyrics: [])
        }
        return NetworkFetchReturn(lyrics: parsed)
    }

    func search(trackName: String, artistName: String) async throws -> [SongResult] {
        guard let match = try await fetchMatch(trackName: trackName, artistName: artistName),
              match.track.hasSubtitles == 1,
              let matchedTrackName = match.track.trackName,
              let matchedArtistName = match.track.artistName,
              let matchedAlbumName = match.track.albumName,
              let trackLength = match.track.trackLength,
              let subtitleBody = match.subtitleBody,
              !subtitleBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let parsed = LyricsParser(lyrics: subtitleBody).lyrics
        guard !parsed.isEmpty, parsed.last?.startTimeMS != 0.0 else {
            return []
        }

        return [SongResult(
            lyricType: "Musixmatch",
            songName: matchedTrackName,
            albumName: matchedAlbumName,
            artistName: matchedArtistName,
            lyrics: parsed,
            // Musixmatch answers 0 for tracks whose length it does not know. Zero is not a
            // duration, and leaving it in printed "0:00" beside a four-minute song.
            durationMS: trackLength > 0 ? trackLength * 1_000 : nil
        )]
    }

    private func fetchMatch(trackName: String, artistName: String) async throws -> Match? {
        guard let userToken = await userToken(),
              let request = Self.macroRequest(
                trackName: trackName,
                artistName: artistName,
                userToken: userToken
              ) else {
            return nil
        }

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            print("Musixmatch macro request failed at the HTTP layer")
            return nil
        }

        let decoded = try JSONDecoder().decode(MusixmatchMacroResponse.self, from: data)
        guard decoded.message.header?.statusCode == 200 else {
            print("Musixmatch macro request failed with API status \(decoded.message.header?.statusCode ?? -1)")
            return nil
        }
        guard let macroCalls = decoded.message.body?.macroCalls,
              let track = macroCalls.matcherTrackGet?.message?.body?.track else {
            return nil
        }
        let subtitleBody = macroCalls.trackSubtitlesGet?.message?.body?.subtitleList?.first?.subtitle?.subtitleBody
        return Match(track: track, subtitleBody: subtitleBody)
    }

    private func userToken() async -> String? {
        if let cachedUserToken {
            return cachedUserToken
        }
        if let tokenTask {
            return await tokenTask.value
        }

        let tokenTask = Task<String?, Never> { [session] in
            guard let request = Self.tokenRequest() else {
                print("Musixmatch token request could not be constructed")
                return nil
            }
            do {
                let (data, response) = try await session.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    print("Musixmatch token request failed at the HTTP layer")
                    return nil
                }
                let decoded = try JSONDecoder().decode(MusixmatchTokenResponse.self, from: data)
                guard decoded.message.header?.statusCode == 200,
                      let token = decoded.message.body?.userToken,
                      !token.isEmpty else {
                    let status = decoded.message.header?.statusCode ?? -1
                    let hint = decoded.message.header?.hint ?? "no hint"
                    print("Musixmatch token request failed with API status \(status) (\(hint))")
                    return nil
                }
                return token
            } catch {
                print("Musixmatch token request failed: \(error.localizedDescription)")
                return nil
            }
        }
        self.tokenTask = tokenTask

        let token = await tokenTask.value
        cachedUserToken = token
        return token
    }

    private static func tokenRequest() -> URLRequest? {
        var components = URLComponents(url: tokenBaseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "app_id", value: appID)]
        return components?.url.map { URLRequest(url: $0) }
    }

    private static func macroRequest(trackName: String, artistName: String, userToken: String) -> URLRequest? {
        var components = URLComponents(url: macroBaseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "namespace", value: "lyrics_richsynched"),
            URLQueryItem(name: "subtitle_format", value: "lrc"),
            URLQueryItem(name: "app_id", value: appID),
            URLQueryItem(name: "usertoken", value: userToken),
            URLQueryItem(name: "q_track", value: trackName),
            URLQueryItem(name: "q_artist", value: artistName)
        ]
        return components?.url.map { URLRequest(url: $0) }
    }

    private struct Match {
        let track: MusixmatchMacroResponse.Track
        let subtitleBody: String?
    }
}
