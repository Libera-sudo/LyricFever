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

/// AppKit because SwiftUI's `Slider` gives nothing that can intercept a drag, and holding the
/// knob at the width the menu bar can actually give -- on a rubber band, not a wall -- is the
/// whole point of this cell.
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

        // Only while the band is stretched: the knob has passed what the bar can give and is
        // still being pulled. The hatching starts at the knob rather than at the ceiling, so it
        // marks the road ahead -- there is nothing there to reach -- instead of restating a
        // boundary the knob has already crossed. It disappears as the knob springs back.
        if let boundary = effectiveCeiling, doubleValue > boundary {
            let knob = knobRect(flipped: flipped)
            let start = max(knob.maxX, bar.minX)
            if start < bar.maxX {
                let hatch = NSRect(x: start, y: bar.minY, width: bar.maxX - start, height: bar.height)
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: hatch).addClip()
                NSColor.systemYellow.withAlphaComponent(0.20).setFill()
                hatch.fill()
                NSColor.systemYellow.withAlphaComponent(0.85).setStroke()
                let stripes = NSBezierPath()
                stripes.lineWidth = 1.2
                // Spaced wider than the bar is tall, so each stroke reads as its own diagonal
                // rather than merging with its neighbours into a braid at this size.
                var x = hatch.minX - hatch.height
                while x < hatch.maxX {
                    stripes.move(to: NSPoint(x: x, y: hatch.minY))
                    stripes.line(to: NSPoint(x: x + hatch.height, y: hatch.maxY))
                    x += 7
                }
                stripes.stroke()
                NSGraphicsContext.restoreGraphicsState()
            }
        }

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
        springBack?.cancel()
        springBack = nil
        let started = super.startTracking(at: startPoint, in: controlView)
        gestureCeiling = .some(effectiveCeiling)
        clampToCeiling()
        return started
    }

    override func stopTracking(last: NSPoint, current: NSPoint, in controlView: NSView, mouseIsUp: Bool) {
        super.stopTracking(last: last, current: current, in: controlView, mouseIsUp: mouseIsUp)
        clampToCeiling()
        let limit = gestureCeiling ?? effectiveCeiling
        gestureCeiling = nil
        if let limit { startSpringBack(to: limit, in: controlView) }
    }

    /// True while the pointer owns the knob, and while it is springing back afterwards, so the
    /// representable can keep out of the way for the whole of it.
    var isTracking: Bool { gestureCeiling != nil || springBack != nil }

    private var springBack: Task<Void, Never>?

    /// How far past the limit the knob can be pulled, in slider units, however hard you pull.
    private let maxStretch = 20.0

    /// The rubber band: displacement that grows ever more slowly and never passes `maxStretch`.
    /// The shape is the one Apple's scroll views use -- resistance rising with distance rather
    /// than a fixed fraction, so the first point past the limit gives easily and the twentieth
    /// hardly at all.
    private func stretched(_ overshoot: Double) -> Double {
        maxStretch * (1 - 1 / (overshoot * 0.55 / maxStretch + 1))
    }

    private func clampToCeiling() {
        guard let boundary = gestureCeiling ?? effectiveCeiling, doubleValue > boundary else { return }
        doubleValue = boundary + stretched(doubleValue - boundary)
    }

    /// Eases the knob back to the limit it was pulled past. Cheap and finite -- a dozen frames,
    /// then the exact value -- rather than anything that stays resident.
    private func startSpringBack(to limit: Double, in controlView: NSView) {
        springBack?.cancel()
        let from = doubleValue
        guard from > limit else { return }
        let control = controlView as? NSControl
        springBack = Task { @MainActor [weak self] in
            let frames = 12
            for frame in 1...frames {
                try? await Task.sleep(for: .milliseconds(16))
                guard let self, !Task.isCancelled else { return }
                let progress = Double(frame) / Double(frames)
                let eased = 1 - pow(1 - progress, 3)
                self.doubleValue = from + (limit - from) * eased
                control?.sendAction(control?.action, to: control?.target)
                controlView.needsDisplay = true
            }
            guard let self, !Task.isCancelled else { return }
            self.doubleValue = limit
            control?.sendAction(control?.action, to: control?.target)
            controlView.needsDisplay = true
            self.springBack = nil
        }
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

/// The width slider. Continuous, marked at four reference widths, and rubber-banded at the width
/// the menu bar has room for: it gives a little under a hard pull, hatches the track ahead of the
/// knob while it is stretched, and springs back on release.
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
