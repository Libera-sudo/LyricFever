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
    @State var appleMusicAuthorizationRefresh = false

    /// Which panel page is showing.
    ///
    /// Settings live on pages inside the panel rather than in a Menu or a Picker. Under
    /// `.menuBarExtraStyle(.window)` the panel is an ordinary window that closes as soon as it
    /// loses focus, and any popped-up menu renders outside it -- so moving the mouse onto the
    /// menu dismissed the panel and took the menu with it. Nothing here pops out of the panel.
    enum Page: Equatable {
        case main
        case moreOptions
        case settings
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

    enum NavigationDirection {
        case forward
        case backward
    }

    @State var page: Page = .main
    @State private var navigationDirection: NavigationDirection = .forward

    private var pageTransition: AnyTransition {
        switch navigationDirection {
            case .forward:
                .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
            case .backward:
                .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
        }
    }

    private func navigate(to destination: Page, direction: NavigationDirection = .forward) {
        navigationDirection = direction
        page = destination
    }

    @ViewBuilder
    var profilePicViewHeaderView: some View {
        ZStack {
            if let artworkImage = viewmodel.artworkImage {
                Image(nsImage: artworkImage)
                    .resizable()
                    .frame(width: 112, height: 112)
                    .clipShape(.rect(cornerRadius: 9))
//                    .animation(.smooth(duration: 0.3), value: viewmodel.newAlbum)
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
                    viewmodel.appleMusicPlayer.activate()
                    dismiss()
                }
            VStack {
                songDetails
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
                navigate(to: .translationSettings)
            }
            .disabled(translationState == .disabled)
        }
    }
    
    var truncationBinding: Binding<Double> {
        Binding(
            get: { Double(viewmodel.userDefaultStorage.menubarWidth) },
            set: { viewmodel.userDefaultStorage.menubarWidth = Int(round($0)) }
        )
    }

    /// Menubar text length: drag lands on any single character, marks appear every ten.
    ///
    /// Those two are not the same knob. A `step:` both snaps the drag *and* draws a mark at
    /// every stop, so `step: 1` turned the track into a dotted line of thirty-one marks --
    /// and the `tick:` closure that pairs with it only restyles those marks, returning nil
    /// does not remove one. The separate `ticks:` initialiser takes no step at all: the value
    /// stays continuous and only the marks listed here are drawn. The binding rounds, so what
    /// gets stored is still a whole number of characters.
    ///
    /// It claims the row's slack rather than a fixed width: the `...` menu has no set width
    /// on macOS 26+, so a fixed slider plus spacers could push Quit off the row, and the
    /// longest possible track is what makes single-character precision draggable at all.
    @ViewBuilder
    var truncationSlider: some View {
        MenubarTruncationSlider(value: truncationBinding)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .tint(.secondary)
    }

    @ViewBuilder
    var systemControlView: some View {
        HStack {
            Button {
                navigate(to: .moreOptions)
            } label: {
                Text("...")
            }
            .frame(width: 30)
            .menubarGlassButtonStyle()
            if viewmodel.userDefaultStorage.airplayDelay {
                Image(systemName: "airplayaudio")
                    .opacity(0.8)
            }
            truncationSlider
            Text("\(viewmodel.userDefaultStorage.menubarWidth)")
                .font(.caption)
                .monospacedDigit()
                .frame(width: 26)
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .menubarGlassButtonStyle()
        }
        .padding(.top, 8)
    }
    
    var mainPage: some View {
        VStack {
            headerView
            Divider()
            systemControlView
        }
        .frame(width: 300)
    }

    @ViewBuilder
    var moreOptionsPage: some View {
        @Bindable var viewmodel = viewmodel
        VStack(alignment: .leading, spacing: 8) {
            pageHeader("Options", back: .main)
            Divider()
            Toggle("Show Song Details in Menubar", isOn: $viewmodel.userDefaultStorage.showSongDetailsInMenubar)
                .toggleStyle(.switch)
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("AirPlay Audio Delay", isOn: $viewmodel.userDefaultStorage.airplayDelay)
                .toggleStyle(.switch)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(!viewmodel.userDefaultStorage.hasOnboarded)
            LaunchAtLogin.Toggle(String(localized: "Launch at Login"))
                .toggleStyle(.switch)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(!viewmodel.userDefaultStorage.hasOnboarded)
            disclosureRow("Settings", value: "") {
                navigate(to: .settings)
            }
            Button {
                openURL(URL(string: "https://buymeacoffee.com/aviwadhwalyricfever")!)
            } label: {
                HStack {
                    Text("Buy Me A Beer (Thank You)!")
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 300)
    }

    var appleMusicAuthorizationStatus: String {
        if !viewmodel.appleMusicPlayer.isRunning {
            return "Apple Music isn't running"
        } else if !viewmodel.appleMusicPlayer.isAuthorized {
            return "Waiting for permission"
        } else {
            return "Apple Music is connected"
        }
    }

    @ViewBuilder
    var settingsPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            pageHeader("Settings", back: .moreOptions)
            Divider()
            Text(appleMusicAuthorizationStatus)
                .id(appleMusicAuthorizationRefresh)
            if appleMusicAuthorizationStatus != "Apple Music is connected" {
                Button("Grant Apple Music Access") {
                    _ = viewmodel.appleMusicPlayer.isAuthorized
                    appleMusicAuthorizationRefresh.toggle()
                }
            }
            Button {
                openURL(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
            } label: {
                HStack {
                    Text("Open Automation Settings")
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 300)
    }

    func pageHeader(_ title: String, back: Page) -> some View {
        HStack(spacing: 6) {
            Button {
                navigate(to: back, direction: .backward)
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
                navigate(to: .languageChoice(.sourceForThisSong))
            }
            disclosureRow("Target (all songs)", value: viewmodel.userLocaleLanguageString) {
                navigate(to: .languageChoice(.targetForAllSongs))
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
                        .transition(pageTransition)
                case .moreOptions:
                    moreOptionsPage
                        .transition(pageTransition)
                case .settings:
                    settingsPage
                        .transition(pageTransition)
                case .translationSettings:
                    translationSettingsPage
                        .transition(pageTransition)
                case .languageChoice(let choice):
                    languageChoicePage(choice)
                        .transition(pageTransition)
            }
        }
        .animation(.smooth(duration: 0.3), value: page)
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
