//
//  MenubarLabelView.swift
//  Lyric Fever
//
//  Created by Avi Wadhwa on 2025-08-05.
//

import SwiftUI
import AppKit

struct MenubarLabelView: View {
    @Environment(ViewModel.self) var viewmodel

    var menuBarTitle: String? {
        if viewmodel.userDefaultStorage.hasOnboarded {
            // Try to work through lyric logic if onboarded
            if viewmodel.isPlaying, viewmodel.showLyrics, let currentlyPlayingLyricsIndex = viewmodel.currentlyPlayingLyricsIndex {
                // Attempt to display translations
                // Implicit assumption: translatedLyric.count == currentlyPlayingLyrics.count
                if viewmodel.translationExists {
                    // I don't localize, because I deliver the lyric verbatim
                    return viewmodel.translatedLyric[currentlyPlayingLyricsIndex]
                } else {
                    // Attempt to display Romanization
                    if !viewmodel.romanizedLyrics.isEmpty {
                        return viewmodel.romanizedLyrics[currentlyPlayingLyricsIndex]
                    } else if !viewmodel.chineseConversionLyrics.isEmpty {
                        return viewmodel.chineseConversionLyrics[currentlyPlayingLyricsIndex]
                    } else {
                        return viewmodel.currentlyPlayingLyrics[currentlyPlayingLyricsIndex].words
                    }
                }
            // Backup: Display name and artist
            } else if viewmodel.userDefaultStorage.showSongDetailsInMenubar, let currentlyPlayingName = viewmodel.currentlyPlayingName, let currentlyPlayingArtist = viewmodel.currentlyPlayingArtist {
                if viewmodel.isPlaying {
                    return String(localized: "Now Playing: \(currentlyPlayingName) - \(currentlyPlayingArtist)")
                } else {
                    return String(localized: "Now Paused: \(currentlyPlayingName) - \(currentlyPlayingArtist)")
                }
            }
            // Onboarded but app is not open
            return nil
        } else {
            // Hasn't onboarded
            return String(localized: "⚠️ Complete Setup (Click Settings)")
        }
    }

    var body: some View {
        Group {
            if let menuBarTitle {
                Image(nsImage: Self.render(menuBarTitle, width: CGFloat(viewmodel.userDefaultStorage.menubarWidth)))
            } else {
                Image(systemName: "music.note.list")
            }
        }
    }

    /// Draws the lyric into a picture of a constant width instead of handing the menu bar a
    /// string that resizes.
    ///
    /// A status item whose width changes is repositioned by the system, and that happens in two
    /// visible steps: the item keeps its left edge and grows rightwards -- briefly overlapping
    /// whatever sits to its right -- and only afterwards does the menu bar repack and everything
    /// slide across. A bare AppKit probe that set `NSStatusItem.length` explicitly, inside a
    /// zero-duration animation group with implicit animation off, behaved exactly the same, so
    /// this is the status bar's own layout pass and not something an app can schedule around.
    /// A constant width sidesteps it completely: nothing is ever resized, so nothing is ever
    /// repositioned, and the right edge simply stays.
    ///
    /// Keeping it narrow matters beyond tidiness. macOS hides status items that overflow past
    /// the notch, so every extra point the lyric claims is paid for by some other icon
    /// disappearing. Lines wider than this are truncated rather than allowed to push.
    ///
    /// `isTemplate` hands colouring back to AppKit, so the lyric follows the menu bar the way
    /// the placeholder icon does, in light and dark alike.
    static func render(_ text: String, width: CGFloat) -> NSImage {
        let height: CGFloat = 18
        let width = max(width, 1)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuBarFont(ofSize: 0),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
        let line = text as NSString
        let lineHeight = line.size(withAttributes: attributes).height
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        line.draw(
            in: NSRect(x: 0, y: (height - lineHeight) / 2, width: width, height: lineHeight),
            withAttributes: attributes
        )
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
