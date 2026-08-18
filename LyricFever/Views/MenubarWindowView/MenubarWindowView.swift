//
//  MenubarWindowView.swift
//  Lyric Fever
//
//  Created by Avi Wadhwa on 2025-07-26.
//

import SwiftUI
import LaunchAtLogin
import Translation

struct MenubarWindowView: View {
    @Environment(\.openURL) var openURL
    @Environment(\.openWindow) var openWindow
    @Environment(ViewModel.self) var viewmodel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State var currentHoveredItem = MenubarButtonHighlight.none
    @State var supportedLanguages: [Locale.Language] = []

    /// Which panel page is showing.
    ///
    /// Settings live on pages inside the panel rather than in a Menu or a Picker. Under
    /// `.menuBarExtraStyle(.window)` the panel is an ordinary window that closes as soon as it
    /// loses focus, and any popped-up menu renders outside it -- so moving the mouse onto the
    /// menu dismissed the panel and took the menu with it. Nothing here pops out of the panel.
    enum Page: Equatable {
        case main
        case translationSettings
        case languageChoice(LanguageChoice)
    }

    enum LanguageChoice: Equatable {
        case sourceForThisSong
        case targetForAllSongs

        var title: String {
            switch self {
                case .sourceForThisSong: "Source Language"
                case .targetForAllSongs: "Target Language"
            }
        }
    }

    @State var page: Page = .main

    @ViewBuilder
    var profilePicViewHeaderView: some View {
        ZStack {
            if let artworkImage = viewmodel.artworkImage {
                Image(nsImage: artworkImage)
                    .resizable()
                    .frame(width: 112, height: 112)
                    .clipShape(.rect(cornerRadius: 9))
//                    .animation(.smooth(duration: 0.3), value: viewmodel.newAlbum)
                    .apply {
                        if let shareURL = viewmodel.currentPlayerInstance.shareURL(for: viewmodel.currentlyPlaying) {
                            $0
                                .draggable(shareURL)
                        } else {
                            $0
                        }
                    }
                    .shadow(color: viewmodel.currentBackground ?? .clear, radius: 70)
                    .shadow(color: viewmodel.currentBackground ?? .clear, radius: 70)
            } else {
                Image(systemName: "music.note.list")
                    .resizable()
                    .shadow(radius: 1)
                    .scaleEffect(0.5)
                    .background(.gray)
                    .frame(width: 112, height: 112)
                    .clipShape(.rect(cornerRadius: 9))
            }
            
            ZStack {
                if viewmodel.isFetching {
                    Rectangle()
                        .fill(Color.black.opacity(0.5))
                        .clipShape(.rect(cornerRadius: 9))
                    
                    ProgressView()
                        .environment(\.colorScheme, .dark)
                }
            }
            .animation(.smooth(duration: 2), value: viewmodel.isFetching)
        }
        .frame(width: 112, height: 112)
    }
    
    @ViewBuilder
    var songDetails: some View {
        VStack {
            HStack {
                MarqueeText(viewmodel.currentlyPlayingName ?? "-", startDelay: 1.5, alignment: .leading, leftFade: 2)
                .frame(height: 15)
            }
            HStack {
                MarqueeText(viewmodel.currentlyPlayingArtist ?? "-", startDelay: 1.5, alignment: .leading, leftFade: 2)
                    .font(.caption)
                    .frame(height: 15)
            }
        }
    }
    
    @ViewBuilder
    var songControls: some View {
        HStack {
            SongControlButton(systemImage: "backward.fill") {
                viewmodel.currentPlayerInstance.rewind()
            }
            .onHover { isHovering in
                currentHoveredItem = isHovering ? .rewind : .none
            }
            SongControlButton(systemImage: viewmodel.isPlaying ? "pause.fill" : "play.fill", wiggle: false) {
                viewmodel.currentPlayerInstance.togglePlayback()
            }
//            .controlSize(.large)
            .onHover { isHovering in
                currentHoveredItem = isHovering ? (viewmodel.isPlaying ? .pause : .play) : .none
            }
            .keyboardShortcut(" ", modifiers: [])
            .contentTransition(.symbolEffect(.replace, options: .speed(2)))
            
            SongControlButton(systemImage: "forward.fill") {
                viewmodel.currentPlayerInstance.forward()
            }
            .onHover { isHovering in
                currentHoveredItem = isHovering ? .forward : .none
            }
        }
        .frame(height: 30)
//        .buttonStyle(.accessoryBar)
    }
    
