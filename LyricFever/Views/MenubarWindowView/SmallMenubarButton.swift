//
//  MenubarButton.swift
//  Lyric Fever
//
//  Created by Avi Wadhwa on 2025-08-04.
//

import SwiftUI

public struct SmallMenubarButtonStyle: ButtonStyle {
    let imageText: String
    let buttonState: ButtonState
    let slashed: Bool
    /// Turns the icon while work is in flight. The artwork used to carry that job, but dimming
    /// and spinning over the album art hid the one thing on the panel worth looking at.
    var spinning: Bool = false
    @State private var spinAngle: Double = 0

    init(imageText: String, buttonState: ButtonState, slashed: Bool = false, spinning: Bool = false) {
        self.imageText = imageText
        self.buttonState = buttonState
        self.slashed = slashed
        self.spinning = spinning
    }
    
    var disabled: Bool {
        buttonState == .disabled
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 5) {
            ZStack {
                if buttonState == .loading {
                    ProgressView()
                        .controlSize(.small)
//                        .padding(.vertical, 16)
                } else {
                    HStack(spacing: 2) {
                        Image(systemName: imageText)
                            .controlSize(buttonState == .missing ? .small : .regular)
                            .bold(buttonState != .missing)
                            .rotationEffect(.degrees(spinAngle))
                            .onChange(of: spinning, initial: true) {
                                if spinning {
                                    withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                                        spinAngle = 360
                                    }
                                } else {
                                    withAnimation(.smooth(duration: 0.2)) { spinAngle = 0 }
                                }
                            }
                        if buttonState == .missing {
                            UnavailableBadge()
                        }
                    }
                    .menubarGlassForegroundStyle(
                        glass: buttonState.glassForegroundStyle,
                        fallback: buttonState.foregroundStyle
                    )
                    if slashed || disabled {
                        Capsule()
                            .fill(Color.white)
                            .frame(width: 32, height: 2)
                            .rotationEffect(.degrees(-45))
                    }
                }
            }
            .frame(height: 15)
        }
        .transition(.scale)
        .animation(.bouncy, value: buttonState)
        .frame(minWidth: 30, maxWidth: .infinity)
        .padding(.vertical, 16)
        .menubarGlass(
            tint: buttonState.glassTint,
            interactive: buttonState.glassIsInteractive,
            cornerRadius: 12,
            fallback: Rectangle()
                .fill(buttonState.fillStyle)
                .brightness(disabled ? 0.05 : 0.3)
                .opacity(disabled ? 1 : 0.7)
                .clipShape(.rect(cornerRadius: 12))
                .shadow(radius: disabled ? 0 : 7)
        )
        .opacity(configuration.isPressed ? 0.7 : 1)
        .environment(\.colorScheme, .dark)
    }
}

public struct SmallMenubarButton: View {
    let buttonText: String
    let imageText: String
    let buttonState: ButtonState
    let slashed: Bool
    let spinning: Bool
    let onClick: () -> Void

    init(
        buttonText: String,
        imageText: String,
        buttonState: ButtonState,
        slashed: Bool = false,
        spinning: Bool = false,
        onClick: @escaping () -> Void
    ) {
        self.buttonText = buttonText
        self.imageText = imageText
        self.buttonState = buttonState
        self.slashed = slashed
        self.spinning = spinning
        self.onClick = onClick
    }
    
    var disabled: Bool {
        buttonState == .disabled
    }
    
    public var body: some View {
        Button {
            onClick()
        } label: {
            EmptyView()
        }
        .buttonStyle(SmallMenubarButtonStyle(imageText: imageText, buttonState: buttonState, slashed: slashed, spinning: spinning))
        .disabled(disabled)
        .buttonStyle(.borderless)
    }
}

/// "N/A" set like a percent sign: N above the stroke, A below it, in the rounded system face
/// so it sits with the soft glass and the rounded button corners rather than against them.
///
/// It marks a control that has nothing to work with -- a song no source has lyrics for -- as
/// distinct from one that failed. An exclamation mark is reserved for the latter: a warning on
/// a song that simply has no words trains the eye to ignore warnings.
struct UnavailableBadge: View {
    var body: some View {
        ZStack {
            Capsule()
                .frame(width: 1.6, height: 13)
                // Leaning the way a solidus does, top to the right. A capsule rather than a
                // rectangle so its ends are rounded like the letters beside it.
                .rotationEffect(.degrees(20))
            Text(verbatim: "N")
                .font(.system(size: 7.5, weight: .bold, design: .rounded))
                .offset(x: -3.5, y: -4)
            Text(verbatim: "A")
                .font(.system(size: 7.5, weight: .bold, design: .rounded))
                .offset(x: 3.5, y: 4)
        }
        .frame(width: 13, height: 15)
        .accessibilityLabel(Text("No lyrics available"))
    }
}
