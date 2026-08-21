//
//  MenubarWindowView.swift
//  Lyric Fever
//
//  Created by Avi Wadhwa on 2025-07-26.
//

import SwiftUI
import LaunchAtLogin
import Translation

/// Carries the main page's measured height up to the container that pins the other pages to it.
private struct MainPageHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

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
        case translationTargetLanguage
        case translationSourceLanguage
        case conversion
    }

    @State var page: Page = .main

    /// Every page is sized to the main one. Measured rather than written down: the main page's
    /// own height moves with its content, and a number typed in here would drift away from it
    /// silently. The seed only holds until the panel first draws, which it always does on the
    /// main page.
    @State private var mainPageHeight: CGFloat = 260

    private func navigate(to destination: Page) {
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
        } else if viewmodel.isFetching {
            // The spinner the artwork used to carry, moved onto the thing being fetched.
            return .loading
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
            } else if viewmodel.translationAlreadyInTargetLanguage {
                // Nothing was translated and nothing went wrong: the lyrics were already in the
                // target language. `.missing` would put a warning mark on a working feature.
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

    var translationStatus: String {
        if viewmodel.lyricsIsEmptyPostLoad || viewmodel.isFetching {
            return String(localized: "Nothing to Translate 🎵")
        } else if viewmodel.isFetchingTranslation {
            return String(localized: "Translating Lyrics ⏳")
        } else if viewmodel.translationAlreadyInTargetLanguage {
            return String(localized: "Lyrics Already in \(viewmodel.userLocaleLanguageString) 😊")
        } else if !viewmodel.translatedLyric.isEmpty {
            return String(localized: "Translated Lyrics 😃")
        } else {
            return String(localized: "No Translation ☹️")
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
            SmallMenubarButton(buttonText: "", imageText: "music.note.list", buttonState: displayLyrics,
                               slashed: !viewmodel.showLyrics) {
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
    
    /// True when the menu bar, not the slider, is what limits the lyric.
    var cappedBySpace: Bool {
        viewmodel.menubarLyricWidth < CGFloat(viewmodel.userDefaultStorage.menubarWidth)
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
        MenubarTruncationSlider(value: truncationBinding, ceiling: viewmodel.measuredMenubarWidth)
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
            LyricWidthIcon(gap: 2.2, filled: true)
            truncationSlider
            // The slider sets a cap; what the lyric actually gets is the cap or the measured
            // space, whichever is smaller. When space wins, showing the cap would be a lie about
            // a number the user just dragged, so the effective width is shown instead -- coloured,
            // because the same slot now means something different.
            Text("\(cappedBySpace ? Int(viewmodel.menubarLyricWidth) : viewmodel.userDefaultStorage.menubarWidth)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(cappedBySpace ? Color.orange : Color.primary)
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

    /// A row whose control sits against the trailing edge rather than beside its label.
    ///
    /// `Toggle("…", isOn:)` puts the switch immediately after the text, so a column of rows ends
    /// up with its switches at as many different x positions as there are label lengths. Pushing
    /// them to one edge gives the eye a single line to run down.
    @ViewBuilder
    func optionRow<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: 12)
            control()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var moreOptionsPage: some View {
        @Bindable var viewmodel = viewmodel
        VStack(alignment: .leading, spacing: 8) {
            pageHeader("Options", back: .main)
            Divider()
            optionRow("Show Song Details in Menubar") {
                Toggle("", isOn: $viewmodel.userDefaultStorage.showSongDetailsInMenubar)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            optionRow("AirPlay Audio Delay") {
                Toggle("", isOn: $viewmodel.userDefaultStorage.airplayDelay)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!viewmodel.userDefaultStorage.hasOnboarded)
            }
            optionRow("Launch at Login") {
                LaunchAtLogin.Toggle { EmptyView() }
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!viewmodel.userDefaultStorage.hasOnboarded)
            }
            // Last: it leaves this page rather than changing something on it.
            disclosureRow("Settings", value: "") {
                navigate(to: .settings)
            }
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
            Button {
                openURL(URL(string: "https://buymeacoffee.com/aviwadhwalyricfever")!)
            } label: {
                HStack {
                    Text("Buy the Author a Beer")
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Divider()
            Text(appVersion)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 300)
    }

    /// Read from the bundle, not written out here: the onboarding window still carries a
    /// hand-typed "Version 3.3" that nothing updates when the project's version moves.
    var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "Version \(short ?? "unknown")"
    }

    /// `status` rides the trailing edge of the header row rather than taking a line of its
    /// own below it: the panel is 300pt wide and every vertical point it spends is a point
    /// the page it heads does not get.
    func pageHeader(_ title: String, back: Page, status: String? = nil) -> some View {
        HStack(spacing: 6) {
            Button {
                navigate(to: back)
            } label: {
                Image(systemName: "chevron.left")
                    .bold()
                    .padding(.vertical, 4)
                    .padding(.trailing, 4)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // The title outranks the status: fixedSize on the status made it hold its full
            // width and squeeze the heading until "Translation" broke across two lines.
            Text(title)
                .font(.headline)
                .fixedSize()
                .layoutPriority(1)
            Spacer(minLength: 4)
            if let status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
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

    func languageCode(for language: Locale.Language) -> String {
        language.languageCode?.identifier ?? language.minimalIdentifier
    }

    func languageName(_ language: Locale.Language) -> String {
        let code = languageCode(for: language)
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    /// One row per language rather than per variant: the framework reports 47 entries for 25
    /// languages, so the unfiltered list read "English (Australia)" through "English (South
    /// Africa)" nine times before reaching F.
    var targetLanguages: [Locale.Language] {
        Dictionary(grouping: supportedLanguages, by: languageCode(for:))
            .values
            .compactMap { variants in
                variants.sorted { $0.maximalIdentifier < $1.maximalIdentifier }.first
            }
            .sorted {
                let result = languageName($0).localizedStandardCompare(languageName($1))
                return result == .orderedSame
                    ? languageCode(for: $0) < languageCode(for: $1)
                    : result == .orderedAscending
            }
    }

    func variants(for language: Locale.Language) -> [Locale.Language] {
        let code = languageCode(for: language)
        return supportedLanguages
            .filter { languageCode(for: $0) == code }
            .sorted { $0.maximalIdentifier < $1.maximalIdentifier }
    }

    func selectTargetLanguage(_ language: Locale.Language) {
        if let current = viewmodel.translationTargetLanguage,
           languageCode(for: current) == languageCode(for: language) {
            return
        }

        let availableVariants = variants(for: language)
        let systemRegion = viewmodel.systemLocale.region?.identifier
        let matchingRegion = availableVariants.first { $0.region?.identifier == systemRegion }
        // With no system-region match, maximalIdentifier order is the deterministic fallback.
        viewmodel.translationTargetLanguage = matchingRegion ?? availableVariants.first
    }

    func conversionVariantLabel(_ language: Locale.Language) -> String {
        if languageCode(for: language) == "zh" {
            switch (language.script?.identifier, language.region?.identifier) {
                case ("Hans", _):
                    return "Simplified"
                case ("Hant", "TW"):
                    return "Traditional (Taiwan)"
                case ("Hant", "HK"):
                    return "Traditional (Hong Kong)"
                case ("Hant", _):
                    return "Traditional"
                default:
                    break
            }
        }
        if let region = language.region?.identifier {
            return Locale.current.localizedString(forRegionCode: region) ?? region
        }
        return language.maximalIdentifier
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
        let status = translationStatus
        VStack(alignment: .leading, spacing: 8) {
            pageHeader("Translation", back: .main,
                       status: viewmodel.userDefaultStorage.translate ? status : nil)
            Divider()
            HStack {
                Toggle("Translate to \(viewmodel.userLocaleLanguageString)",
                       isOn: $viewmodel.userDefaultStorage.translate)
                    .disabled(!viewmodel.userDefaultStorage.hasOnboarded)
                Spacer()
                Button {
                    navigate(to: .translationTargetLanguage)
                } label: {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                        .padding(.leading, 8)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            disclosureRow("Source (this song)", value: sourceLanguageLabel) {
                navigate(to: .translationSourceLanguage)
            }
            // Conversion is the target language's regional variant, so it only exists when a
            // language is actually chosen and that language has more than one. Nine of the 25
            // supported languages do; the rest never show this row.
            if let target = viewmodel.translationTargetLanguage,
               variants(for: target).count > 1 {
                disclosureRow("\(languageName(target)) Conversion",
                              value: conversionVariantLabel(target)) {
                    navigate(to: .conversion)
                }
            }
            // Romanizing Latin lyrics is a no-op, so hide that transform when it cannot act.
            if viewmodel.lyricsCanBeRomanized {
                Toggle("Romanize", isOn: $viewmodel.userDefaultStorage.romanize)
            }
        }
        .frame(width: 300)
    }

    @ViewBuilder
    var conversionPage: some View {
        let currentTarget = viewmodel.translationTargetLanguage
        let availableVariants = currentTarget.map(variants(for:)) ?? []
        let title = currentTarget.map { "\(languageName($0)) Conversion" } ?? "Conversion"

        VStack(alignment: .leading, spacing: 8) {
            pageHeader(title, back: .translationSettings)
            Divider()
            // English alone has nine regional variants -- more than fits the height the main
            // page sets -- so this list scrolls like the language pages rather than running
            // off the bottom.
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(availableVariants, id: \.maximalIdentifier) { language in
                        choiceRow(conversionVariantLabel(language),
                                  selected: currentTarget?.maximalIdentifier == language.maximalIdentifier) {
                            viewmodel.translationTargetLanguage = language
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .frame(maxHeight: .infinity)
        }
        .frame(width: 300)
    }

    @ViewBuilder
    /// The scrollable language list.
    ///
    /// Uses List rather than ScrollView + VStack: a probe build showed the same Button firing
    /// reliably outside a ScrollView and never inside one, so the ScrollView was swallowing the
    /// clicks. List is backed by AppKit's own scrolling table, which routes them properly.
    var translationTargetLanguagePage: some View {
        // Read the current value once instead of per row.
        let currentTarget = viewmodel.translationTargetLanguage

        VStack(alignment: .leading, spacing: 6) {
            pageHeader("Translate to", back: .translationSettings)
            Divider()
            List {
                choiceRow("System (\(viewmodel.systemLocaleString))", selected: currentTarget == nil) {
                    viewmodel.translationTargetLanguage = nil
                }
                ForEach(targetLanguages, id: \.maximalIdentifier) { language in
                    choiceRow(languageName(language),
                              selected: currentTarget.map { languageCode(for: $0) } == languageCode(for: language)) {
                        selectTargetLanguage(language)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(maxHeight: .infinity)
        }
        .frame(width: 300)
    }

    @ViewBuilder
    var translationSourceLanguagePage: some View {
        // Read the current value once instead of per row.
        let currentSource = viewmodel.translationSourceLanguage

        VStack(alignment: .leading, spacing: 6) {
            pageHeader("Source Language", back: .translationSettings)
            Divider()
            List {
                choiceRow("Auto", selected: currentSource == nil) {
                    setSourceLanguage(nil)
                }
                ForEach(supportedLanguages, id: \.maximalIdentifier) { language in
                    choiceRow(languageLabel(language),
                              selected: currentSource?.maximalIdentifier == language.maximalIdentifier) {
                        setSourceLanguage(language)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(maxHeight: .infinity)
        }
        .frame(width: 300)
    }

    var body: some View {
        Group {
            switch page {
                case .main:
                    mainPage
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(key: MainPageHeightKey.self,
                                                       value: proxy.size.height)
                            }
                        )
                case .moreOptions:
                    moreOptionsPage
                case .settings:
                    settingsPage
                case .translationSettings:
                    translationSettingsPage
                case .translationTargetLanguage:
                    translationTargetLanguagePage
                case .translationSourceLanguage:
                    translationSourceLanguagePage
                case .conversion:
                    conversionPage
            }
        }
        // The main page sets the height and every other page takes it, so the panel no longer
        // resizes as pages change. Top-aligned, or a short page would float its rows in the
        // middle of the box.
        .frame(height: page == .main ? nil : mainPageHeight, alignment: .top)
        .onPreferenceChange(MainPageHeightKey.self) { height in
            // Sub-pages publish nothing, so the key falls back to 0 while one is showing; the
            // last real measurement is what should stand.
            if height > 0 { mainPageHeight = height }
        }
        // Each page keeps its natural height through the change. Without this the two pages
        // are laid out together while the container is between sizes, and SwiftUI answers by
        // squeezing them -- rows collapse into each other mid-flight. Sliding them sideways
        // made it worse, since both were then on screen for the whole animation; a crossfade
        // has only one page at full opacity at a time and cannot fold anything.
        .fixedSize(horizontal: false, vertical: true)
        // A shade of scale under the fade so the page reads as arriving rather than merely
        // appearing. It is a render-time effect and takes no part in layout, so unlike the
        // slide it cannot pull the two pages into fighting over the same space.
        // The fade and the resize want different curves. A spring on opacity reads as a
        // flicker -- it overshoots past fully opaque and back -- so the crossfade gets a short
        // ease-out of its own, while the panel's height springs.
        .transition(
            .opacity.animation(.easeOut(duration: 0.13))
                .combined(with: .scale(scale: 0.97))
        )
        // The window follows its content's height, so springing the content is what makes the
        // panel itself land with a little give rather than snapping to the new size.
        .animation(.bouncy(duration: 0.3, extraBounce: 0.12), value: page)
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
