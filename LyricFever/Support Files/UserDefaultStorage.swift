//
//  UserDefaultStorage.swift
//  Lyric Fever
//
//  Created by Avi Wadhwa on 2025-07-17.
//

import Combine
import SwiftUI
//import ObservableDefaults
import ObservableUserDefault


//@ObservableDefaults
@Observable
class UserDefaultStorage {
    @ObservableUserDefault(.init(key: "translate", defaultValue: false, store: .standard))
    @ObservationIgnored var translate: Bool
    // Stored as an identifier string rather than a Locale.Language. UserDefaults only
    // accepts property-list types, and the macro hands the value over verbatim -- writing a
    // Locale.Language was silently dropped and always read back nil, so this setting could
    // never be saved. ViewModel.translationTargetLanguage wraps this back into a Language.
    @ObservableUserDefault(.init(key: "translationTargetLanguageIdentifier", store: .standard))
    @ObservationIgnored var translationTargetLanguageIdentifier: String?
//    var furigana = false
    #if os(macOS)
    @ObservableUserDefault(.init(key: "showSongDetailsInMenubar", defaultValue: false, store: .standard))
    @ObservationIgnored var showSongDetailsInMenubar: Bool
    #endif
    @ObservableUserDefault(.init(key: "romanize", defaultValue: false, store: .standard))
    @ObservationIgnored var romanize: Bool
    @ObservableUserDefault(.init(key: "romanizeMetadata", defaultValue: true, store: .standard))
    @ObservationIgnored var romanizeMetadata: Bool
    @ObservableUserDefault(.init(key: "chinesePreference", defaultValue: 0, store: .standard))
    @ObservationIgnored var chinesePreference: Int
    #if os(macOS)
    @ObservableUserDefault(.init(key: "spotifyConnectDelayCount", defaultValue: 400, store: .standard))
    @ObservationIgnored var spotifyConnectDelayCount: Int
    @ObservableUserDefault(.init(key: "hasMigrated", defaultValue: false, store: .standard))
    @ObservationIgnored var hasMigrated: Bool
    
    // User setting: use album art color or user-set currentBackground
    
    #endif

    #if os(macOS)
    // False: Spotify, True: Apple Music
    @ObservableUserDefault(.init(key: "spotifyOrAppleMusic", defaultValue: false, store: .standard))
    @ObservationIgnored var spotifyOrAppleMusic: Bool
    #endif
    @ObservableUserDefault(.init(key: "hasOnboarded", defaultValue: false, store: .standard))
    @ObservationIgnored var hasOnboarded: Bool
    @ObservableUserDefault(.init(key: "hasTranslated", defaultValue: false, store: .standard))
    @ObservationIgnored var hasTranslated: Bool
    @ObservableUserDefault(.init(key: "truncationLength", defaultValue: 40, store: .standard))
    @ObservationIgnored var truncationLength: Int
}
