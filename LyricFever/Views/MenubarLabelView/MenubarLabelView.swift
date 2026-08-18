//
//  MenubarLabelView.swift
//  Lyric Fever
//
//  Created by Avi Wadhwa on 2025-08-05.
//

import SwiftUI
import AppKit

/// Remembers the last measurement so `body` can read a width synchronously without redoing
/// the work on every redraw. A reference type on purpose: mutating it is not a SwiftUI state
/// change, which is what lets the lookup happen inline while the view is being built.
@MainActor
final class MenubarWidthCache {
    private var key: String?
    private var width: CGFloat?

    func width(forKey key: String, measuring lines: @autoclosure () -> [String], cappedAt truncationLength: Int) -> CGFloat? {
        if key != self.key {
            self.key = key
            self.width = MenubarLabelView.widestLine(among: lines(), cappedAt: truncationLength)
        }
        return width
    }
}

struct MenubarLabelView: View {
    @Environment(ViewModel.self) var viewmodel

    @State private var widthCache = MenubarWidthCache()

    var menuBarTitle: String? {
        // Update message takes priority
        if viewmodel.mustUpdateUrgent {
            return String(localized: "⚠️ Please Update (Click Check Updates)")
        } else if viewmodel.userDefaultStorage.hasOnboarded {
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

    /// Every line the menubar could show for this song, in whichever form it will show them.
    /// Mirrors the branching in `menuBarTitle`, which picks one array for the whole song.
    var displayedLines: [String] {
        if viewmodel.translationExists {
            return viewmodel.translatedLyric
        } else if !viewmodel.romanizedLyrics.isEmpty {
            return viewmodel.romanizedLyrics
        } else if !viewmodel.chineseConversionLyrics.isEmpty {
            return viewmodel.chineseConversionLyrics
        } else {
            return viewmodel.currentlyPlayingLyrics.map(\.words)
        }
    }

    /// Changes exactly when the set of lines the menubar would draw changes, so the width is
    /// remeasured once per song (or once per settings flip) rather than on every redraw.
    var measurementKey: String {
        [
            viewmodel.currentlyPlaying ?? "-",
            String(viewmodel.userDefaultStorage.truncationLength),
            String(viewmodel.translatedLyric.count),
            String(viewmodel.romanizedLyrics.count),
            String(viewmodel.chineseConversionLyrics.count),
            String(viewmodel.currentlyPlayingLyrics.count)
        ].joined(separator: "|")
    }

    var body: some View {
        Group {
            if let menuBarTitle {
                Text(menuBarTitle.trunc())
            } else {
                Image(systemName: "music.note.list")
            }
        }
        // Holding a width is what stops the lyric shuffling sideways: a status item hugs its
        // content, so without this the item -- and everything to its left -- is relaid out on
        // every line. The width is the widest line *this song* will actually draw rather than
        // the theoretical maximum for `truncationLength`: reserving forty CJK characters would
        // claim over 500pt of menu bar and leave most of it empty on an English song. Trailing
        // alignment pins the right edge, so lines grow leftwards into the reserved space.
        //
        // Measured inline rather than from a `.task`: that ran a cycle late, so each new line
        // was drawn once at its own width before the reserved width arrived and shoved it
        // right -- read as the text sliding into place. The cache keeps the repeat cost to a
        // dictionary-free string compare.
        .frame(
            width: widthCache.width(
                forKey: measurementKey,
                measuring: displayedLines,
                cappedAt: viewmodel.userDefaultStorage.truncationLength
            ),
            alignment: .trailing
        )
        // A width change is a relayout, never something to animate across.
        .transaction { $0.animation = nil }
    }

    /// Measures in the menu bar's own font, on the already-truncated strings, so the answer is
    /// the width actually drawn. Returns nil for a song with no lyrics, which lets the frame
    /// collapse back to the placeholder icon instead of holding a wide empty gap.
    static func widestLine(among lines: [String], cappedAt truncationLength: Int) -> CGFloat? {
        guard !lines.isEmpty else { return nil }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.menuBarFont(ofSize: 0)]
        let widest = lines.reduce(into: CGFloat.zero) { widest, line in
            let drawn = line.count > truncationLength ? String(line.prefix(truncationLength)) + "…" : line
            widest = max(widest, (drawn as NSString).size(withAttributes: attributes).width)
        }
        return widest > 0 ? ceil(widest) : nil
    }
}