    @ViewBuilder
    var headerView: some View {
        HStack(spacing: 12) {
            profilePicViewHeaderView
                .onHover { isHovering in
                    currentHoveredItem = isHovering ? viewmodel.currentPlayerInstance.currentHoverItem : .none
                }
                .onTapGesture {
                    viewmodel.currentPlayerInstance.activate()
                    dismiss()
                }
            VStack {
                HStack {
                    songDetails
//                    LikeButton()
//                        .task(id: viewmodel.currentlyPlaying) {
//                            guard let currentlyPlaying = viewmodel.currentlyPlaying else {
//                                print("Ignoring nil currentlyPlaying for heart check")
//                                return
//                            }
//                            print("Task to check if \(viewmodel.currentlyPlaying) is hearted")
//                            do {
//                                viewmodel.isHearted = try await viewmodel.spotifyLyricProvider.checkHeartedStatusFor(trackID: currentlyPlaying)
//                            } catch {
//                                print(error)
//                            }
//                        }
//                        .onHover { isHovering in
//                            currentHoveredItem = isHovering ? (viewmodel.isHearted ? .unheart : .heart) : .none
//                        }
                }
                songControls
                
                ProgressView(value: displayLyrics == .enabled ? viewmodel.currentTime.currentTime : 0, total: Double(viewmodel.duration))
                    .progressViewStyle(ColoredThinProgressViewStyle(color: .secondary, thickness: 4))
                    .frame(height: 4)
                    .padding(.horizontal, 4)
                    .environment(\.colorScheme, .dark)
                
                HStack {
                    Text(displayLyrics == .enabled ? viewmodel.formattedCurrentTime : "--:--")
                        .font(.caption2)
                    Spacer()
                    Text(viewmodel.formattedDuration)
                        .font(.caption2)
                }
                .padding(.horizontal, 4)
            }
        }
        // even out vertical padding with divider as compared to Menubar button
        .padding(.bottom, 2)
    }
    
    var displayLyrics: ButtonState {
        if !viewmodel.userDefaultStorage.hasOnboarded {
            return .disabled
        } else if viewmodel.lyricsIsEmptyPostLoad {
            return .disabled
        } else if viewmodel.showLyrics {
            return .enabled
        } else {
            return .clickable
        }
    }
    
    
    @ViewBuilder
    var lyricModifierView: some View {
        HStack {
            MenubarButton(buttonText: "", imageText: "music.note.list", buttonState: displayLyrics) {
                viewmodel.showLyrics.toggle()
            }
            .onHover { isHovering in
                if isHovering {
                    switch displayLyrics {
                        case .enabled:
                            currentHoveredItem = .disableLyrics
                        case .disabled:
                            currentHoveredItem = .unavailableLyrics
                        case .clickable:
                            currentHoveredItem = .enableLyrics
                        default:
                            currentHoveredItem = .none
                    }
                } else {
                    currentHoveredItem = .none
                }
            }
        }
    }

    
    @ViewBuilder
    var spotifyConnectDelayPicker: some View {
        Text("TODO")
    }
    
    
    var refreshState: ButtonState {
        guard viewmodel.userDefaultStorage.hasOnboarded else {
            return .disabled
        }
        if viewmodel.isFetching {
            return .loading
        } else {
            return .clickable
        }
    }
    
