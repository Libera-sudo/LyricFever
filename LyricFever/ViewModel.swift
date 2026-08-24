//
//  viewModel.swift
//  SpotifyLyricsInMenubar
//
//  Created by Avi Wadhwa on 14/08/23.
//

import Foundation
import NaturalLanguage
#if os(macOS)
#endif
import CoreData
import SwiftUI
import MediaPlayer
#if os(macOS)
import Translation
import KeyboardShortcuts
import MediaRemoteAdapter
#endif

@MainActor
@Observable class ViewModel {
    static let shared = ViewModel()
    
    // Apple Music Tahoe broken AppleScript workaround
    //
    // No bundle identifier: upstream removed that parameter in the same commit that fixed a
    // pipe deadlock, on the grounds that the filtering "never worked". Nothing is lost —
    // payloads are filtered by bundleIdentifier where they are consumed — and the deadlock
    // mattered: artwork exceeds the 64KB pipe buffer, so on the older build it never arrived
    // and every track showed a placeholder cover.
    let musicController = MediaController()
//    var appleMusicUniqueIdentifier: String?

    var currentlyPlaying: String?
    
    var artworkImage: NSImage?
    var currentArtworkURL: URL?

    var duration: Int = 0
    var currentTime = CurrentTimeWithStoredDate(currentTime: 0)
    
    var formattedCurrentTime: String {
        let baseTime = currentTime.currentTime
        let totalSeconds = Int(baseTime) / 1000
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: TimeInterval(totalSeconds)) ?? "0:00"
    }
    private func initAppleMusicWorkaround() {
        musicController.onTrackInfoReceived = { data in
            print("Track info received")
            Task { @MainActor in
//                if self.appleMusicUniqueIdentifier == data.payload.uniqueIdentifier {
//                    print("Apple Music Artwork Workaround: Ignoring artwork for existing song")
//                    return
//                } else {
//                    self.appleMusicUniqueIdentifier = data.payload.uniqueIdentifier
//                }
                guard let artwork = data?.payload.artwork else {
                    if self.currentlyPlaying == nil {
                        self.artworkImage = nil
                    }
                    print("Apple Music Artwork Workaround: Ignoring No Artwork")
                    return
                }
                // Match on the bundle identifier, not applicationName: the latter is the
                // app's *localised* display name, so it reads "音樂" on a Chinese system and
                // never equals "Music". That silently dropped every artwork payload for
                // anyone not running an English system.
                guard data?.payload.bundleIdentifier == "com.apple.Music" else {
                    return
                }
                self.artworkImage = artwork
                // Colour is derived here rather than alongside the lyrics. Artwork arrives on
                // its own schedule, so computing it when lyrics land found `artworkImage` still
                // nil about as often as not -- and that only ever ran on a network fetch, so a
                // song answered from the cache never got a colour at all. This is the one moment
                // an image is guaranteed to exist.
                self.callColorDataServiceOnLyricColorOrArtwork()
                self.setBackgroundColor()
            }
            // This will only be called for Apple Music events
        }
        musicController.startListening()
    }
    
    func formattedCurrentTime(for date: Date) -> String {
        let baseTime = currentTime.currentTime
        let delta = date.timeIntervalSince(currentTime.storedDate)
//        print("Formatted Current Time: delta is \(delta)")
        let totalSeconds = Int((baseTime + delta) / 1000)
//        print("total seconds should be \(totalSeconds)")
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: TimeInterval(totalSeconds)) ?? "0:00"
    }
    
    var formattedDuration: String {
        let totalSeconds = duration / 1000
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: TimeInterval(totalSeconds)) ?? "0:00"
    }
    
    var appleMusicPlayer = AppleMusicPlayer()
    
    #if os(macOS)
    var translationSessionConfig: TranslationSession.Configuration?
    #endif
    var userDefaultStorage = UserDefaultStorage()
    
    #if os(macOS)
    // nil to deal with previously saved songs that don't have lang saved with them
    // or for LRCLIB
    var currentBackground: Color? = nil

    var canDisplayLyrics: Bool {
        showLyrics && !lyricsIsEmptyPostLoad
    }

    var currentlyPlayingAppleMusicPersistentID: String? = nil
    #endif
    
    var currentlyPlayingName: String?
    var currentlyPlayingArtist: String?
    var currentAlbumName: String?
    var currentlyPlayingLyrics: [LyricLine] = []
    var currentlyPlayingLyricsIndex: Int?
    var isPlaying: Bool = false
    var romanizedLyrics: [String] = []
    var chineseConversionLyrics: [String] = []
    var translatedLyric: [String] = []
    var showLyrics = true

    var isFetchingTranslation = false
    var translationAlreadyInTargetLanguage = false
    var translationExists: Bool { !translatedLyric.isEmpty}

    /// The line the menu bar would draw if romanization were off: the translation when there is
    /// one, then the script-converted lyrics, then the lyrics themselves. Romanization reads
    /// this rather than always reading the original, so a translation into Japanese or Chinese
    /// can be read in Latin letters too -- which is also why romanization sits at the outermost
    /// step of the display chain in MenubarLabelView rather than a rung below translation.
    var lyricsForDisplayWithoutRomanization: [String] {
        if translationExists {
            return translatedLyric
        } else if !chineseConversionLyrics.isEmpty {
            return chineseConversionLyrics
        } else {
            return currentlyPlayingLyrics.map(\.words)
        }
    }
    // Tracks the in-flight local translation so a song change cancels the previous one
    // instead of letting a stale result overwrite the new song's lyrics.
    private var localTranslationTask: Task<Void, Never>?
    
    // CoreData container (for saved lyrics)
    let coreDataContainer: NSPersistentContainer
    
    // Async Tasks (Lyrics fetch, Apple Music -> Spotify ID fetch, Lyrics Updater)
    private var currentFetchTask: Task<[LyricLine], Error>?
    private var currentLyricsUpdaterTask: Task<Void,Error>?
    var isFetching = false
    private var currentAppleMusicFetchTask: Task<Void,Error>?
    
    // Songs are translated to user locale
    let systemLocale: Locale
    let systemLocaleString: String
    var translationSourceLanguage: Locale.Language?
