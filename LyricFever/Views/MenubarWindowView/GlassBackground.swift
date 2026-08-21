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

/// Draws the warning into the bar itself, which is the whole reason this is AppKit: an overlay
/// on SwiftUI's `Slider` would cover the knob rather than pass beneath it, and nothing in that
/// API intercepts the drag.
private final class MenubarTruncationSliderCell: NSSliderCell {
    /// Values above this have no room in the menu bar. Nil when nothing could be measured --
    /// which is not the same as unavailable, and draws no warning at all.
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

        // The fill stops at the ceiling rather than at the value. Past that point the track is
        // not really available, so showing it as filled would paint over the warning at exactly
        // the moment it matters most -- the knob alone carries where the value actually sits.
        let fillLimit = effectiveCeiling.map { min(doubleValue, $0) } ?? doubleValue
        let filled = CGFloat(min(max((fillLimit - minValue) / range, 0), 1))
        NSColor.secondaryLabelColor.withAlphaComponent(0.62).setFill()
        NSRect(x: bar.minX, y: bar.minY, width: bar.width * filled, height: bar.height).fill()

        if let boundary = effectiveCeiling {
            let start = bar.minX + bar.width * CGFloat((boundary - minValue) / range)
            let hatch = NSRect(x: start, y: bar.minY, width: bar.maxX - start, height: bar.height)
            NSBezierPath(rect: hatch).addClip()
            // Orange, the same colour the readout beside the slider turns when the bar rather
            // than the slider is what limits the lyric: one meaning, one colour.
            NSColor.systemOrange.withAlphaComponent(0.22).setFill()
            NSRect(x: hatch.minX, y: hatch.minY, width: hatch.width, height: hatch.height).fill()
            NSColor.systemOrange.withAlphaComponent(0.85).setStroke()
            let stripes = NSBezierPath()
            stripes.lineWidth = 1.2
            // Spaced wider than the bar is tall, so each stroke reads as its own diagonal rather
            // than merging with its neighbours into a braid at this size.
            var x = hatch.minX - hatch.height
            while x < hatch.maxX {
                stripes.move(to: NSPoint(x: x, y: hatch.minY))
                stripes.line(to: NSPoint(x: x + hatch.height, y: hatch.maxY))
                x += 7
            }
            stripes.stroke()
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

    override func continueTracking(last: NSPoint, current: NSPoint, in controlView: NSView) -> Bool {
        let keepTracking = super.continueTracking(last: last, current: current, in: controlView)
        guard let boundary = effectiveCeiling, doubleValue > boundary else {
            controlView.needsDisplay = true
            return keepTracking
        }

        // A slider tracks the pointer absolutely, so super has already turned this event's
        // position into a value. Remapping just the stretch above the boundary therefore needs
        // no memory of where the drag began, and cannot drift over a long drag.
        //
        // The curve starts at a third of the normal rate and steepens back to full by the end
        // of the track. A flat third would feel the same but could never reach 320 on a finite
        // bar -- and reaching it has to stay possible, because this is a cap and the free space
        // changes: a wall would quietly rewrite the setting to whatever fitted at the time.
        let span = maxValue - boundary
        let progress = min(max((doubleValue - boundary) / span, 0), 1)
        let resistance = 1.0 / 3.0
        let resisted = resistance * progress + (1 - resistance) * progress * progress
        doubleValue = boundary + span * resisted
        controlView.needsDisplay = true
        return keepTracking
    }
}

/// The width slider. Continuous, marked at four reference widths, and hatched over whatever the
/// menu bar has no room for -- with a drag that stiffens once it crosses into that stretch.
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
        if slider.doubleValue != value { slider.doubleValue = value }
        guard let cell = slider.cell as? MenubarTruncationSliderCell else { return }
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
