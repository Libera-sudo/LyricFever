//
//  SongResult.swift
//  Lyric Fever
//
//  Created by Avi Wadhwa on 2025-09-06.
//

import Foundation


struct SongResult: Identifiable {
    let lyricType: String
    let songName: String
    let albumName: String
    let artistName: String
    let id = UUID()
    let lyrics: [LyricLine]
    let durationMS: Int?

    init(lyricType: String, songName: String, albumName: String, artistName: String,
         lyrics: [LyricLine], durationMS: Int?) {
        self.lyricType = lyricType
        self.songName = songName
        self.albumName = Self.withoutPlaceholder(albumName)
        self.artistName = artistName
        self.lyrics = lyrics
        self.durationMS = durationMS
    }

    /// Drops the text people type into a field they are not allowed to leave blank.
    ///
    /// LRCLIB's catalogue is contributed by its listeners, and the album field collects whatever
    /// was to hand: the literal word "null", "unknown", a bare dash. Those say nothing and read
    /// as a bug in this app. Anything else the uploader wrote -- a date, even a running time --
    /// was meant, and is shown as given rather than second-guessed.
    private static func withoutPlaceholder(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let placeholders: Set<String> = ["null", "none", "nil", "n/a", "na", "unknown", "-", "--"]
        return placeholders.contains(trimmed.lowercased()) ? "" : trimmed
    }
}