//    var translationTargetLanguage: Locale.Language?
    /// The user's chosen translation target, or nil to follow the system.
    var translationTargetLanguage: Locale.Language? {
        get {
            guard let identifier = userDefaultStorage.translationTargetLanguageIdentifier else { return nil }
            return Locale.Language(identifier: identifier)
        }
        set {
            userDefaultStorage.translationTargetLanguageIdentifier = newValue?.maximalIdentifier
        }
    }

    var userLocaleLanguage: Locale.Language {
        if let translationTargetLanguage {
            return translationTargetLanguage
        } else {
            return systemLocale.language
        }
    }
    var userLocaleLanguageString: String {
        if let translationTargetLanguage, let translationTargetLanguageString = Locale.current.localizedString(forIdentifier: translationTargetLanguage.minimalIdentifier) {
            return translationTargetLanguageString
        } else {
            return systemLocaleString
        }
    }

    // Delayed variable to hook onto for whether to display lyrics or not.
    // Prevents flickering that occurs when we directly bind to currentlyPlayingLyrics.isEmpty()
    var lyricsIsEmptyPostLoad: Bool = true
    // Separates a track that has no vocals from one whose lyrics were not found.
    var currentTrackIsInstrumental = false

    /// Width the menubar lyric is drawn at, in points. Held steady while a song plays, and
    /// remeasured only when the screen arrangement changes -- see `MenubarSpace`.
    var menubarLyricWidth: CGFloat = 180

    /// The latest ceiling, headroom already deducted, or nil when nothing could be measured.
    /// Published so the width slider can hatch the part of its track there is no room for.
    ///
    /// One caveat for the reader: once the item has been pushed past the notch,
    /// `MenubarSpace.availableWidth` answers with the current width minus 32 -- an instruction
    /// to shrink rather than a measurement. As a hatch boundary it still tells the truth, that
    /// the lyric is wider than the bar can hold, but it is not a reading of free space.
    var measuredMenubarWidth: CGFloat?

    @ObservationIgnored private var initialMeasurement: Task<Void, Never>?

    /// Measures as soon as the status item is actually in the menu bar, however long that takes.
    ///
    /// The item's window exists well before it is placed: measured 2026-08-24, a second after
    /// launch the windows were still parked below the screen (maxY 0 against the bar's 982). The
    /// single measurement that used to run at that moment therefore failed, fell back to the
    /// slider's raw cap, and nothing ever retried -- the remaining triggers are a screen change,
    /// a drag of the slider, and this item's own window moving, and a window that is created
    /// already in place never moves. So the whole session ran unmeasured, and whether that
    /// overflowed came down to how crowded the bar happened to be. Hence "randomly".
    ///
    /// Bounded, because one of the failures never resolves: with no notched screen at all there
    /// is nothing to measure against and retrying would go on forever.
    func measureUntilPlaced() {
        initialMeasurement?.cancel()
        initialMeasurement = Task { @MainActor [weak self] in
            for _ in 0..<25 {
                guard let self, !Task.isCancelled else { return }
                self.remeasureMenubarWidth()
                if self.measuredMenubarWidth != nil { return }
                try? await Task.sleep(for: .milliseconds(400))
            }
            print("Menubar: still unmeasured after 10s -- running on the slider's cap")
        }
    }

    /// Coalesces a burst of moves into one pass. Cancelled and replaced rather than queued.
    @ObservationIgnored private var menubarMoveRemeasure: Task<Void, Never>?

    /// The bar packs from the right, so anything another app adds or removes shifts this item,
    /// and that shift is the only notice available that the free space changed -- other apps'
    /// status items cannot be enumerated without Screen Recording, and the bar comes back from
    /// CGWindowList as one full-width WindowServer surface.
    func statusItemDidMove() {
        menubarMoveRemeasure?.cancel()
        menubarMoveRemeasure = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.remeasureMenubarWidth(afterStatusItemMove: true)
        }
    }

    func remeasureMenubarWidth(afterStatusItemMove: Bool = false) {
        let cap = CGFloat(userDefaultStorage.menubarWidth)
        // A margin so the lyric never butts straight up against the notch.
        // Deliberately short of what fits. The space beside the notch is not ours to fill: the
        // frontmost app's menus claim room on the other side of it, and any app may add a
        // status item at any moment. Taking all of it means the first thing that needs room
        // collapses every status item behind a chevron, so a good part of the measurement is
        // left unclaimed as headroom.
        let headroom: CGFloat = 48
        let measured = MenubarSpace.availableWidth(currentDrawnWidth: menubarLyricWidth).map { $0 - headroom }
        measuredMenubarWidth = measured
        let width = min(cap, measured ?? cap)
        let clamped = max(width, 80)
        // Applying a new width moves the item, which posts another move, which lands back here:
        // without a deadband the two chase each other a point at a time. It belongs to this path
        // only -- dragging the slider stays exact to the point.
        if afterStatusItemMove, abs(clamped - menubarLyricWidth) < 8 { return }
        if clamped != menubarLyricWidth {
            // Which of the two won matters and used to be invisible: an unmeasured fallback and
            // a genuinely cap-limited measurement both printed the same width.
            let reason: String
            if let measured {
                reason = measured < cap ? "space \(Int(measured))pt" : "cap \(Int(cap))pt"
            } else {
                reason = "UNMEASURED, fell back to cap \(Int(cap))pt"
            }
            print("Menubar: lyric width \(Int(menubarLyricWidth))pt -> \(Int(clamped))pt (\(reason))")
            menubarLyricWidth = clamped
        }
    }
    
    var currentDuration: Int? {
        appleMusicPlayer.duration
    }
    var isPlayerRunning: Bool {
        appleMusicPlayer.isRunning
    }
    
    var lRCLyricProvider = LRCLIBLyricProvider()
    var netEaseLyricProvider = NetEaseLyricProvider()
    var qqMusicLyricProvider = QQMusicLyricProvider()
    var musixmatchLyricProvider = MusixmatchLyricProvider()
    #if os(macOS)
    var localFileUploadProvider = LocalFileUploadProvider()
    #endif
    @ObservationIgnored lazy var allNetworkLyricProviders: [LyricProvider] = [lRCLyricProvider, netEaseLyricProvider, qqMusicLyricProvider, musixmatchLyricProvider]
    
    // custom order because LRCLIB is tweaking for the time being
    @ObservationIgnored lazy var allNetworkLyricProvidersForSearch: [LyricProvider] = [netEaseLyricProvider, qqMusicLyricProvider, lRCLyricProvider, musixmatchLyricProvider]
    
    var isFirstFetch = true
    
    init() {
        // Set our user locale for translation language
        systemLocale = Locale.preferredLocale()
        systemLocaleString = Locale.preferredLocaleString() ?? ""
        
        // Load our CoreData container for Lyrics
        coreDataContainer = NSPersistentContainer(name: "Lyrics")
        
        initAppleMusicWorkaround()
        
        coreDataContainer.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Error: \(error.localizedDescription)")
            }
            self.coreDataContainer.viewContext.mergePolicy = NSMergePolicy.overwrite
        }
        #if os(macOS)
        migrateTimestampsIfNeeded(context: coreDataContainer.viewContext)
        // Spotify login is gone, so its stored cookie should not linger.
        UserDefaults.standard.removeObject(forKey: "spDcCookie")
        
        // onAppear()
        print("on appear running")
        #endif
        guard userDefaultStorage.hasOnboarded else {
            return
        }
        guard isPlayerRunning else {
            return
        }
        print("Application just started. lets check whats playing")
        
        isPlaying = appleMusicPlayer.isPlaying
        userDefaultStorage.hasOnboarded = appleMusicPlayer.isAuthorized
        KeyboardShortcuts.onKeyUp(for: .init("lyrics")) { [self] in
            showLyrics.toggle()
        }
        KeyboardShortcuts.onKeyUp(for: .init("translate")) { [self] in
            userDefaultStorage.translate.toggle()
        }
        KeyboardShortcuts.onKeyUp(for: .init("romanize")) { [self] in
            userDefaultStorage.romanize.toggle()
        }
        guard userDefaultStorage.hasOnboarded else {
            return
        }
        
    }
    
    @MainActor
    func fetchAllNetworkLyrics() async -> NetworkFetchReturn {
        guard let currentlyPlaying, let currentlyPlayingName else {
            return NetworkFetchReturn(lyrics: [])
        }
        var isInstrumental = false
        for networkLyricProvider in allNetworkLyricProviders {
            do {
                print("FetchAllNetworkLyrics: fetching from \(networkLyricProvider.providerName)")
                let lyrics = try await networkLyricProvider.fetchNetworkLyrics(trackName: currentlyPlayingName, trackID: currentlyPlaying, currentlyPlayingArtist: currentlyPlayingArtist, currentAlbumName: currentAlbumName, duration: duration > 0 ? duration : nil)
                if !lyrics.lyrics.isEmpty {
                    currentTrackIsInstrumental = false
                    print("FetchAllNetworkLyrics: returning lyrics from \(networkLyricProvider.providerName)")
                    // thats how i save to coredata
                    let _ = SongObject(from: lyrics.lyrics, with: coreDataContainer.viewContext, trackID: currentlyPlaying, trackName: currentlyPlayingName)
                    saveCoreData()
                    return lyrics
                } else {
                    isInstrumental = isInstrumental || lyrics.isInstrumental
                    print("FetchAllNetworkLyrics: no lyrics from \(networkLyricProvider.providerName)")
                }
            } catch {
                print("Caught exception on \(networkLyricProvider.providerName): \(error)")
            }
        }
        if !isInstrumental, let genre = appleMusicPlayer.genre {
            let instrumentalGenres = ["Classical", "Instrumental", "New Age", "Ambient"]
            // This is a guess, not knowledge: Classical also includes opera and art songs, so
            // missing lyrics can mislabel a vocal work. One wrong menu-bar word is a smaller
            // cost than presenting common concertos and other wordless pieces as failed lookups.
            isInstrumental = instrumentalGenres.contains {
                genre.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
        currentTrackIsInstrumental = isInstrumental
        return NetworkFetchReturn(lyrics: [], isInstrumental: isInstrumental)
    }
    
    #if os(macOS)
    func refreshLyrics() async throws {
        // todo: romanize
        print("Refresh Lyrics: Re-deriving the Apple Music track key")
        try await appleMusicFetch()
        guard let currentlyPlaying, let currentlyPlayingName, appleMusicPlayer.duration != nil else {
            return
        }
        print("Calling refresh lyrics")
        guard let finalLyrics = await self.fetch(for: currentlyPlaying, currentlyPlayingName, checkCoreDataFirst: false) else {
            print("Refresh Lyrics: Failed to run network fetch")
            return
        }
        if finalLyrics.isEmpty {
            currentlyPlayingLyricsIndex = nil
        }
        setNewLyricsColorTranslationRomanizationAndStartUpdater(with: finalLyrics)
//        currentlyPlayingLyrics = finalLyrics
//        setBackgroundColor()
//        romanizeDidChange()
//        reloadTranslationConfigIfTranslating()
//        lyricsIsEmptyPostLoad = currentlyPlayingLyrics.isEmpty
//        print("HELLOO")
//        if isPlaying, !currentlyPlayingLyrics.isEmpty, showLyrics, userDefaultStorage.hasOnboarded {
//            startLyricUpdater()
//        }
        // we call this in self.fetch
//        callColorDataServiceOnLyricColorOrArtwork()
    }
    
    func callColorDataServiceOnLyricColorOrArtwork() {
        if let currentlyPlaying, let backgroundColor = artworkImage?.findWhiteTextLegibleMostSaturatedDominantColor() {
            ColorDataService.saveColorToCoreData(trackID: currentlyPlaying, songColor: backgroundColor)
            print("ViewModel Refresh Lyrics: New color \(backgroundColor) saved for track \(currentlyPlaying)")
        }
    }
    
    // Run only on first 2.1 run. Strips whitespace from saved lyrics, and extends final timestamp to prevent karaoke mode racecondition (as well as song on loop race condition)
    func migrateTimestampsIfNeeded(context: NSManagedObjectContext) {
        if !userDefaultStorage.hasMigrated {
            let fetchRequest: NSFetchRequest<SongObject> = SongObject.fetchRequest()
            do {
                let objects = try context.fetch(fetchRequest)
                for object in objects {
                    var timestamps = object.lyricsTimestamps
                    if let lastIndex = timestamps.indices.last {
                        timestamps[lastIndex] = timestamps[lastIndex] + 5000
                        object.lyricsTimestamps = timestamps
                    }
                    var strings = object.lyricsWords
                    let indicesToRemove = strings.indices.filter { strings[$0].isEmpty }
                    strings.removeAll { $0.isEmpty }
                    for index in indicesToRemove.reversed() {
                        timestamps.remove(at: index)
                    }

                    // Update the object properties
                    object.lyricsWords = strings
                    object.lyricsTimestamps = timestamps
                }
                try context.save()
                
                // Mark migration as done
                userDefaultStorage.hasMigrated = true
            } catch {
                print("Error migrating data: \(error)")
            }
        }
    }
    
    func openSettings(_ openWindow: OpenWindowAction) {
        openWindow(id: "onboarding")
        NSApplication.shared.activate(ignoringOtherApps: true)
//        // send notification to check auth
//        NotificationCenter.default.post(name: Notification.Name("didClickSettings"), object: nil)
    }
    #endif
    
    // The panel no longer carries a reload button or a delete button: this toggle is both.
    // Switching lyrics off throws away the current song's cached lyrics, switching them back
    // on downloads them again, so off-then-on is how a bad match gets redownloaded.
    func toggleLyrics() {
        if showLyrics {
            #if os(macOS)
            Task {
                do {
                    // refreshLyrics() restarts the updater itself once the lyrics land,
                    // so there is no startLyricUpdater() call to pair with this.
                    try await refreshLyrics()
                } catch {
                    print("Couldn't refresh lyrics on re-enabling them: \(error)")
                }
            }
            #else
            startLyricUpdater()
            #endif
        } else {
            stopLyricUpdater()
            if let currentlyPlaying {
                deleteLyric(trackID: currentlyPlaying)
            }
        }
    }
    
    func openTranslationHelpOnFirstRun(_ openURL: OpenURLAction) {
        if !userDefaultStorage.hasTranslated {
            openURL(URL(string: "https://aviwadhwa.com/TranslationHelp")!)
        }
        userDefaultStorage.hasTranslated = true
    }
    
    @MainActor
    func translationTask(_ session: TranslationSession) async {
        isFetchingTranslation = true
        let translationResponse = await TranslationService.translationTask(session, request: currentlyPlayingLyrics.map { TranslationSession.Request(lyric: $0) })
        
        switch translationResponse {
            case .success(let array):
                print("Translation Service: isFetchingTranslation set to false due to success")
                isFetchingTranslation = false
                if currentlyPlayingLyrics.count == array.count {
                    translatedLyric = restoringChants(array.map { $0.targetText })
                    romanizeDidChange()
                }
            case .needsConfigUpdate(let language):
                // TODO: why do i sleep?
//                try? await Task.sleep(for: .seconds(1))
                translationSessionConfig = TranslationSession.Configuration(source: language, target: userLocaleLanguage)
            case .failure:
                print("Translation Service: isFetchingTranslation set to false due to failure")
                isFetchingTranslation = false
                return
        }
    }
    
    /// Enough of the song to tell its scripts apart, without walking a long lyric sheet every
    /// time the panel redraws.
    private var lyricsScriptSample: String {
        lyricsForDisplayWithoutRomanization.prefix(40).joined(separator: "\n")
    }

    /// Whether romanizing this song would change anything -- asked directly, by running the
    /// transform, rather than by listing scripts. Latin lyrics come back untouched, accents and
    /// all, so French and German answer no alongside English.
    var lyricsCanBeRomanized: Bool {
        let sample = lyricsScriptSample
        return !sample.isEmpty && sample.applyingTransform(.toLatin, reverse: false) != sample
    }

    func romanizeDidChange() {
        if userDefaultStorage.romanize {
            print("Romanized Lyrics generated for song \(String(describing: currentlyPlaying))")
            romanizedLyrics = RomanizerService.generateRomanizedLyrics(lyricsForDisplayWithoutRomanization)
            
//            romanizeMetadata()
        } else {
            romanizedLyrics = []
        }
    }
    
    // Only called when Romanize is true
//    func romanizeMetadata() {
//        // Generate romanized metadata from name & artist
//        if userDefaultStorage.romanizeMetadata, let currentlyPlayingName, let romanizedName = RomanizerService.generateRomanizedString(currentlyPlayingName), let currentlyPlayingArtist, let romanizedArtist = RomanizerService.generateRomanizedString(currentlyPlayingArtist) {
//            self.currentlyPlayingName = romanizedName
//            self.currentlyPlayingArtist = romanizedArtist
//        }
//    }
    
    func romanizeName(_ currentlyPlayingName: String) -> String? {
        if let romanizedName = RomanizerService.generateRomanizedString(currentlyPlayingName) {
            return romanizedName
        }
        return nil
    }
    
    func romanizeArtist(_ currentlyPlayingArtist: String) -> String? {
        if let romanizedArtist = RomanizerService.generateRomanizedString(currentlyPlayingArtist) {
            return romanizedArtist
        }
        return nil
    }
    
    /// Which OpenCC conversion the original lyrics get, read off the translation target rather
    /// than a setting of its own. The two were separate controls that looked alike and meant
    /// different things -- one restyled the lyrics, the other picked a translation dialect --
    /// so they are now one answer to one question: which flavour of the language do I want to
    /// read. The cost is that lyrics only convert while Chinese is the target; asking for
    /// Traditional lyrics while translating into English is no longer expressible.
    private var targetChineseConversion: ChineseConversion {
        let target = userLocaleLanguage
        guard target.languageCode?.identifier == "zh" else { return .none }
        switch target.script?.identifier {
            case "Hans":
                return .simplified
            case "Hant":
                switch target.region?.identifier {
                    case "TW": return .traditionalTaiwan
                    case "HK": return .traditionalHK
                    default: return .traditionalNeutral
                }
            default:
                return .none
        }
    }

    func translationTargetLanguageDidChange() {
        let conversion = targetChineseConversion
        guard conversion != .none else {
            chineseConversionLyrics = []
            return
        }

        print("Generating Chinese conversion for song \(String(describing: currentlyPlaying)) to chinese style \(conversion.description)")
        //TODO: check if Task was cancelled
        let convertedLyrics: [String] = currentlyPlayingLyrics.compactMap {
            switch conversion {
                case .none:
                    return nil
                case .simplified:
                    return RomanizerService.generateMainlandTransliteration($0)
                case .traditionalNeutral:
                    return RomanizerService.generateTraditionalNeutralTransliteration($0)
                case .traditionalTaiwan:
                    return RomanizerService.generateTaiwanTransliteration($0)
                case .traditionalHK:
                    return RomanizerService.generateHongKongTransliteration($0)
            }
        }
        //TODO: check if Task was cancelled
        if !Task.isCancelled {
            chineseConversionLyrics = convertedLyrics
        }
    }
    
    func appleMusicPlaybackDidChange(_ notification: Notification) {
        if notification.userInfo?["Player State"] as? String == "Playing" {
            print("is playing")
            isPlaying = true
        } else {
            print("paused. timer canceled")
            isPlaying = false
            // manually cancels the lyric-updater task bc media is paused
        }
        let currentlyPlayingName = (notification.userInfo?["Name"] as? String)
        guard let currentlyPlayingName else {
            self.currentlyPlayingName = nil
            currentlyPlayingArtist = nil
            currentAlbumName = nil
            return
        }
        if currentlyPlayingName == "" {
            self.currentlyPlayingName = nil
            currentlyPlayingArtist = nil
            currentAlbumName = nil
        } else {
            self.currentlyPlayingName = currentlyPlayingName
            currentlyPlayingArtist = (notification.userInfo?["Artist"] as? String)
            currentAlbumName = (notification.userInfo?["Album"] as? String)
            if let duration = appleMusicPlayer.duration {
                self.duration = duration
            }
            print("REOPEN: currentlyPlayingName is \(currentlyPlayingName)")
            currentlyPlayingAppleMusicPersistentID = appleMusicPlayer.persistentID
        }
    }
    
    func onAppear() {
        setCurrentProperties()
    }
    
    func onCurrentlyPlayingIDChange() async {
        currentlyPlayingLyricsIndex = nil
        currentlyPlayingLyrics = []
        translatedLyric = []
        translationAlreadyInTargetLanguage = false
        romanizedLyrics = []
        chineseConversionLyrics = []
        currentTrackIsInstrumental = false
        
        if userDefaultStorage.hasOnboarded, let currentlyPlaying = currentlyPlaying, let currentlyPlayingName = currentlyPlayingName, let lyrics = await fetch(for: currentlyPlaying, currentlyPlayingName) {
            setNewLyricsColorTranslationRomanizationAndStartUpdater(with: lyrics)
//            currentlyPlayingLyrics = lyrics
//            setBackgroundColor()
//            romanizeDidChange()
//            reloadTranslationConfigIfTranslating()
//            lyricsIsEmptyPostLoad = lyrics.isEmpty
//            if isPlaying, !currentlyPlayingLyrics.isEmpty, showLyrics, userDefaultStorage.hasOnboarded {
//                print("STARTING UPDATER")
//                startLyricUpdater()
//            }
        }
    }
    
    private func setCurrentProperties() {
        if let currentTrackName = appleMusicPlayer.trackName, let currentArtistName = appleMusicPlayer.artistName, let duration = appleMusicPlayer.duration, let currentAlbumName = appleMusicPlayer.albumName {
            // Don't set currentlyPlaying here: the persistentID change triggers appleMusicFetch, which derives the key
            if currentTrackName == "" {
                currentlyPlayingName = nil
                currentlyPlayingArtist = nil
                self.currentAlbumName = nil
            } else {
                currentlyPlayingName = currentTrackName
                currentlyPlayingArtist = currentArtistName
                self.duration = duration
                self.currentAlbumName = currentAlbumName
            }
            print("ON APPEAR HAS UPDATED APPLE MUSIC SONG ID")
            currentlyPlayingAppleMusicPersistentID = appleMusicPlayer.persistentID
        }
    }

    func upcomingIndex(_ currentTime: Double) -> Int? {
        if let currentlyPlayingLyricsIndex {
            let newIndex = currentlyPlayingLyricsIndex + 1
            if newIndex >= currentlyPlayingLyrics.count {
                print("REACHED LAST LYRIC!!!!!!!!")
                // if current time is before our current index's start time, the user has scrubbed and rewinded
                // reset into linear search mode
                if currentTime < currentlyPlayingLyrics[currentlyPlayingLyricsIndex].startTimeMS {
                    return currentlyPlayingLyrics.firstIndex(where: {$0.startTimeMS > currentTime})
                }
                // we've reached the end of the song, we're past the last lyric
                //TODO: remove these
                #if os(macOS)
                currentlyPlayingAppleMusicPersistentID = nil
                #endif
                currentlyPlaying = nil
                return nil
            }
            else if  currentTime > currentlyPlayingLyrics[currentlyPlayingLyricsIndex].startTimeMS, currentTime < currentlyPlayingLyrics[newIndex].startTimeMS {
                print("just the next lyric")
                return newIndex
            }
        }
        // linear search through the array to find the first lyric that's right after the current time
        // done on first lyric update for the song, as well as post-scrubbing
        return currentlyPlayingLyrics.firstIndex(where: {$0.startTimeMS > currentTime})
    }
    
    func lyricUpdater() async throws {
        repeat {
            guard let currentTime = appleMusicPlayer.currentTime, let lastIndex: Int = upcomingIndex(currentTime) else {
                stopLyricUpdater()
                return
            }
            // If there is no current index (perhaps lyric updater started late and we're mid-way of the first lyric, or the user scrubbed and our index is expired)
            // Then we set the current index to the one before our anticipated index
            if currentlyPlayingLyricsIndex == nil && lastIndex > 0 {
                currentlyPlayingLyricsIndex = lastIndex-1
            }
            let nextTimestamp = currentlyPlayingLyrics[lastIndex].startTimeMS
            let diff = nextTimestamp - currentTime
            print("current time: \(currentTime)")
            self.currentTime = CurrentTimeWithStoredDate(currentTime: currentTime)
            print("next time: \(nextTimestamp)")
            print("the difference is \(diff)")
            try await Task.sleep(nanoseconds: UInt64(1000000*diff))
            print("lyrics exist: \(!currentlyPlayingLyrics.isEmpty)")
            print("last index: \(lastIndex)")
            print("currently playing lryics index: \(currentlyPlayingLyricsIndex)")
            if currentlyPlayingLyrics.count > lastIndex {
                currentlyPlayingLyricsIndex = lastIndex
            } else {
                currentlyPlayingLyricsIndex = nil
                
            }
            print(currentlyPlayingLyricsIndex ?? "nil")
        } while !Task.isCancelled
    }
    
    func startLyricUpdater() {
        currentLyricsUpdaterTask?.cancel()
        if !isPlaying || currentlyPlayingLyrics.isEmpty {
            return
        }
        // If an index exists, we're unpausing: meaning we must instantly find the current lyric
        if currentlyPlayingLyricsIndex != nil {
            guard let currentTime = appleMusicPlayer.currentTime, let lastIndex: Int = upcomingIndex(currentTime) else {
                stopLyricUpdater()
                return
            }
            // If there is no current index (perhaps lyric updater started late and we're mid-way of the first lyric, or the user scrubbed and our index is expired)
            // Then we set the current index to the one before our anticipated index
            if lastIndex > 0 {
                currentlyPlayingLyricsIndex = lastIndex-1
            }
        }
        currentLyricsUpdaterTask = Task {
            do {
                try await lyricUpdater()
            } catch {
                print("lyrics were canceled \(error)")
            }
        }
        Task {
            try await currentLyricsUpdaterTask?.value
        }
        
    }
    
    func stopLyricUpdater() {
        print("stop called")
        currentLyricsUpdaterTask?.cancel()
    }
    
    func saveCoreData() {
        let context = coreDataContainer.viewContext
        if context.hasChanges {
            do {
                try context.save()
                print("Saved CoreData!")
            } catch {
                print("core data error \(error)")
                // Show some error here
            }
        } else {
            print("BAD COREDATA CALL!!")
        }
    }
    
    func fetch(for trackID: String, _ trackName: String, checkCoreDataFirst: Bool = true) async -> [LyricLine]? {
        if isFirstFetch {
            isFirstFetch = false
        }
        print("Fetch Called for trackID \(trackID), trackName \(trackName), checkCoreDataFirst: \(checkCoreDataFirst)")
        currentFetchTask?.cancel()
        // i don't set isFetching to true here to prevent "flashes" for CoreData fetches
        defer {
            isFetching = false
        }
        currentFetchTask = Task { try await self.fetchLyrics(for: trackID, trackName, checkCoreDataFirst: checkCoreDataFirst) }
        do {
            return try await currentFetchTask?.value
        } catch {
            print("error \(error)")
            return nil
        }
    }

    #if os(macOS)
    func intToRGB(_ value: Int32) -> Color {//(red: Int, green: Int, blue: Int) {
        // Convert negative numbers to an unsigned 32-bit representation
        let unsignedValue = UInt32(bitPattern: value)
        
        // Extract RGB components
        let red = Double((unsignedValue >> 16) & 0xFF)
        let green = Double((unsignedValue >> 8) & 0xFF)
        let blue = Double(unsignedValue & 0xFF)
        return Color(red: red/255, green: green/255, blue: blue/255) //(red, green, blue)
    }
    
    func setBackgroundColor() {
        guard let currentlyPlaying else {
            return
        }
        let fetchRequest: NSFetchRequest<IDToColor> = IDToColor.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", currentlyPlaying) // Replace trackID with the desired value

        do {
            let results = try coreDataContainer.viewContext.fetch(fetchRequest)
            if let idToColor = results.first {
                self.currentBackground = intToRGB(idToColor.songColor)
            } else {
                self.currentBackground = nil
            }
        } catch {
            print("Error fetching SongObject:", error)
        }
    }
    
    #endif
    
    func fetchLyrics(for trackID: String, _ trackName: String, checkCoreDataFirst: Bool) async throws -> [LyricLine] {
        let initiatingTrackID = trackID
        
        if checkCoreDataFirst, let lyrics = fetchFromCoreData(for: trackID) {
            print("ViewModel FetchLyrics: got lyrics from core data :D \(trackID) \(trackName)")
            try Task.checkCancellation()
            // verify non-stale trackID
            if initiatingTrackID != self.currentlyPlaying {
                print("FetchLyrics: CoreData result stale (initiated: \(initiatingTrackID), current: \(self.currentlyPlaying ?? "nil")). Throwing.")
                throw FetchError.staleTrack
            }
            return lyrics
        } else {
            print("ViewModel FetchLyrics: no lyrics from core data, going to download from internet \(trackID) \(trackName)")
            print("ViewModel FetchLyrics: isFetching set to true")
            isFetching = true
            
            var networkLyrics: NetworkFetchReturn = await fetchAllNetworkLyrics()
            
            // verify non-stale trackID
            if initiatingTrackID != self.currentlyPlaying {
                print("FetchLyrics: Network result stale (initiated: \(initiatingTrackID), current: \(self.currentlyPlaying ?? "nil")). Throwing.")
                throw FetchError.staleTrack
            }
            
            guard let duration = appleMusicPlayer.duration else {
                print("FetchLyrics: Couldn't access current player duration. Giving up on netwokr fetch")
                return []
            }
            networkLyrics = networkLyrics.processed(withSongName: trackName, duration: duration)
            
            // verify non-stale trackID
            if initiatingTrackID == self.currentlyPlaying {
                callColorDataServiceOnLyricColorOrArtwork()
            } else {
                print("FetchLyrics: Skipping color save due to stale track (initiated: \(initiatingTrackID), current: \(self.currentlyPlaying ?? "nil")).")
                throw FetchError.staleTrack
            }
            return networkLyrics.lyrics
        }
    }
    
    func deleteSongLocalePairing(trackID: String) {
        do {
            let fetchRequest: NSFetchRequest<SongToLocale> = SongToLocale.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", trackID)
            guard let object = try coreDataContainer.viewContext.fetch(fetchRequest).first else { return print("Translation: No songToLocale object could be deleted, doesn't exist for trackID \(trackID)") }
            coreDataContainer.viewContext.delete(object)
            try coreDataContainer.viewContext.save()
        } catch {
            print("Error deleting data: \(error)")
        }
    }

    func deleteLyric(trackID: String) {
        do {
            let fetchRequest: NSFetchRequest<SongObject> = SongObject.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", trackID)
            let object = try coreDataContainer.viewContext.fetch(fetchRequest).first
            object?.lyricsTimestamps.removeAll()
            object?.lyricsWords.removeAll()
            try coreDataContainer.viewContext.save()
            currentlyPlayingLyricsIndex = nil
            currentlyPlayingLyrics = []
            translatedLyric = []
            romanizedLyrics = []
            chineseConversionLyrics = []
            lyricsIsEmptyPostLoad = true
        } catch {
            print("Error deleting data: \(error)")
        }
    }
    
    func fetchFromCoreData(for trackID: String) -> [LyricLine]? {
        let fetchRequest: NSFetchRequest<SongObject> = SongObject.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", trackID) // Replace trackID with the desired value

        do {
            let results = try coreDataContainer.viewContext.fetch(fetchRequest)
            if let songObject = results.first {
                // Found the SongObject with the matching trackID
                let lyricsArray = zip(songObject.lyricsTimestamps, songObject.lyricsWords).map { LyricLine(startTime: $0, words: $1) }
                print("Found SongObject with ID:", songObject.id)
                return lyricsArray
            } else {
                // No SongObject found with the given trackID
                print("No SongObject found with the provided trackID. \(trackID)")
            }
        } catch {
            print("Error fetching SongObject:", error)
        }
        return nil
    }
    
    #if os(macOS)
    /// Drops the translation and re-derives the romanization from what is left, since the two
    /// are no longer independent: romanized text is a transform of the line on display.
    private func clearTranslation() {
        guard translationExists else { return }
        translatedLyric = []
        romanizeDidChange()
    }

    /// Translates the current lyrics, preferring the local Hy-MT2 model and falling back to
    /// Apple's translator whenever it is unavailable or returns an incomplete result.
    func startTranslation() {
        // Every path out of this function has to leave isFetchingTranslation false unless
        // something is actually still running, otherwise the UI stays stuck on "translating"
        // until the next song happens to translate successfully.
        localTranslationTask?.cancel()
        guard userDefaultStorage.translate else {
            clearTranslation()
            translationAlreadyInTargetLanguage = false
            isFetchingTranslation = false
            return
        }
        let lines = currentlyPlayingLyrics
        guard !lines.isEmpty else {
            clearTranslation()
            translationAlreadyInTargetLanguage = false
            isFetchingTranslation = false
            return
        }
        let sourceLanguage = translationSourceLanguage ?? detectedLyricsLanguage(in: lines)
        // Both sides unwrapped explicitly. Comparing the optionals directly would make a
        // failed detection (nil) equal to a target with no language code (also nil), and skip
        // translation on the strength of knowing nothing about either.
        if let sourceCode = sourceLanguage?.languageCode?.identifier,
           let targetCode = userLocaleLanguage.languageCode?.identifier,
           sourceCode == targetCode {
            clearTranslation()
            translationAlreadyInTargetLanguage = true
            isFetchingTranslation = false
            print("Translation: Lyrics are already in \(userLocaleLanguage.languageCode?.identifier ?? userLocaleLanguage.minimalIdentifier); skipping translation")
            return
        }
        let requestedSong = currentlyPlaying
        translationAlreadyInTargetLanguage = false
        isFetchingTranslation = true
        localTranslationTask = Task { [weak self] in
            guard let self else { return }
            let local = await LocalTranslationService.translate(lines, to: userLocaleLanguage)
            guard !Task.isCancelled else { return }
            // The track may have changed while the request was in flight; a late result
            // must never be pinned onto a different song's lyrics.
            guard currentlyPlaying == requestedSong else { return }
            if let local, local.count == lines.count {
                translatedLyric = restoringChants(matchingChineseScript(local, for: userLocaleLanguage))
                romanizeDidChange()
                isFetchingTranslation = false
            } else if !reloadTranslationConfigIfTranslating() {
                // Normally Apple's translator takes over here, driving itself through
                // translationSessionConfig and the .translationTask modifier, and clears
                // the flag when it finishes. It declines when translation was switched off
                // while this request was in flight -- then nothing follows, so clear it here.
                isFetchingTranslation = false
            }
        }
    }

    /// Detects a source language only when several lyric lines agree on a true majority.
    private func detectedLyricsLanguage(in lines: [LyricLine]) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        var languageCounts: [NLLanguage: Int] = [:]
        var recognizedLineCount = 0

        for line in lines {
            recognizer.reset()
            recognizer.processString(line.words)
            guard let language = recognizer.dominantLanguage else { continue }
            languageCounts[language, default: 0] += 1
            recognizedLineCount += 1
        }

        // The only caller uses this to decide whether translating can be skipped, and both ways
        // of being wrong are silent: skip a mixed-language song and half of it stays
        // untranslated forever, or translate a song already in the target language and every
        // line comes back needlessly rewritten.
        //
        // What separates the two is not how large the winner is -- it is how large the
        // *runner-up* is. Per-line recognition misfires constantly on short lines, but the
        // misfires scatter across languages, while a genuine second language concentrates.
        // Measured over real songs, the runner-up in single-language lyrics came out at 0%,
        // 6.0%, 6.7%, 10.3%, 10.3% and 10.9%; in Korean/English songs it was 42.3% and 40.5%.
        // That is open ground to draw a line through, unlike the winner's own share, where a
        // wholly English song scored 76.4% -- credit lines such as "Lyrics by:" drag it down --
        // against a genuinely mixed song's 57.7%, too close together to separate.
        guard recognizedLineCount >= 8,
              let majority = languageCounts.max(by: { $0.value < $1.value }),
              Double(majority.value) >= 0.5 * Double(recognizedLineCount) else {
            return nil
        }
        let runnerUp = languageCounts.filter { $0.key != majority.key }.values.max() ?? 0
        guard Double(runnerUp) < 0.20 * Double(recognizedLineCount) else { return nil }
        return Locale.Language(identifier: majority.key.rawValue)
    }

    /// Puts the original words back for lines that are chants rather than sentences.
    ///
    /// A translator handed one short line has no context to work with and answers with the
    /// dictionary sense, which is wrong for a hook: APT.'s "아파트, 아파트" came back as
    /// "Apartment, apartment", the literal reading of a word that is functioning as the song's
    /// title and its chant. Interjections go the same way.
    ///
    /// The test is repetition, not brevity, and it takes *two* repeats rather than one. Brevity
    /// alone swept up ordinary short lines like "광야로 걸어가"; a single repeat still swept up
    /// "중심을 잃고 목소리도 잃고" and "To Kosmo, yeah, yeah". Requiring at most three distinct
    /// words and at least two repetitions among them separates the chants -- "아파트, 아파트,
    /// uh, uh-huh, uh-huh", "La-la-la-la-la", "제껴라, 제껴라, 제껴라" -- from lines that are
    /// saying something. Checked line by line against six songs, including this app's own
    /// stored copy of APT., whose provider packs the hook and the interjection onto one line.
    private func lineIsAChant(_ words: String) -> Bool {
        let tokens = words.lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
        guard tokens.count >= 2 else { return false }
        let distinct = Set(tokens)
        return distinct.count <= 3 && tokens.count - distinct.count >= 2
    }

    /// Applied to whichever translator produced the lines, so both paths agree.
    private func restoringChants(_ translated: [String]) -> [String] {
        guard translated.count == currentlyPlayingLyrics.count else { return translated }
        return zip(translated, currentlyPlayingLyrics).map { line, original in
            lineIsAChant(original.words) ? original.words : line
        }
    }

    /// Hy-MT2 writes Simplified Chinese whatever variant was asked for -- its template only
    /// understands "Chinese". When the target locale asks for Traditional, run the result
    /// through the converters RomanizerService already keeps loaded, picking the regional
    /// standard the locale implies. Any other target language passes straight through.
    private func matchingChineseScript(_ lines: [String], for language: Locale.Language) -> [String] {
        guard language.languageCode?.identifier == "zh",
              language.script?.identifier == "Hant" else { return lines }
        let region = language.region?.identifier
        return lines.map { line in
            let lyric = LyricLine(startTime: 0, words: line)
            let converted: String?
            switch region {
                case "HK", "MO":
                    converted = RomanizerService.generateHongKongTransliteration(lyric)
                case "TW":
                    converted = RomanizerService.generateTaiwanTransliteration(lyric)
                default:
                    converted = RomanizerService.generateTraditionalNeutralTransliteration(lyric)
            }
            // Falling back to the untouched line keeps Simplified text rather than a hole.
            return converted ?? line
        }
    }

    func reloadTranslationConfigIfTranslating() -> Bool {
        if userDefaultStorage.translate {
            if translationSessionConfig == TranslationSession.Configuration(source: translationSourceLanguage, target: userLocaleLanguage) {
                translationSessionConfig?.invalidate()
            } else {
                translationSessionConfig = TranslationSession.Configuration(source: translationSourceLanguage, target: userLocaleLanguage)
            }
            return true
        } else {
            return false
        }
    }
    #endif
    
    func fetchTranslationSourceLanguage() {
        guard let currentlyPlaying else {
            print("Translation: ignoring translationSourceLang fetch due to nil currentlyPlaying")
            return
        }
        let fetchRequest: NSFetchRequest<SongToLocale> = SongToLocale.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", currentlyPlaying) // Replace trackID with the desired value

        do {
            let results = try coreDataContainer.viewContext.fetch(fetchRequest)
            if let songToLocale = results.first?.locale {
                self.translationSourceLanguage = Locale.Language(identifier: songToLocale)
            } else {
                self.translationSourceLanguage = nil
            }
        } catch {
            print("Error fetching translationSourceLanguage:", error)
        }
    }
    
    #if os(macOS)
    func setNewLyricsColorTranslationRomanizationAndStartUpdater(with newLyrics: [LyricLine]) {
        currentlyPlayingLyrics = newLyrics
        setBackgroundColor()
        fetchTranslationSourceLanguage()
        startTranslation()
//        romanizeDidChange()
        translationTargetLanguageDidChange()
        // we romanize afterwards, in-case the chinese conversion array was populated
        romanizeDidChange()
        lyricsIsEmptyPostLoad = currentlyPlayingLyrics.isEmpty
        if isPlaying, !currentlyPlayingLyrics.isEmpty, showLyrics, userDefaultStorage.hasOnboarded {
            startLyricUpdater()
        }
    }
    
    @MainActor
    func uploadLocalLRCFile() async throws {
        guard let currentlyPlaying = currentlyPlaying, let currentlyPlayingName = currentlyPlayingName else {
            throw CancellationError()
        }
        let duration = self.duration
        let localLyrics = try await localFileUploadProvider.localFetch(for: currentlyPlaying, currentlyPlayingName)
        let cleanLyrics = NetworkFetchReturn(lyrics: localLyrics).processed(withSongName: currentlyPlayingName, duration: duration).lyrics
        if self.currentlyPlaying == currentlyPlaying {
            setNewLyricsColorTranslationRomanizationAndStartUpdater(with: cleanLyrics)
        }
        
        // thats how i save to coredata
        let _ = SongObject(from: cleanLyrics, with: coreDataContainer.viewContext, trackID: currentlyPlaying, trackName: currentlyPlayingName)
        saveCoreData()
    }
    #endif
    
    func stepsToTakeAfterSettingsLyrics() async {
        
    }
    
    func didOnboard() {
        guard isPlayerRunning else {
            isPlaying = false
            currentlyPlaying = nil
            currentlyPlayingName = nil
            currentlyPlayingArtist = nil
            #if os(macOS)
            currentlyPlayingAppleMusicPersistentID = nil
            #endif
            return
        }
        print("Application just started (finished onboarding). lets check whats playing")
        if appleMusicPlayer.isPlaying {
            isPlaying = true
        }
        setCurrentProperties()
        startLyricUpdater()
    }
}

