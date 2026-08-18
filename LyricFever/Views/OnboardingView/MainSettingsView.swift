//
//  MainSettingsView.swift
//  Lyric Fever
//
//  Created by Avi Wadhwa on 2025-07-26.
//

//
//  MainSettingsView.swift
//  Lyric Fever
//
//  Created by Avi Wadhwa on 2025-07-19.
//

import SwiftUI
import SDWebImageSwiftUI

enum MainSettingsError: Error, Identifiable, CaseIterable {
    case openAppleMusic
    case missingAuthorization
    case authorized
    
    var id: Self { self }
    
    var description: LocalizedStringKey {
        switch self {
        case .openAppleMusic:
            return LocalizedStringKey("Please open Apple Music!")
        case .missingAuthorization:
            return LocalizedStringKey("Please give required permissions!")
        case .authorized:
            return " "
        }
    }
}

struct MainSettingsView: View {
    @Environment(ViewModel.self) var viewModel
    @State var permissionDenied: Bool = false
    @State var error: MainSettingsError = .openAppleMusic
    
    @ViewBuilder
    var permissionDeniedView: some View {
        AnimatedImage(name: "newPermissionMac.gif")
            .resizable()
            .frame(width: 397, height: 340)
        HStack {
            Button("Open Automation Panel", action: {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
                NSWorkspace.shared.open(url)
            })
        }
    }
    
    @ViewBuilder
    var onboardView: some View {
        Image("hi")
            .resizable()
            .frame(width: 150, height: 150, alignment: .center)
                    
        Text("Welcome to Lyric Fever! 🎉")
            .font(.largeTitle)
                    
        Text("Please give Apple Music permissions")
            .font(.title)
    }
    
    @ViewBuilder
    var permissionsOrNextButton: some View {
        if error == .authorized {
            NavigationLink("Next", destination: FinalTruncationView())
                .font(.headline)
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
        } else {
            Button("Give Apple Music Permissions") {
                if !viewModel.appleMusicPlayer.isRunning {
                    error = .openAppleMusic
                } else if !viewModel.appleMusicPlayer.isAuthorized {
                    error = .openAppleMusic
                    permissionDenied = true
                } else {
                    permissionDenied = false
                    error = .authorized
                }
            }
        }
    }
    
    var body: some View {
        @Bindable var viewmodel = viewModel
        NavigationStack {
            VStack(alignment: .center, spacing: 20) {
                Group {
                    if permissionDenied {
                        permissionDeniedView
                    } else {
                        onboardView
                    }
                }
                .transition(.fade)
                
                Text(error.description)
                    .transition(.opacity)
                            
                permissionsOrNextButton
                    .frame(height: 40)
                
                VStack {
                    Text("Email me at [aviwad@gmail.com](mailto:aviwad@gmail.com) for any support")
                    Text(verbatim: "⚠️ Disclaimer: I do not own the rights to Spotify or the lyric content presented.\nMusixmatch and Spotify own all rights to the lyrics.\nTranslations by InTheManXG and ARui-tw")
                    Text("[Lyric Fever GitHub](https://github.com/aviwad/LyricFever)\nVersion 3.3")
                }
                    .multilineTextAlignment(.center)
                    .font(.callout)
                    .padding(.top, 10)
                    .frame(alignment: .bottom)
            }
            .animation(.bouncy, value: permissionDenied)
            .animation(.bouncy, value: error)
        }
    }
}
