//
//  ButtonState.swift
//  Lyric Fever
//
//  Created by Avi Wadhwa on 2025-08-04.
//

import SwiftUI

@MainActor
enum ButtonState {
    case enabled
    case disabled
    case loading
    case clickable
    case missing

    /// Only an active lyric control carries the album colour into Liquid Glass.
    var glassTint: Color? {
        self == .enabled ? ViewModel.shared.currentBackground : nil
    }

    /// Disabled controls retain glass depth but do not react to pointer movement or clicks.
    var glassIsInteractive: Bool {
        self != .disabled
    }

    /// Liquid Glass tints with the extracted colour directly instead of adding the fallback's
    /// 0.3 brightness. Compare against that unbrightened tint; if it is absent, white is the
    /// safe choice for untinted regular glass over this forced-dark panel.
    var glassForegroundStyle: Color {
        switch self {
            case .enabled:
                guard let background = ViewModel.shared.currentBackground else { return .white }
                return background.legibleForeground(afterBrightening: 0)
            case .disabled, .clickable, .loading, .missing:
                return .white
        }
    }
    
    var fillStyle: AnyShapeStyle {
        switch self {
            case .enabled:
                if let bg = ViewModel.shared.currentBackground {
                    // Use the color with desired opacity
                    return AnyShapeStyle(bg.opacity(0.8))
                } else {
                    // Fall back to a material; set opacity on the shape usage, not here
                    return AnyShapeStyle(.primary)
                }
            case .disabled:
                return AnyShapeStyle(.thickMaterial)
            case .clickable, .loading, .missing:
                return AnyShapeStyle(.thickMaterial)
        }
    }

    /// The icon colour that stays readable on top of the legacy fallback background.
    ///
    /// Callers force `colorScheme` to `.dark`, which makes the icon white by default. That is
    /// right for the inactive states, whose `.thickMaterial` stays dark over this panel, but
    /// wrong for `.enabled`: album colours are deliberately lightened when extracted, and the
    /// fallback background is brightened by another 0.3 before being drawn, so a white icon
    /// lands on a near-white field. With no album colour at all the fallback is `.primary`,
    /// which under the forced dark scheme is pure white and hides the icon completely.
    var foregroundStyle: Color {
        switch self {
            case .enabled:
                guard let background = ViewModel.shared.currentBackground else { return .black }
                return background.legibleForeground(afterBrightening: 0.3)
            case .disabled, .clickable, .loading, .missing:
                return .white
        }
    }
}

extension Color {
    /// Black or white -- whichever keeps contrast after applying the background's brightness.
    ///
    /// Judged on WCAG relative luminance rather than HSB brightness: a saturated yellow and a
    /// saturated blue can report the same brightness while differing enormously in how light
    /// they actually appear, and it is the latter that decides whether an icon reads.
    func legibleForeground(afterBrightening amount: CGFloat) -> Color {
        #if canImport(AppKit)
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return .white }
        func linearised(_ component: CGFloat) -> CGFloat {
            let brightened = min(max(component + amount, 0), 1)
            return brightened <= 0.03928 ? brightened / 12.92
                                         : pow((brightened + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linearised(srgb.redComponent)
                      + 0.7152 * linearised(srgb.greenComponent)
                      + 0.0722 * linearised(srgb.blueComponent)
        // 0.179 is where black and white swap places in the WCAG contrast-ratio formula.
        return luminance > 0.179 ? .black : .white
        #else
        return .white
        #endif
    }
}
