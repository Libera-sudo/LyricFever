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
    /// Read and written only from the main thread, where every caller already is.
    nonisolated(unsafe) private static var lastKnownPadding: CGFloat = 16

    /// The screen whose menu bar is the tight one. Not `NSScreen.main`: that is wherever the
    /// keyboard focus is, which on a docked Mac is routinely an external display with no notch
    /// and no crowding. The notched bar is the one that runs out of room.
    private static var notchedScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.auxiliaryTopRightArea != nil })
    }

    /// This app's own status-item window, or nil before the item is placed.
    ///
    /// `MenuBarExtra` keeps its `NSStatusItem` to itself, so the item is found by its window
    /// instead. Identifying it lives here alone, because two callers need it: the measurement
    /// below, and whoever wants to watch it move.
    ///
    /// The filter is geometric, not just the class name. One status window exists per screen,
    /// so the frames have to be narrowed to the notched screen before any of them is compared
    /// -- picking the right-most across all screens instead reaches onto whichever display sits
    /// furthest right and measures it against this screen's notch: with an external at x=2952
    /// that produced 2283pt of "available" space, silently outranking every slider setting and
    /// switching the whole limit off. And the panel that drops out of a `MenuBarExtra` is an
    /// `NSStatusBarWindow` too, but hangs below the bar and is far taller, so height and top
    /// edge exclude it -- otherwise opening the panel changes what gets measured.
    static func statusItemWindow() -> NSWindow? {
        guard let screen = notchedScreen else { return nil }
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        return NSApp.windows.filter {
            let frame = $0.frame
            return String(describing: type(of: $0)) == "NSStatusBarWindow"
                && screen.frame.contains(CGPoint(x: frame.midX, y: frame.midY))
                && abs(frame.maxY - screen.frame.maxY) <= 2
                && frame.height <= max(menuBarHeight, 24) + 8
        }.max(by: { $0.frame.maxX < $1.frame.maxX })
    }

    /// Points between the notch and this app's own status item, i.e. everything the lyric could
    /// grow into. Nil when the item has not been placed yet, or on a screen without a notch,
    /// where no reliable reference edge exists.
    ///
    /// - Parameter currentDrawnWidth: width of the image currently in the item. The status item
    ///   frames its content with padding, so the frame is always wider than what we drew; this
    ///   lets the difference be measured instead of guessed. Getting that wrong pushes the item
    ///   under the notch and macOS collapses the whole menu bar behind a chevron.
    static func availableWidth(currentDrawnWidth: CGFloat) -> CGFloat? {
        guard let screen = notchedScreen,
              let notchRightEdge = screen.auxiliaryTopRightArea?.minX,
              let ourFrame = statusItemWindow()?.frame else { return nil }
        // The status item insets its content by a fixed amount, but its frame catches up a beat
        // after the drawn width changes -- so subtracting the two during a change reads as zero
        // and inflates the answer by an item's worth of padding. Mid-drag that made the ceiling
        // jump and fall every frame, which threw the slider's knob around and blinked the
        // readout orange. Only a difference in the plausible range is believed; otherwise the
        // last believable one stands.
        let observed = ourFrame.width - currentDrawnWidth
        if (0...40).contains(observed) { lastKnownPadding = observed }
        let padding = lastKnownPadding
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
