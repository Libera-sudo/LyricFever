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
        guard let screen = NSScreen.main,
              let notchRightEdge = screen.auxiliaryTopRightArea?.minX else { return nil }
        let statusWindows = NSApp.windows.filter {
            String(describing: type(of: $0)) == "NSStatusBarWindow" && $0.frame.maxY > screen.frame.midY
        }
        guard let ourFrame = statusWindows.map(\.frame).max(by: { $0.maxX < $1.maxX }) else { return nil }
        let padding = max(ourFrame.width - currentDrawnWidth, 0)
        let available = ourFrame.maxX - notchRightEdge - padding
        return available > 0 ? floor(available) : nil
    }
}
