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
    /// What one look at the bar found. The failures are deliberately not interchangeable:
    /// launch placement, overflow, corrupt geometry and a missing reference edge each need a
    /// different response from the caller, and folding them all into one nil is what once made
    /// every failure look like "the limit randomly switched off".
    enum Reading {
        /// Free points between the notch and the item, from a frame that is fully on-screen
        /// and arithmetic that is physically possible.
        case space(CGFloat)
        /// The item's window is at bar height but parked past a screen edge, or squeezed left
        /// of the notch: macOS has collapsed it behind the chevron, or is about to. Shrink.
        case overflowing
        /// No window of ours is in the bar yet. At launch the windows exist but wait below the
        /// screen; that state must not read as overflow.
        case unplaced
        /// No screen has a notch -- lid closed, or external displays only. There is no reliable
        /// reference edge, so there is nothing to measure against.
        case noReference
        /// A window passed every structural test but the numbers came out impossible. Trust
        /// nothing about it, and change nothing because of it.
        case invalid
    }

    /// Read and written only from the main thread, where every caller already is.
    nonisolated(unsafe) private static var lastKnownPadding: CGFloat = 16

    /// The screen whose menu bar is the tight one. Not `NSScreen.main`: that is wherever the
    /// keyboard focus is, which on a docked Mac is routinely an external display with no notch
    /// and no crowding. The notched bar is the one that runs out of room.
    private static var notchedScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.auxiliaryTopRightArea != nil })
    }

    /// Every window of ours that is structurally a status-bar window on this screen -- placed
    /// OR parked past an edge. Both lookups below start here, so a parked window stays visible
    /// to measurement (it means overflow) without ever counting as validly placed.
    ///
    /// Three tests, each carrying scar tissue:
    /// - Intersection with the screen, not midpoint containment: when macOS 27 collapses the
    ///   item behind the chevron it parks the window PARTIALLY PAST the right edge (maxX
    ///   1522-1538 on this 1512pt screen, measured 2026-08-25) -- the midpoint is still
    ///   on-screen, and a midpoint test waved that frame into measurement as 674pt of free
    ///   space, which got persisted and poisoned every launch after it. Intersection still ties
    ///   each window to its own display: one exists per screen, and picking right-most across
    ///   all of them once reached an external at x=2952 and measured it against this notch.
    /// - The top edge pinned to the bar: the panel that drops out of a `MenuBarExtra` is an
    ///   `NSStatusBarWindow` too, but hangs below the bar; and at launch the item's windows
    ///   exist while still parked below the screen (maxY 0 against the bar's 982), which must
    ///   read as "not placed yet", not as a frame worth measuring.
    /// - The height, for the same panel.
    private static func barWindows(on screen: NSScreen) -> [NSWindow] {
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        return NSApp.windows.filter {
            let frame = $0.frame
            return String(describing: type(of: $0)) == "NSStatusBarWindow"
                && frame.intersects(screen.frame)
                && abs(frame.maxY - screen.frame.maxY) <= 2
                && frame.height <= max(menuBarHeight, 24) + 8
        }
    }

    private static func fullyOnScreen(_ frame: NSRect, _ screen: NSScreen) -> Bool {
        frame.minX >= screen.frame.minX - 0.5 && frame.maxX <= screen.frame.maxX + 0.5
    }

    /// This app's own status-item window, properly placed in the bar. Nil before the item is
    /// placed -- and nil again while it is parked off an edge, which is what "properly" buys:
    /// callers holding one of these may trust its frame.
    static func statusItemWindow() -> NSWindow? {
        guard let screen = notchedScreen else { return nil }
        return barWindows(on: screen)
            .filter { fullyOnScreen($0.frame, screen) }
            .max(by: { $0.frame.maxX < $1.frame.maxX })
    }

    /// Loose membership test for the move observer. It cannot use `statusItemWindow()`: the
    /// one move worth reacting to fastest -- the one that parks the item off the edge -- is
    /// posted by exactly the window the strict lookup no longer returns.
    static func involvesStatusItem(_ window: NSWindow) -> Bool {
        guard let screen = notchedScreen else { return false }
        return barWindows(on: screen).contains { $0 === window }
    }

    /// One look at the bar: how much room there is, or which way there isn't.
    ///
    /// - Parameter currentDrawnWidth: width of the image currently in the item. The status item
    ///   frames its content with padding, so the frame is always wider than what we drew; this
    ///   lets the difference be measured instead of guessed. Getting that wrong pushes the item
    ///   under the notch and macOS collapses the whole menu bar behind a chevron.
    static func reading(currentDrawnWidth: CGFloat) -> Reading {
        guard let screen = notchedScreen, let rightArea = screen.auxiliaryTopRightArea else {
            print("MenubarSpace: no screen with a notch -- lid closed, or external displays only")
            return .noReference
        }
        let candidates = barWindows(on: screen)
        guard !candidates.isEmpty else {
            print("MenubarSpace: no status window in the bar yet")
            return .unplaced
        }
        guard let ourFrame = candidates
            .filter({ fullyOnScreen($0.frame, screen) })
            .max(by: { $0.frame.maxX < $1.frame.maxX })?.frame
        else {
            print("MenubarSpace: status window parked past the screen edge -- collapsed behind the chevron; frames \(candidates.map(\.frame))")
            return .overflowing
        }
        // The status item insets its content by a fixed amount, but its frame catches up a beat
        // after the drawn width changes -- so subtracting the two during a change reads as zero
        // and inflates the answer by an item's worth of padding. Mid-drag that made the ceiling
        // jump and fall every frame, which threw the slider's knob around and blinked the
        // readout orange. Only a difference in the plausible range is believed; otherwise the
        // last believable one stands.
        let observed = ourFrame.width - currentDrawnWidth
        if (0...40).contains(observed) { lastKnownPadding = observed }
        let available = ourFrame.maxX - rightArea.minX - lastKnownPadding
        guard available > 0 else {
            print("MenubarSpace: item sits left of the notch (available \(Int(available))pt) -- overflowing")
            return .overflowing
        }
        guard available <= rightArea.width else {
            // More free space than there is bar beside the notch is not a measurement, it is
            // corrupt geometry -- the 674pt reading that started all of this came through here.
            print("MenubarSpace: impossible reading \(Int(available))pt against \(Int(rightArea.width))pt beside the notch -- frame \(ourFrame) ignored")
            return .invalid
        }
        return .space(floor(available))
    }
}
