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
                // Romanization is outermost because it transforms whichever line the rest of
                // this chain settled on -- including a translation. Every array below is
                // index-aligned with currentlyPlayingLyrics.
                if !viewmodel.romanizedLyrics.isEmpty {
                    return viewmodel.romanizedLyrics[currentlyPlayingLyricsIndex]
                } else if viewmodel.translationExists {
                    // I don't localize, because I deliver the lyric verbatim
                    return viewmodel.translatedLyric[currentlyPlayingLyricsIndex]
                } else if !viewmodel.chineseConversionLyrics.isEmpty {
                    return viewmodel.chineseConversionLyrics[currentlyPlayingLyricsIndex]
                } else {
                    return viewmodel.currentlyPlayingLyrics[currentlyPlayingLyricsIndex].words
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

    /// What to say when there is no lyric line to show. Set in italics so it never reads as a
    /// lyric that happens to be short -- these are notes about the player, not words from the
    /// song.
    var menuBarStatus: String {
        if !viewmodel.showLyrics {
            return String(localized: "lyrics off")
        }
        if viewmodel.currentlyPlayingName == nil {
            return String(localized: "not playing")
        }
        if !viewmodel.isPlaying {
            return String(localized: "paused")
        }
        // Before "no lyrics": a song change resets `lyricsIsEmptyPostLoad` to true, so the
        // seconds spent downloading would otherwise announce that the song has none.
        if viewmodel.isFetching {
            return String(localized: "searching…")
        }
        if viewmodel.currentTrackIsInstrumental {
            return String(localized: "instrumental")
        }
        if viewmodel.lyricsIsEmptyPostLoad {
            return String(localized: "no lyrics")
        }
        // Playing, lyrics loaded, but this moment has no line of its own.
        return String(localized: "interlude")
    }

    var body: some View {
        // Even the placeholder is drawn on the same canvas. It appears whenever there is no
        // lyric to show -- paused, between lines, instrumental passages -- and letting it
        // shrink the item back to icon width would reintroduce exactly the resize this whole
        // approach exists to avoid.
        Image(nsImage: Self.render(menuBarTitle, status: menuBarStatus, width: viewmodel.menubarLyricWidth, scrolledBy: scrollOffset))
            .task(id: ScrollKey(line: menuBarTitle, width: viewmodel.menubarLyricWidth)) {
                await scrollThroughLine()
            }
    }

    /// Walks a too-long line leftwards in step with the singing rather than at a fixed rate, so
    /// the words under the reader's eye are roughly the words being sung.
    ///
    /// Position comes from how far into the line playback has got: the line's own timestamp and
    /// the next line's bound it, and `CurrentTimeWithStoredDate` interpolates between player
    /// updates from the wall clock, so this costs no Apple events however often it is sampled.
    ///
    /// Two things shape the pacing. The travel is squeezed into the middle of the line -- still
    /// at the head for the first quarter, already at the tail for the last -- because a line
    /// that starts moving instantly is unreadable and one still moving as it is replaced never
    /// gets its ending read. And it never crawls: a long line that only just overflows would
    /// otherwise inch along for seconds, so the travel is also capped at whatever
    /// `minimumScrollSpeed` needs, finishing early and resting at the tail instead.
    ///
    /// Nothing here resizes the item. The canvas is a constant width and only the text inside it
    /// moves, which is what makes scrolling safe at all: a status item that changes width gets
    /// repositioned by the system, visibly, in two steps.
    private func scrollThroughLine() async {
        scrollOffset = 0
        let overflow = Self.overflow(of: menuBarTitle, within: viewmodel.menubarLyricWidth)
        guard overflow > 0 else { return }
        while !Task.isCancelled {
            if viewmodel.isPlaying, let line = currentLineTiming() {
                let lead = 0.25, trail = 0.75
                let window = (trail - lead) * line.duration
                let travel = min(window, overflow / Self.minimumScrollSpeed * 1000)
                let elapsed = line.elapsed - lead * line.duration
                let travelled = travel > 0 ? min(max(elapsed / travel, 0), 1) : 1
                scrollOffset = overflow * travelled
            }
            try? await Task.sleep(for: .milliseconds(33))
        }
    }

    /// Points per second below which the scroll is not allowed to drop.
    static let minimumScrollSpeed: Double = 55

    /// Where playback sits inside the current lyric line, in milliseconds. Nil when there is no
    /// line to measure against.
    private func currentLineTiming() -> (elapsed: Double, duration: Double)? {
        let lines = viewmodel.currentlyPlayingLyrics
        guard let index = viewmodel.currentlyPlayingLyricsIndex,
              lines.indices.contains(index) else { return nil }
        let start = lines[index].startTimeMS
        // The closing line has no next timestamp; give it a plausible span rather than nothing.
        let end = lines.indices.contains(index + 1) ? lines[index + 1].startTimeMS : start + 5000
        guard end > start else { return nil }
        let now = viewmodel.currentTime.adjustedCurrentTime(for: Date())
        return (elapsed: now - start, duration: end - start)
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
    static func render(_ text: String?, status: String, width: CGFloat, scrolledBy offset: CGFloat = 0) -> NSImage {
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
        } else {
            // The state, in the font's own italic rather than a slanted upright, right-aligned
            // and faded so it sits behind the lyrics in the reading order instead of competing
            // with them. Template images carry their alpha through, so the fade survives
            // whatever colour AppKit paints the menu bar in.
            let base = NSFont.menuBarFont(ofSize: 0)
            let italic = NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(.italic),
                                size: base.pointSize) ?? base
            let attributes: [NSAttributedString.Key: Any] = [
                .font: italic,
                .foregroundColor: NSColor.black.withAlphaComponent(0.55)
            ]
            let line = status as NSString
            let drawn = line.size(withAttributes: attributes)
            line.draw(at: NSPoint(x: width - drawn.width, y: (height - drawn.height) / 2),
                      withAttributes: attributes)
        }
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
