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

    init(imageText: String, buttonState: ButtonState, slashed: Bool = false) {
        self.imageText = imageText
        self.buttonState = buttonState
        self.slashed = slashed
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
    let onClick: () -> Void

    init(
        buttonText: String,
        imageText: String,
        buttonState: ButtonState,
        slashed: Bool = false,
        onClick: @escaping () -> Void
    ) {
        self.buttonText = buttonText
        self.imageText = imageText
        self.buttonState = buttonState
        self.slashed = slashed
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
        .buttonStyle(SmallMenubarButtonStyle(imageText: imageText, buttonState: buttonState, slashed: slashed))
        .disabled(disabled)
        .buttonStyle(.borderless)
    }
}

/// "N/A" set like a percent sign: N above the stroke, A below it.
///
/// It marks a control that has nothing to work with -- a song no source has lyrics for -- as
/// distinct from one that failed. An exclamation mark is reserved for the latter: a warning on
/// a song that simply has no words trains the eye to ignore warnings.
struct UnavailableBadge: View {
    var body: some View {
        ZStack {
            Capsule()
                .frame(width: 1.5, height: 13)
                // Leaning the way a solidus does, top to the right.
                .rotationEffect(.degrees(20))
            Text(verbatim: "N")
                .font(.system(size: 7, weight: .heavy))
                .offset(x: -3.5, y: -4)
            Text(verbatim: "A")
                .font(.system(size: 7, weight: .heavy))
                .offset(x: 3.5, y: 4)
        }
        .frame(width: 13, height: 15)
        .accessibilityLabel(Text("No lyrics available"))
    }
}
