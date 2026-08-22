//
//  GlassBackground.swift
//  Lyric Fever
//

import SwiftUI

extension View {
    /// Uses Liquid Glass when it is available and preserves the supplied background verbatim
    /// on older systems.
    @ViewBuilder
    func menubarGlass(
        tint: Color?,
        interactive: Bool,
        cornerRadius: CGFloat,
        fallback: some View
    ) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(
                .regular.tint(tint).interactive(interactive),
                in: .rect(cornerRadius: cornerRadius)
            )
        } else {
            background(fallback)
        }
    }

    /// Applies the system glass button style without exposing availability checks to callers.
    @ViewBuilder
    func menubarGlassButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            self
        }
    }

    /// Selects the foreground calculated for the background each OS actually renders.
    @ViewBuilder
    func menubarGlassForegroundStyle(glass: Color, fallback: Color) -> some View {
        if #available(macOS 26.0, *) {
            foregroundStyle(glass)
        } else {
            foregroundStyle(fallback)
        }
    }
}

/// AppKit because SwiftUI's `Slider` gives nothing that can intercept a drag, and stopping the
/// knob at the width the menu bar can actually give is the whole point of this cell.
private final class MenubarTruncationSliderCell: NSSliderCell {
    /// Values above this have no room in the menu bar, so the drag stops there. Nil when nothing
    /// could be measured -- which is not the same as unavailable, and stops nothing.
    var ceiling: Double?

    private let tickValues: [Double] = [100, 160, 220, 280]

    private var effectiveCeiling: Double? {
        guard let ceiling else { return nil }
        let clamped = min(max(ceiling, minValue), maxValue)
        return clamped < maxValue ? clamped : nil
    }

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let height = min(4, rect.height)
        let bar = NSRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
        let track = NSBezierPath(roundedRect: bar, xRadius: height / 2, yRadius: height / 2)
        NSColor.labelColor.withAlphaComponent(0.14).setFill()
        track.fill()

        let range = maxValue - minValue
        guard range > 0 else { return }

        NSGraphicsContext.saveGraphicsState()
        track.addClip()

        let filled = CGFloat(min(max((doubleValue - minValue) / range, 0), 1))
        NSColor.secondaryLabelColor.withAlphaComponent(0.62).setFill()
        NSRect(x: bar.minX, y: bar.minY, width: bar.width * filled, height: bar.height).fill()

        NSGraphicsContext.restoreGraphicsState()

        // Drawn here rather than through numberOfTickMarks, which spaces its marks evenly: these
        // four sit 60 apart inside a 220-wide range, which even spacing cannot reproduce. Drawing
        // them also leaves the value unsnapped, so the drag still lands on any whole point.
        NSColor.secondaryLabelColor.withAlphaComponent(0.55).setStroke()
        let ticks = NSBezierPath()
        ticks.lineWidth = 1
        for tick in tickValues {
            let x = bar.minX + bar.width * CGFloat((tick - minValue) / range)
            ticks.move(to: NSPoint(x: x, y: bar.minY - 2))
            ticks.line(to: NSPoint(x: x, y: bar.maxY + 2))
        }
        ticks.stroke()
    }

    /// The limit in force for the current gesture, taken once when it begins.
    ///
    /// It has to be frozen, because the live one moves while the drag is happening and moving it
    /// throws the knob around. The measurement derives the status item's padding from
    /// `frame.width - currentDrawnWidth`; dragging changes the drawn width immediately while the
    /// window's frame catches up a beat later, so mid-drag the subtraction goes negative, the
    /// padding reads as zero, and the ceiling jumps by about the padding's width -- then falls
    /// back once the frame lands. Clamping to a target that oscillates is what sent the knob
    /// flying near the end of the track.
    private var gestureCeiling: Double??

    /// Clicking the track jumps the knob without ever dragging, and the mouse-up settles the
    /// final value, so both ends of the gesture need the same limit as the drag itself.
    override func startTracking(at startPoint: NSPoint, in controlView: NSView) -> Bool {
        let started = super.startTracking(at: startPoint, in: controlView)
        gestureCeiling = .some(effectiveCeiling)
        clampToCeiling()
        return started
    }

    override func stopTracking(last: NSPoint, current: NSPoint, in controlView: NSView, mouseIsUp: Bool) {
        super.stopTracking(last: last, current: current, in: controlView, mouseIsUp: mouseIsUp)
        clampToCeiling()
        gestureCeiling = nil
    }

    /// True between mouse-down and mouse-up, so the representable can keep out of the way.
    var isTracking: Bool { gestureCeiling != nil }

    private func clampToCeiling() {
        guard let boundary = gestureCeiling ?? effectiveCeiling, doubleValue > boundary else { return }
        doubleValue = boundary
    }

    override func continueTracking(last: NSPoint, current: NSPoint, in controlView: NSView) -> Bool {
        let keepTracking = super.continueTracking(last: last, current: current, in: controlView)
        // The knob stops at what the menu bar can actually give. A slider tracks the pointer
        // absolutely, so super has already turned this event's position into a value and the
        // clamp needs no memory of where the drag began.
        //
        // Only the drag is stopped. A stored value already above the ceiling is left alone: the
        // free space rises and falls as other apps come and go, and rewriting the setting every
        // time it dipped would ratchet it down to whatever happened to fit at that moment.
        clampToCeiling()
        controlView.needsDisplay = true
        return keepTracking
    }
}

/// The width slider. Continuous, marked at four reference widths, and unable to be dragged past
/// the width the menu bar has room for.
///
/// It claims the row's slack rather than a fixed width: the `...` menu has no set width on
/// macOS 26+, so a fixed slider plus spacers could push Quit off the row, and the longest
/// possible track is what makes single-point precision draggable at all.
struct MenubarTruncationSlider: NSViewRepresentable {
    @Binding var value: Double
    var ceiling: CGFloat?

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(frame: .zero)
        slider.cell = MenubarTruncationSliderCell()
        slider.minValue = 100
        slider.maxValue = 320
        slider.doubleValue = value
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.valueChanged(_:))
        slider.setAccessibilityLabel("Menubar Size")
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.value = $value
        guard let cell = slider.cell as? MenubarTruncationSliderCell else { return }
        // Not while the pointer owns it. The binding stores whole points, so writing the rounded
        // value back mid-drag drags the knob half a point away from the pointer and the next
        // mouse event pulls it back -- a fight nobody wins, and one the clamp joins in on.
        if !cell.isTracking, slider.doubleValue != value {
            slider.doubleValue = value
        }
        let newCeiling = ceiling.map(Double.init)
        if cell.ceiling != newCeiling {
            cell.ceiling = newCeiling
            slider.needsDisplay = true
        }
    }

    final class Coordinator: NSObject {
        var value: Binding<Double>
        init(value: Binding<Double>) { self.value = value }

        @objc func valueChanged(_ sender: NSSlider) {
            value.wrappedValue = sender.doubleValue
        }
    }
}
