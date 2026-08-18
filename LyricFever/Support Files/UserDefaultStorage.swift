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
    // Persisted rather than a plain flag: it describes the listening setup, which does not
    // change between launches, and resetting it each time silently put the lyrics two seconds
    // ahead of AirPlay audio again.
    @ObservableUserDefault(.init(key: "airplayDelay", defaultValue: false, store: .standard))
    @ObservationIgnored var airplayDelay: Bool
    @ObservableUserDefault(.init(key: "romanizeMetadata", defaultValue: true, store: .standard))
    @ObservationIgnored var romanizeMetadata: Bool
    @ObservableUserDefault(.init(key: "chinesePreference", defaultValue: 0, store: .standard))
    @ObservationIgnored var chinesePreference: Int
    #if os(macOS)
    @ObservableUserDefault(.init(key: "hasMigrated", defaultValue: false, store: .standard))
    @ObservationIgnored var hasMigrated: Bool
    
    // User setting: use album art color or user-set currentBackground
    
    #endif

    @ObservableUserDefault(.init(key: "hasOnboarded", defaultValue: false, store: .standard))
    @ObservationIgnored var hasOnboarded: Bool
    @ObservableUserDefault(.init(key: "hasTranslated", defaultValue: false, store: .standard))
    @ObservationIgnored var hasTranslated: Bool
    @ObservableUserDefault(.init(key: "truncationLength", defaultValue: 40, store: .standard))
    @ObservationIgnored var truncationLength: Int
    // How much menu bar the lyric occupies, in points. A width rather than a character count:
    // the same forty characters are twice as wide in Chinese as in English, and it is the
    // width the user is actually budgeting.
    @ObservableUserDefault(.init(key: "menubarWidth", defaultValue: 180, store: .standard))
    @ObservationIgnored var menubarWidth: Int
}
