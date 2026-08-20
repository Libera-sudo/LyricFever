//
//  MenubarSpace.swift
//  Lyric Fever
//

import AppKit

/// Works out how much menu bar the lyric may occupy.
///
/// The width has to be a constant while a song plays -- a status item that resizes is
/// repositioned by the system, visibly, in two steps -- but the right constant depends on the
/// machine: how wide the screen is, whether there is a notch, and how many other status items
/// are already parked to the right. So it is measured once and remeasured only when the screen
/// arrangement changes.
enum MenubarSpace {
    /// Points between the notch and this app's own status item, i.e. everything the lyric could
    /// grow into. Nil when the item has not been placed yet, or on a screen without a notch,
    /// where no reliable reference edge exists.
    ///
    /// `MenuBarExtra` keeps its `NSStatusItem` to itself, so the item is found by its window
    /// instead: the app owns exactly one on-screen `NSStatusBarWindow`. This only reads a frame
    /// -- nothing here reaches into SwiftUI's ownership of the item.
    /// - Parameter currentDrawnWidth: width of the image currently in the item. The status item
    ///   frames its content with padding, so the frame is always wider than what we drew; this
    ///   lets the difference be measured instead of guessed. Getting that wrong pushes the item
    ///   under the notch and macOS collapses the whole menu bar behind a chevron.
    static func availableWidth(currentDrawnWidth: CGFloat) -> CGFloat? {
        // The notched screen, not NSScreen.main: main is wherever the keyboard focus is, which
        // on a docked Mac is routinely an external display with no notch and no crowding. The
        // notched menu bar is the one that runs out of room, so it is the one worth measuring.
        guard let screen = NSScreen.screens.first(where: { $0.auxiliaryTopRightArea != nil }),
              let notchRightEdge = screen.auxiliaryTopRightArea?.minX else { return nil }
        // One status window per screen, so the frames have to be filtered to that screen before
        // any of them is compared. Picking the right-most across all screens instead reaches
        // onto whichever display sits furthest right and measures it against this screen's
        // notch: with an external at x=2952 that produced 2283pt of "available" space, which
        // silently outranks every slider setting and switches the whole limit off.
        let statusWindows = NSApp.windows.filter {
            String(describing: type(of: $0)) == "NSStatusBarWindow"
                && screen.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY))
                && $0.frame.maxY > screen.frame.midY
        }
        guard let ourFrame = statusWindows.map(\.frame).max(by: { $0.maxX < $1.maxX }) else { return nil }
        let padding = max(ourFrame.width - currentDrawnWidth, 0)
        let available = ourFrame.maxX - notchRightEdge - padding
        guard available > 0 else {
            // Nothing left of the notch to measure from means the item has already been pushed
            // past it, i.e. it is too wide right now. Returning nil here would hand the caller
            // its fallback -- the raw slider cap, the very width that overflowed -- and the
            // state would never unwind. Shrinking instead does: the caller takes another 48pt
            // of headroom off this, so one remeasurement pulls the item in by 80pt.
            return max(currentDrawnWidth - 32, 0)
        }
        return floor(available)
    }
}
