//
//  LyricWidthIcon.swift
//  Lyric Fever
//

import SwiftUI

/// One triangle cut down the middle into two right triangles, parted by `gap`.
///
/// SF Symbols has no glyph for this. Every `righttriangle` variant ships the pair welded to a
/// double-headed arrow above it, and `triangle.lefthalf.filled` is one whole triangle with half
/// of it filled -- not two halves with air between them. So the shape is drawn here.
struct SplitTriangle: Shape {
    var gap: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let middle = rect.midX
        // Left half: right angle at the bottom of the cut, hypotenuse falling away to the left.
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: middle - gap / 2, y: rect.maxY))
        path.addLine(to: CGPoint(x: middle - gap / 2, y: rect.minY))
        path.closeSubpath()
        // Right half: the same, mirrored.
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: middle + gap / 2, y: rect.maxY))
        path.addLine(to: CGPoint(x: middle + gap / 2, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// Marks the slider that sets how much menu bar the lyric may occupy.
struct LyricWidthIcon: View {
    var gap: CGFloat = 2.2
    var filled: Bool = false

    var body: some View {
        Group {
            if filled {
                SplitTriangle(gap: gap).fill()
            } else {
                SplitTriangle(gap: gap).stroke(lineWidth: 1.6)
            }
        }
        .frame(width: 14, height: 12)
        .foregroundStyle(.secondary)
    }
}