    var translationState: ButtonState {
        guard viewmodel.userDefaultStorage.hasOnboarded else {
            return .disabled
        }
        guard !viewmodel.lyricsIsEmptyPostLoad else {
            return .disabled
        }
        if viewmodel.userDefaultStorage.translate {
            if viewmodel.isFetchingTranslation {
                return .loading
            } else if viewmodel.translationExists {
                return .enabled
            } else {
                return .missing
            }
        } else if viewmodel.userDefaultStorage.romanize {
            return .enabled
        } else {
            return .clickable
        }
    }
    
    var searchState: ButtonState {
        guard viewmodel.userDefaultStorage.hasOnboarded else {
            return .disabled
        }
        return .clickable
    }
    
    var deleteOrUploadState: ButtonState {
        guard viewmodel.userDefaultStorage.hasOnboarded else {
            return .disabled
        }
        // attach a separate disabled modifier to prevent slash flashing
//        if viewmodel.isFetching {
//            return .disabled
//        }
        return .clickable
    }
    
    @ViewBuilder
    var viewSelector: some View {
        @Bindable var viewmodel = viewmodel
        HStack {
            SmallMenubarButton(buttonText: "", imageText: "arrow.clockwise", buttonState: refreshState) {
                Task {
                    do {
                        try await viewmodel.refreshLyrics()
                    } catch {
                        print("Couldn't refresh lyrics: error \(String(describing: error))")
                    }
                }
            }
            .disabled(refreshState == .loading)
            .onHover { isHovering in
                if isHovering {
                    switch refreshState {
                        case .loading:
                            currentHoveredItem = .refreshingLyrics
                        case .disabled:
                            currentHoveredItem = .none
                        case .clickable:
                            currentHoveredItem = .refreshLyrics
                        default:
                            currentHoveredItem = .none
                    }
                } else {
                    currentHoveredItem = .none
                }
            }
            SmallMenubarButton(buttonText: "", imageText: "magnifyingglass", buttonState: searchState) {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "search")
            }
            .onHover { isHovering in
                if isHovering {
                    currentHoveredItem = .search
                } else {
                    currentHoveredItem = .none
                }
            }
            SmallMenubarButton(buttonText: "", imageText: "translate", buttonState: translationState) {
                page = .translationSettings
            }
            .disabled(translationState == .disabled)
            .onHover { isHovering in
                if isHovering {
                    switch translationState {
                        case .enabled:
                            currentHoveredItem = .translateEnabled
                        case .disabled:
                            currentHoveredItem = .translationUnavailable
                        case .loading:
                            currentHoveredItem = .translationLoading
                        case .clickable:
                            currentHoveredItem = .translate
                        case .missing:
                            currentHoveredItem = .translationFail
                    }
                } else {
                    currentHoveredItem = .none
                }
            }
            SmallMenubarButton(buttonText: "", imageText: viewmodel.lyricsIsEmptyPostLoad ? "arrow.up.document" : "trash", buttonState: deleteOrUploadState) {
                if viewmodel.lyricsIsEmptyPostLoad {
                    Task {
                        do {
                            try await viewmodel.uploadLocalLRCFile()
                        } catch {
                            print("MenuBarWindowView: Upload LRC: Error occurred: \(error)")
                        }
                    }
                } else {
                    guard let currentlyPlaying = viewmodel.currentlyPlaying else { return }
                    viewmodel.deleteLyric(trackID: currentlyPlaying)
                }
            }
            .disabled(viewmodel.isFetching)
            .onHover { isHovering in
                if isHovering {
                    if viewmodel.lyricsIsEmptyPostLoad {
                        currentHoveredItem = .upload
                    } else {
                        currentHoveredItem = .delete
                    }
                } else {
                    currentHoveredItem = .none
                }
            }
            .contentTransition(.symbolEffect(.replace))
        }
    }
    
    @ViewBuilder
    var streamingDelayView: some View {
        @Bindable var viewmodel = viewmodel
        if viewmodel.currentPlayer == .spotify {
             Toggle("Spotify Connect Audio Delay", isOn: $viewmodel.spotifyConnectDelay)
                 .disabled(!viewmodel.userDefaultStorage.hasOnboarded)
            if viewmodel.spotifyConnectDelay {
                 Text("Offset is \(viewmodel.userDefaultStorage.spotifyConnectDelayCount) ms")
//                 if viewmodel.userDefaultStorage.spotifyConnectDelayCount != 3000 {
//                     Button("Increase Offset to \(viewmodel.userDefaultStorage.spotifyConnectDelayCount+100)") {
//                         viewmodel.userDefaultStorage.spotifyConnectDelayCount = viewmodel.userDefaultStorage.spotifyConnectDelayCount + 100
//                     }
//                 }
//                if viewmodel.userDefaultStorage.spotifyConnectDelayCount != 300 {
//                     Button("Decrease Offset to \(viewmodel.userDefaultStorage.spotifyConnectDelayCount-100)") {
//                         viewmodel.userDefaultStorage.spotifyConnectDelayCount = viewmodel.userDefaultStorage.spotifyConnectDelayCount - 100
//                     }
//                 }
             }
            Toggle("AirPlay Audio Delay", isOn: $viewmodel.airplayDelay)
                .disabled(!viewmodel.userDefaultStorage.hasOnboarded)
            Divider()
        }
    }
    
    @ViewBuilder
    var otherOptions: some View {
        @Bindable var viewmodel = viewmodel
        Toggle("Show Song Details in Menubar", isOn: $viewmodel.userDefaultStorage.showSongDetailsInMenubar)
        Divider()
        streamingDelayView
        Button("Settings") {
            openWindow(id: "onboarding")
            NSApplication.shared.activate(ignoringOtherApps: true)
            // send notification to check auth
            NotificationCenter.default.post(name: Notification.Name("didClickSettings"), object: nil)
        }.keyboardShortcut("s")
        LaunchAtLogin.Toggle(String(localized: "Launch at Login"))
        .disabled(!viewmodel.userDefaultStorage.hasOnboarded)
        .keyboardShortcut("l")
        Button("Check for Updates…") {
            viewmodel.updaterService.updaterController.checkForUpdates(nil)
        }
        Divider()
            .keyboardShortcut("u")
        Button("Buy Me A Beer (Thank You)!") {
            openURL(URL(string: "https://buymeacoffee.com/aviwadhwalyricfever")!)
        }
    }
    
    @ViewBuilder
    var systemControlView: some View {
        HStack {
            if #available(macOS 26.0, *) {
                Menu {
                    otherOptions
//                        .foregroundStyle(viewmodel.currentBackground ?? .primary)
                } label: {

                        Text("...")
                }
                .environment(\.colorScheme, .dark)
                .menuIndicator(.hidden)
                .onHover { isHovering in
                    if isHovering {
                        currentHoveredItem = .moreOptions
                    } else {
                        currentHoveredItem = .none
                    }
                }
            } else {
                Menu {
                    otherOptions
                        .foregroundStyle(viewmodel.currentBackground ?? .primary)
                } label: {

                        Text("...")
                }
                .frame(width: 30)
                .environment(\.colorScheme, .dark)
                .menuIndicator(.hidden)
                .onHover { isHovering in
                    if isHovering {
                        currentHoveredItem = .moreOptions
                    } else {
                        currentHoveredItem = .none
                    }
                }
            }
            if viewmodel.airplayDelay {
                Image(systemName: "airplayaudio")
                    .opacity(0.8)
            }
            if viewmodel.spotifyConnectDelay {
                Image(systemName: "tortoise")
                    .opacity(0.8)
            }
            Spacer()
            Text(currentHoveredItem.description)
                .minimumScaleFactor(0.8)
                .textCase(.uppercase)
                .font(.system(size: 12, weight: .light, design: .monospaced))
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .onHover { isHovering in
                if isHovering {
                    currentHoveredItem = .quit
                } else {
                    currentHoveredItem = .none
                }
            }
        }
        .padding(.top, 8)
    }
    
    var menubarSizeSliderBinding: Binding<Double> {
        Binding (
            get: { Double(viewmodel.userDefaultStorage.truncationLength) },
            set: { newValue in
                let steps = [30, 40, 50, 60]
                let closest = steps.min(by: { abs(Double($0) - newValue) < abs(Double($1) - newValue) }) ?? 40
                viewmodel.userDefaultStorage.truncationLength = closest
            }
        )
    }
    
    var spotifyDelayBinding: Binding<Double> {
        Binding(
            get: { Double(viewmodel.userDefaultStorage.spotifyConnectDelayCount) },
            set: { newValue in
                let snapped = (round(newValue / 100) * 100)
                viewmodel.userDefaultStorage.spotifyConnectDelayCount = Int(snapped)
            }
        )
    }
    
    @ViewBuilder
    var menubarSizeSlider: some View {
        @Bindable var viewmodel = viewmodel
        HStack {
            Image(systemName: "textformat.size")
                .frame(width: 30)
            Slider(value: menubarSizeSliderBinding, in: 30...60, step: 10, label: {
                Text("Menubar Size")
            })
            .labelsHidden()
            .frame(width: 160)
            Text("\(viewmodel.userDefaultStorage.truncationLength)")
                .frame(width: 23)
        }
        .tint(.secondary)
    }

    @ViewBuilder
    var spotifyDelaySlider: some View {
        @Bindable var viewmodel = viewmodel
        HStack {
            Image(systemName: "tortoise")
                .frame(width: 34, alignment: .trailing)
            Slider(value: spotifyDelayBinding, in: 300...3000, step: 100) {
                Text("Spotify Delay")
            }
            .labelsHidden()
            .frame(width: 160)
            let seconds = Double(viewmodel.userDefaultStorage.spotifyConnectDelayCount) / 1000.0
            Text("\(seconds.formatted(.number.precision(.fractionLength(1))))s")
                .frame(width: 27)
        }
        .tint(.secondary)
    }
    
    var mainPage: some View {
        VStack {
            headerView
            Divider()
            lyricModifierView
            Divider()
            viewSelector
            Divider()
            menubarSizeSlider
                .environment(\.colorScheme, .dark)
            if viewmodel.spotifyConnectDelay {
                Divider()
                spotifyDelaySlider
                    .environment(\.colorScheme, .dark)
            }
            Divider()
            systemControlView
        }
    }

    func pageHeader(_ title: String, back: Page) -> some View {
        HStack(spacing: 6) {
            Button {
                page = back
            } label: {
                Image(systemName: "chevron.left").bold()
            }
            .buttonStyle(.borderless)
            Text(title).font(.headline)
            Spacer()
        }
    }

    /// A row that applies a value and shows whether it is the one in effect. Deliberately not a
    /// Picker: a Picker pops its list outside the panel, and the panel closes before the list
    /// can be clicked.
    func choiceRow(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label).lineLimit(1)
                Spacer()
                if selected {
                    Image(systemName: "checkmark").bold()
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
    }

    /// A row that leads to another page, showing the value currently in effect.
    func disclosureRow(_ label: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                Spacer()
                Text(value).foregroundStyle(.secondary).lineLimit(1)
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
    }

    func languageLabel(_ language: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: language.minimalIdentifier) ?? language.maximalIdentifier
    }

    var sourceLanguageLabel: String {
        guard let source = viewmodel.translationSourceLanguage else { return "Auto" }
        return languageLabel(source)
    }

    /// Records the per-song source language override. Mirrors what the old picker binding did:
    /// clearing it deletes the stored pairing, setting it saves one.
    func setSourceLanguage(_ language: Locale.Language?) {
        viewmodel.translationSourceLanguage = language
        guard let trackID = viewmodel.currentlyPlaying else {
            print("Translation: ignoring source language change: nil currentlyPlaying")
            return
        }
        guard let language else {
            print("Translation: source language cleared, deleting existing pair")
            viewmodel.deleteSongLocalePairing(trackID: trackID)
            return
        }
        let localeIdentifier = language.maximalIdentifier
        print("Translation: Source language changed. Saving new pair (\(trackID),\(localeIdentifier)) to coredata")
        let newSongToLocaleMapping = SongToLocale(context: viewmodel.coreDataContainer.viewContext)
        newSongToLocaleMapping.id = trackID
        newSongToLocaleMapping.locale = localeIdentifier
        do {
            try viewmodel.coreDataContainer.viewContext.save()
            print("Translation: Successfully saved locale \(localeIdentifier) for trackID \(trackID)")
        } catch {
            print("Translation: Couldn't save locale mapping to CoreData: \(error)")
        }
    }

    @ViewBuilder
    var translationSettingsPage: some View {
        @Bindable var viewmodel = viewmodel
        VStack(alignment: .leading, spacing: 8) {
            pageHeader("Translation", back: .main)
            Divider()
            Toggle("Translate to \(viewmodel.userLocaleLanguageString)", isOn: $viewmodel.userDefaultStorage.translate)
                .disabled(!viewmodel.userDefaultStorage.hasOnboarded)
            if viewmodel.userDefaultStorage.translate {
                Text(!viewmodel.translatedLyric.isEmpty ? "Translated Lyrics 😃" : "No Translation ☹️")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if viewmodel.translatedLyric.isEmpty {
                    Button("Translation Help") {
                        openURL(URL(string: "https://aviwadhwa.com/TranslationHelp")!)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            disclosureRow("Source (this song)", value: sourceLanguageLabel) {
                page = .languageChoice(.sourceForThisSong)
            }
            disclosureRow("Target (all songs)", value: viewmodel.userLocaleLanguageString) {
                page = .languageChoice(.targetForAllSongs)
            }
            Divider()
            Toggle("Romanize", isOn: $viewmodel.userDefaultStorage.romanize)
            Text("Chinese Conversion")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(ChineseConversion.allCases) { conversion in
                choiceRow(conversion.description,
                          selected: viewmodel.userDefaultStorage.chinesePreference == conversion.rawValue) {
                    viewmodel.userDefaultStorage.chinesePreference = conversion.rawValue
                }
            }
        }
        .frame(width: 260)
    }

    @ViewBuilder
    func languageChoicePage(_ choice: LanguageChoice) -> some View {
        @Bindable var viewmodel = viewmodel
        VStack(alignment: .leading, spacing: 6) {
            pageHeader(choice.title, back: .translationSettings)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    switch choice {
                        case .sourceForThisSong:
                            choiceRow("Auto", selected: viewmodel.translationSourceLanguage == nil) {
                                setSourceLanguage(nil)
                            }
                            ForEach(supportedLanguages, id: \.maximalIdentifier) { language in
                                choiceRow(languageLabel(language),
                                          selected: viewmodel.translationSourceLanguage?.maximalIdentifier == language.maximalIdentifier) {
                                    setSourceLanguage(language)
                                }
                            }
                        case .targetForAllSongs:
                            choiceRow("System (\(viewmodel.systemLocaleString))",
                                      selected: viewmodel.userDefaultStorage.translationTargetLanguage == nil) {
                                viewmodel.userDefaultStorage.translationTargetLanguage = nil
                            }
                            ForEach(supportedLanguages, id: \.maximalIdentifier) { language in
                                choiceRow(languageLabel(language),
                                          selected: viewmodel.userDefaultStorage.translationTargetLanguage == language) {
                                    viewmodel.userDefaultStorage.translationTargetLanguage = language
                                }
                            }
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .frame(width: 260)
    }

    var body: some View {
        Group {
            switch page {
                case .main:
                    mainPage
                case .translationSettings:
                    translationSettingsPage
                case .languageChoice(let choice):
                    languageChoicePage(choice)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(
            viewmodel.currentBackground
                .brightness(colorScheme == .dark ? -0.4 : -0.8)
                .opacity(0.6)
                .animation(.smooth, value: viewmodel.currentBackground)
        )
        .task {
            let languages = await Task.detached {
                await LanguageAvailability().supportedLanguages
            }.value
            await MainActor.run {
                supportedLanguages = languages
            }
        }
    }
}

