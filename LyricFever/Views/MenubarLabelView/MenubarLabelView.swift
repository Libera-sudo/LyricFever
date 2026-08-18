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

    /// How far the current line has travelled leftwards, in points.
    @State private var scrollOffset: CGFloat = 0

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
        // Even the placeholder is drawn on the same canvas. It appears whenever there is no
        // lyric to show -- paused, between lines, instrumental passages -- and letting it
        // shrink the item back to icon width would reintroduce exactly the resize this whole
        // approach exists to avoid.
        Image(nsImage: Self.render(menuBarTitle, width: viewmodel.menubarLyricWidth, scrolledBy: scrollOffset))
            .task(id: ScrollKey(line: menuBarTitle, width: viewmodel.menubarLyricWidth)) {
                await scrollThroughLine()
            }
    }

    /// A line only scrolls when it is too long, and only once: lines are replaced every few
    /// seconds anyway, so looping would restart a line the reader has already finished. It
    /// rests at the head first -- the opening words are the ones being sung right now -- then
    /// travels to the end and stays there.
    ///
    /// Nothing about this resizes the item. The canvas is a constant width and only the text
    /// inside it moves, which is what makes scrolling safe here at all: a status item that
    /// changes width gets repositioned by the system, visibly, in two steps.
    private func scrollThroughLine() async {
        scrollOffset = 0
        let overflow = Self.overflow(of: menuBarTitle, within: viewmodel.menubarLyricWidth)
        guard overflow > 0 else { return }
        try? await Task.sleep(for: .seconds(1.2))
        while scrollOffset < overflow {
            if Task.isCancelled { return }
            scrollOffset = min(scrollOffset + 1, overflow)
            try? await Task.sleep(for: .milliseconds(33))
        }
    }

    /// Identifies the thing being scrolled. The width belongs in here too: re-fitting the item
    /// to a resized menu bar changes how much of the line overflows.
    private struct ScrollKey: Equatable {
        let line: String?
        let width: CGFloat
    }

    /// How far past the canvas the line runs, in points. Zero when it fits.
    static func overflow(of text: String?, within width: CGFloat) -> CGFloat {
        guard let text else { return 0 }
        let drawn = (text as NSString).size(withAttributes: [.font: NSFont.menuBarFont(ofSize: 0)]).width
        return max(ceil(drawn) - width, 0)
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
    static func render(_ text: String?, width: CGFloat, scrolledBy offset: CGFloat = 0) -> NSImage {
        let height: CGFloat = 18
        let width = max(width, 1)
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        if let text {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.menuBarFont(ofSize: 0),
                .foregroundColor: NSColor.black
            ]
            let line = text as NSString
            let drawn = line.size(withAttributes: attributes)
            let y = (height - drawn.height) / 2
            // A line that fits sits against the right edge, where the eye already is. One that
            // does not starts at the left and is walked leftwards by `offset`; the canvas clips
            // whatever hangs off either side.
            let x = drawn.width <= width ? width - drawn.width : -offset
            NSGraphicsContext.current?.cgContext.clip(to: CGRect(x: 0, y: 0, width: width, height: height))
            line.draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
        } else if let glyph = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: nil) {
            // Right-aligned like the lyric, so the two never appear to shift when one replaces
            // the other.
            let size = glyph.size
            glyph.draw(in: NSRect(x: width - size.width, y: (height - size.height) / 2,
                                  width: size.width, height: size.height))
        }
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