#if os(macOS)
// Apple Music Code
extension ViewModel {
    // Similar structure to my other Async functions. Only 1 appleMusic) can run at any given moment
    func appleMusicStarter() async {
        print("apple music test called again, cancelling previous")
        currentAppleMusicFetchTask?.cancel()
        let newFetchTask = Task {
            try await self.appleMusicFetch()
        }
        currentAppleMusicFetchTask = newFetchTask
        do {
            return try await newFetchTask.value
        } catch {
            print("error \(error)")
            return
        }
    }
    
    /// Establishes which cache key the playing Apple Music track uses.
    ///
    /// This used to search Spotify for an "equivalent" song and adopt whatever came back --
    /// its ID as the key, and its name, artist and album written over Apple Music's own. The
    /// search took the single top hit with no similarity check, so a miss renamed the track
    /// outright: "Bread and Roses" by the New York City Labor Chorus came through as
    /// "Hallelujah, I'm A Bum!" by Utah Phillips, and that wrong name was then what LRCLIB and
    /// NetEase were asked for, poisoning all three providers from one bad guess. The result
    /// was cached under the wrong ID and a persistentID -> Spotify ID table replayed it on
    /// every later play. Apple Music's own persistent ID needs none of that.
    ///
    /// The `appleMusic:` prefix keeps the two ID spaces apart. A bare 22-character string is
    /// read elsewhere as "this is a Spotify track", which is a shape an unprefixed identifier
    /// could stumble into.
    func appleMusicFetch() async throws {
        isFetching = true
        print("Apple Music Fetch: isFetching set to true")

        if let currentlyPlayingAppleMusicPersistentID, !currentlyPlayingAppleMusicPersistentID.isEmpty {
            try Task.checkCancellation()
            currentlyPlaying = "appleMusic:\(currentlyPlayingAppleMusicPersistentID)"
        } else if let alternativeID = appleMusicPlayer.alternativeID, !alternativeID.isEmpty {
            // Artist + title, for the occasional track that reports no persistent ID.
            try Task.checkCancellation()
            currentlyPlaying = "appleMusic:\(alternativeID)"
        } else {
            lyricsIsEmptyPostLoad = true
        }
    }
}
#endif
