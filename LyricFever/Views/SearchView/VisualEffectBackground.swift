//
//  VisualEffectBackground.swift
//  Lyric Fever
//

import SwiftUI

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        // The view has no window yet at this point, so the window cannot be opened up until
        // after this returns.
        DispatchQueue.main.async { [weak visualEffectView] in
            visualEffectView?.letBackgroundThrough()
        }
        return visualEffectView
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
        nsView.letBackgroundThrough()
    }
}

private extension NSVisualEffectView {
    /// `behindWindow` blending samples what sits behind the window, and an opaque window never
    /// lets any of it through -- the material then renders as flat grey, which is exactly what
    /// it looked like. The panel gets this for free because a `MenuBarExtra` window is already
    /// transparent; an ordinary `Window` is not, so it has to be opened up by hand.
    func letBackgroundThrough() {
        guard let window, window.isOpaque else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
    }
}
