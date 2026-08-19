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

/// Keeps the version-specific Slider initialiser in the same availability boundary as the
/// Liquid Glass APIs. Its appearance and binding are intentionally unchanged.
struct MenubarTruncationSlider: View {
    @Binding var value: Double

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                Slider(
                    value: $value,
                    in: 100...320,
                    label: { Text("Menubar Size") },
                    ticks: {
                        SliderTick(100)
                        SliderTick(160)
                        SliderTick(220)
                        SliderTick(280)
                    }
                )
            } else {
                Slider(value: $value, in: 100...320) {
                    Text("Menubar Size")
                }
            }
        }
    }
}
