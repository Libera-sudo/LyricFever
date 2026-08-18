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
    var headerView: some View {
        HStack(spacing: 12) {
            profilePicViewHeaderView
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
                }
                lyricControls
            }
        }
        // even out vertical padding with divider as compared to Menubar button
        .padding(.bottom, 2)
    }
    
    /// Now that the toggle doubles as the reload, it has to stay clickable whenever the app is
    /// set up. A song with no lyrics used to make it `.disabled`, which under the new behavior
    /// would strand the user exactly where they most want to retry -- `.missing` draws the same
    /// inactive fill without taking the click away.
    var displayLyrics: ButtonState {
        if !viewmodel.userDefaultStorage.hasOnboarded {
            return .disabled
        } else if !viewmodel.showLyrics {
            return .clickable
        } else if viewmodel.lyricsIsEmptyPostLoad {
            return .missing
        } else {
            return .enabled
        }
    }
    
    
    @ViewBuilder
    var spotifyConnectDelayPicker: some View {
        Text("TODO")
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
    
    @ViewBuilder
    var lyricControls: some View {
        HStack {
            SmallMenubarButton(buttonText: "", imageText: "music.note.list", buttonState: displayLyrics) {
                viewmodel.showLyrics.toggle()
            }
            SmallMenubarButton(buttonText: "", imageText: "magnifyingglass", buttonState: searchState) {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "search")
            }
            SmallMenubarButton(buttonText: "", imageText: "translate", buttonState: translationState) {
                page = .translationSettings
            }
            .disabled(translationState == .disabled)
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
    
    var truncationBinding: Binding<Double> {
        Binding(
            get: { Double(viewmodel.userDefaultStorage.truncationLength) },
            set: { viewmodel.userDefaultStorage.truncationLength = Int(round($0)) }
        )
    }

    /// Menubar text length, one character per step.
    ///
    /// The step is what the drag snaps to; the tick marks are a separate thing. Asking for
    /// `step: 1` alone would draw all thirty-one of them and turn the track into a dotted
    /// line, so on macOS 26 the `tick:` closure keeps the fine step and hands back a mark
    /// only on multiples of ten. Older systems have no such split and fall back to a
    /// continuous track -- the binding rounds, so the stored value is an Int either way.
    ///
    /// It claims the row's slack rather than a fixed width: the `...` menu has no set width
    /// on macOS 26+, so a fixed slider plus spacers could push Quit off the row, and the
    /// longest possible track is what makes a one-character step draggable at all.
    @ViewBuilder
    var truncationSlider: some View {
        Group {
            if #available(macOS 26.0, *) {
                Slider(
                    value: truncationBinding,
                    in: 30...60,
                    step: 1,
                    label: { Text("Menubar Size") },
                    tick: { value in
                        value.truncatingRemainder(dividingBy: 10) == 0 ? SliderTick(value) : nil
                    }
                )
            } else {
                Slider(value: truncationBinding, in: 30...60) {
                    Text("Menubar Size")
                }
            }
        }
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .tint(.secondary)
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
            }
            if viewmodel.airplayDelay {
                Image(systemName: "airplayaudio")
                    .opacity(0.8)
            }
            if viewmodel.spotifyConnectDelay {
                Image(systemName: "tortoise")
                    .opacity(0.8)
            }
            truncationSlider
            Text("\(viewmodel.userDefaultStorage.truncationLength)")
                .font(.caption)
                .monospacedDigit()
                .frame(width: 18)
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.top, 8)
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
            if viewmodel.spotifyConnectDelay {
                Divider()
                spotifyDelaySlider
                    .environment(\.colorScheme, .dark)
            }
            Divider()
            systemControlView
        }
        .frame(width: 300)
    }

    func pageHeader(_ title: String, back: Page) -> some View {
        HStack(spacing: 6) {
            Button {
                page = back
            } label: {
                Image(systemName: "chevron.left")
                    .bold()
                    .padding(.vertical, 4)
                    .padding(.trailing, 4)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
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
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark").bold()
                }
            }
            // The row has to claim the full width and declare its shape, otherwise only the
            // glyphs themselves are clickable and most of the row is dead space. .plain keeps
            // the label's frame as the hit area; .borderless shrinks it to the content.
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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
        .frame(width: 300)
    }

    @ViewBuilder
    /// The scrollable language list.
    ///
    /// Uses List rather than ScrollView + VStack: a probe build showed the same Button firing
    /// reliably outside a ScrollView and never inside one, so the ScrollView was swallowing the
    /// clicks. List is backed by AppKit's own scrolling table, which routes them properly.
    func languageChoicePage(_ choice: LanguageChoice) -> some View {
        // Read the current value once instead of per row.
        let currentTarget = viewmodel.translationTargetLanguage
        let currentSource = viewmodel.translationSourceLanguage

        return VStack(alignment: .leading, spacing: 6) {
            pageHeader(choice.title, back: .translationSettings)
            Divider()
            List {
                switch choice {
                    case .sourceForThisSong:
                        choiceRow("Auto", selected: currentSource == nil) {
                            setSourceLanguage(nil)
                        }
                        ForEach(supportedLanguages, id: \.maximalIdentifier) { language in
                            choiceRow(languageLabel(language),
                                      selected: currentSource?.maximalIdentifier == language.maximalIdentifier) {
                                setSourceLanguage(language)
                            }
                        }
                    case .targetForAllSongs:
                        choiceRow("System (\(viewmodel.systemLocaleString))", selected: currentTarget == nil) {
                            viewmodel.translationTargetLanguage = nil
                        }
                        ForEach(supportedLanguages, id: \.maximalIdentifier) { language in
                            choiceRow(languageLabel(language),
                                      selected: currentTarget?.maximalIdentifier == language.maximalIdentifier) {
                                viewmodel.translationTargetLanguage = language
                            }
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: 280)
        }
        .frame(width: 300)
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
                // The API returns them in no meaningful order. Sort by the name actually
                // shown, using localizedStandardCompare so it matches how the user's language
                // orders things rather than raw code points.
                supportedLanguages = languages.sorted {
                    let a = Locale.current.localizedString(forIdentifier: $0.minimalIdentifier) ?? $0.maximalIdentifier
                    let b = Locale.current.localizedString(forIdentifier: $1.minimalIdentifier) ?? $1.maximalIdentifier
                    return a.localizedStandardCompare(b) == .orderedAscending
                }
            }
        }
    }
}
