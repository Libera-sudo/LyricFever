//
//  Player.swift
//  Lyric Fever
//
//  Created by Avi Wadhwa on 2025-07-18.
//

import Foundation
import AppKit

protocol Player {
    // track details
    var albumName: String? { get }
    var artistName: String? { get }
    var trackName: String? { get }
    
    // track timing details
    @MainActor
    var currentTime: TimeInterval? { get }
    var duration: Int? { get }
    
    // player details
    var isAuthorized: Bool { get }
    var isPlaying: Bool { get }
    var isRunning: Bool { get }
    
    // playback controls, driven from the menubar window
    func togglePlayback()
    func rewind()
    func forward()

    // album art, shown in the menubar window and used to derive the accent colour
    @MainActor
    var artworkImage: NSImage? { get async }
//    var artworkImageURL: URL? { get }
    
    // menubar behaviour
    func activate()

    // Declared here, not just defaulted in the extension below: callers reach it through the
    // `Player` existential, so an implementation on a conforming type is only ever dispatched
    // if the protocol itself lists it.
    func shareURL(for currentlyPlaying: String?) -> URL?
}

extension Player {
    var durationAsTimeInterval: TimeInterval? {
        if let duration {
            return TimeInterval(duration*1000)
        } else {
            return nil
        }
    }
    
    func artwork(for artworkURL: URL) async -> NSImage? {
        do {
            let artwork = try await URLSession.shared.data(for: URLRequest(url: artworkURL))
            return NSImage(data: artwork.0)
        } catch {
            print("\(#function) failed to download artwork \(error)")
            return nil
        }
    }
    
    /// Spotify's own default: its track IDs are 22 characters. Apple Music overrides this to
    /// return nil -- its keys are not Spotify IDs and must never be dressed up as one.
    func shareURL(for currentlyPlaying: String?) -> URL? {
        guard let currentlyPlaying, currentlyPlaying.count == 22 else {
            return nil
        }
        return URL(string: "http://open.spotify.com/track/\(currentlyPlaying)")
    }
}
