//
//  GlobalKeyboardShortcutsView.swift
//  Lyric Fever
//
//  Created by Avi Wadhwa on 2025-09-11.
//

import SwiftUI
import KeyboardShortcuts

struct GlobalKeyboardShortcutsView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Toggle displaying lyrics:", name: .init("lyrics"))
            KeyboardShortcuts.Recorder("Toggle translations:", name: .init("translate"))
            KeyboardShortcuts.Recorder("Toggle romanizations:", name: .init("romanize"))
        }
    }
}
