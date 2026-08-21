//
//  SearchWindow.swift
//  Lyric Fever
//
//  Created by Avi Wadhwa on 2025-09-02.
//

import SwiftUI
import StringMetric

struct SearchWindow: View {
    @Environment(ViewModel.self) var viewmodel
    @State var trackName: String = ""
    @State var artistName: String = ""
    @State private var searchResults: [SongResult] = []
    @State private var agreementScores: [UUID: Double] = [:]
    @State var isFetching = false
    @State private var hasCompletedSearch = false
    @State private var selectedLyric: UUID? = nil
    @State private var lyricsAreApplied: Bool = false
    @State private var searchTask: Task<Void, Never>? = nil
    

    @ViewBuilder
    var searchControlsView: some View {
        HStack {
            Text("Song Name:")
                .foregroundStyle(.primary)
            // These two are editable: the search runs on whatever they hold, and the
            // whole point of the window is correcting a bad title or artist. Glass made
            // them read as labels sitting among the glass buttons, so they keep the
            // standard bordered field instead -- the control that looks typed-into.
            TextField("", text: $trackName)
                .textFieldStyle(.roundedBorder)
                .padding(.trailing, 30)
            Text("Artist Name:")
                .foregroundStyle(.primary)
            TextField("", text: $artistName)
                .textFieldStyle(.roundedBorder)
                .padding(.trailing, 30)
            Button {
                searchResults = []
                agreementScores = [:]
                hasCompletedSearch = false
                // cancel any stale search task
                searchTask?.cancel()
                searchTask = Task { @MainActor in
                    do {
                        try await searchLyrics()
                    } catch {
                        print("Search Task Error: \(error)")
                    }
                }
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .disabled(isFetching)
            .keyboardShortcut(.defaultAction)
            .tint(.primary)
            .menubarGlassButtonStyle()
            Button("Remove Lyrics") {
                guard let trackID = viewmodel.currentlyPlaying else { return }
                let removedLyricsWerePreviewed = lyricsAreApplied
                viewmodel.deleteLyric(trackID: trackID)
                if removedLyricsWerePreviewed {
                    selectedLyric = nil
                }
                lyricsAreApplied = false
            }
            .disabled(viewmodel.currentlyPlaying == nil || viewmodel.lyricsIsEmptyPostLoad)
            .menubarGlassButtonStyle()
            Button {
                applySelectedLyrics()
            } label: {
                Label(
                    lyricsAreApplied ? "Applied" : "Click to Use",
                    systemImage: lyricsAreApplied ? "checkmark.circle.fill" : "checkmark"
                )
            }
            .disabled(selectedLyric == nil || lyricsAreApplied)
            .menubarGlassButtonStyle()
        }
    }
    
    @ViewBuilder
    var searchResultsView: some View {
        if hasCompletedSearch && searchResults.isEmpty {
            ContentUnavailableView(
                "No lyrics found",
                systemImage: "music.note.list",
                description: Text("Try a shorter song name, or drop the artist.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            SearchResultsNSTableView(
                results: searchResults,
                agreementScores: agreementScores,
                selectedID: $selectedLyric
            )
        }
    }
    
    @ViewBuilder
    var selectedLyricView: some View {
        if let selectedLyric, let selectedLyricLyric = searchResults.first(where: { $0.id == selectedLyric}) {
            Group {
                if selectedLyricLyric.lyrics.isEmpty {
                    // Empty results are filtered out of the list before it is shown, so this
                    // is a backstop rather than the usual case -- but a preview that silently
                    // collapses reads as one that stopped working, and that is worth a
                    // sentence whenever an empty result does reach here.
                    Text("This result has no lyrics to preview.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(height: 60)
                } else {
                    LyricPreviewNSTableView(
                        lyrics: selectedLyricLyric.lyrics
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                }
            }
            .transition(.move(edge: .bottom))
        }
    }

    private func applySelectedLyrics() {
        guard
            let selectedLyric,
            let selectedLyricLyric = searchResults.first(where: { $0.id == selectedLyric })
        else { return }

        let cleanLyrics = NetworkFetchReturn(lyrics: selectedLyricLyric.lyrics)
            .processed(withSongName: trackName, duration: viewmodel.duration).lyrics

        if let currentIndex = viewmodel.currentlyPlayingLyricsIndex, currentIndex >= cleanLyrics.count {
            // Set currentIndex to nil to prevent out-of-bounds access in the existing UI.
            viewmodel.currentlyPlayingLyricsIndex = nil
        }

        viewmodel.setNewLyricsColorTranslationRomanizationAndStartUpdater(with: cleanLyrics)
        guard let trackID = viewmodel.currentlyPlaying else { return }
        let _ = SongObject(
            from: cleanLyrics,
            with: viewmodel.coreDataContainer.viewContext,
            trackID: trackID,
            trackName: trackName
        )
        viewmodel.saveCoreData()
        lyricsAreApplied = true
    }
    
    @ViewBuilder
    var searchWindow: some View {
        VStack(alignment: .leading) {
            Text("Searching for \(viewmodel.currentlyPlayingName ?? "-") by \(viewmodel.currentlyPlayingArtist ?? "-")")
                .font(.caption)
                .foregroundStyle(.secondary)
            searchControlsView
            ZStack {
                searchResultsView
                loadingView
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            selectedLyricView
        }
        .animation(.snappy(duration: 0.2), value: selectedLyric)
        .padding()
    }
    
    @ViewBuilder
    var loadingView: some View {
        if isFetching {
            Rectangle()
                .fill(Color.black.opacity(0.5))
                .frame(width: 80, height: 80)
                .cornerRadius(10)
            ProgressView()
        }
    }
    
    func searchLyrics() async throws {
        selectedLyric = nil
        isFetching = true
        defer { isFetching = false }
        searchResults = []
        agreementScores = [:]
        hasCompletedSearch = false

        let searchedTrackName = trackName
        let searchedArtistName = artistName
        let providers = viewmodel.allNetworkLyricProvidersForSearch

        let collectedResults: [SongResult] = await withTaskGroup(
            of: (offset: Int, results: [SongResult]).self,
            returning: [SongResult].self
        ) { group in
            for (offset, lyricProvider) in providers.enumerated() {
                group.addTask { @MainActor in
                    guard !Task.isCancelled else { return (offset, []) }
                    do {
                        let results = try await lyricProvider.search(
                            trackName: searchedTrackName,
                            artistName: searchedArtistName
                        )
                        return (offset, Task.isCancelled ? [] : results)
                    } catch {
                        if !Task.isCancelled {
                            print("Search: \(lyricProvider.providerName) failed, continuing: \(error)")
                        }
                        return (offset, [])
                    }
                }
            }

            // A task group yields in completion order, which is whichever provider's server
            // answered first -- so appending as batches arrive would reshuffle equally ranked
            // rows between one search and the next. Each batch is filed under its provider's
            // position and flattened in that order, leaving the final tie-breaker fixed.
            var byProvider = [[SongResult]](repeating: [], count: providers.count)
            for await batch in group {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return []
                }
                byProvider[batch.offset] = batch.results
            }
            return byProvider.flatMap { $0 }
        }

        guard !Task.isCancelled else { return }
        // A result with no lines is nothing to choose between: LRCLIB flags instrumental
        // tracks and returns them regardless, so a solo piano piece answers with three hits
        // and not a word among them, and applying one would only wipe the lyrics. Filtering
        // by emptiness rather than by anyone's instrumental flag also catches a result whose
        // lyrics simply failed to parse, and needs no new field carried through four
        // providers. When every hit is like that the list is empty, which is the honest
        // answer -- "No lyrics found" -- instead of three rows that do nothing.
        let usableResults = collectedResults.filter { !$0.lyrics.isEmpty }
        let ranked = rankAndDeduplicate(usableResults,
                                        searchedTrackName: searchedTrackName,
                                        targetDurationMS: viewmodel.duration)
        guard !Task.isCancelled else { return }

        agreementScores = ranked.scores
        searchResults = ranked.results
        hasCompletedSearch = true
    }

    /// Ranks candidates on three signals at once rather than on lyric agreement alone.
    ///
    /// Agreement -- how closely another provider's copy of the same words matches -- was the
    /// whole ranking, and it measures the wrong thing: it says a song is widely catalogued, not
    /// that it is the song being searched for. Searching "Dec." by Kanaria put two of the
    /// artist's better-known tracks above it at 81% and 78% against its own 69%, precisely
    /// because those are carried identically everywhere while the right song's copies disagree
    /// over credit lines. Duration was in the sort but never reached: it only broke ties in a
    /// continuous Jaccard value, which effectively never ties.
    ///
    /// So duration carries the most weight -- it is the signal that survives translation and
    /// romanisation, which is why the providers already lean on it -- with the title next and
    /// agreement demoted to a corroborating bonus. A signal that cannot be computed hands its
    /// weight to the others rather than standing in with an invented middle value.
    private func rankAndDeduplicate(
        _ results: [SongResult],
        searchedTrackName: String,
        targetDurationMS: Int
    ) -> (results: [SongResult], scores: [UUID: Double]) {
        struct Candidate {
            let result: SongResult
            let fingerprint: Set<String>
            let score: Double
            let arrivalOrder: Int
        }

        let durationWeight = 0.5
        let titleWeight = 0.3
        let agreementWeight = 0.2
        /// Recordings of one song differ by a second or two between catalogues, so that much is
        /// no evidence either way; past a quarter of a minute it is a different recording.
        let durationFullCredit = 2_000
        let durationNoCredit = 15_000

        let fingerprints = Dictionary(uniqueKeysWithValues: results.map {
            ($0.id, LyricAgreement.fingerprint($0.lyrics))
        })

        var candidates = results.enumerated().map { arrivalOrder, result in
            let fingerprint = fingerprints[result.id] ?? []
            let agreementScore = results.lazy
                .filter { $0.lyricType != result.lyricType }
                .map { LyricAgreement.similarity(fingerprint, fingerprints[$0.id] ?? []) }
                .max() ?? 0

            // Unknown when the candidate carries no length, or when nothing is playing to
            // compare it against.
            let durationFit: Double?
            if let durationMS = result.durationMS, targetDurationMS != 0 {
                let difference = abs(durationMS - targetDurationMS)
                switch difference {
                    case ..<durationFullCredit: durationFit = 1
                    case durationNoCredit...: durationFit = 0
                    default:
                        durationFit = Double(durationNoCredit - difference)
                            / Double(durationNoCredit - durationFullCredit)
                }
            } else {
                durationFit = nil
            }

            // StringMetric answers 0 for titles in different scripts -- a romanised title
            // against its original, say. Under weighting that costs a candidate 0.3 rather
            // than ruling it out, which is the point of scoring instead of filtering.
            let titleSimilarity = searchedTrackName.isEmpty
                ? nil
                : searchedTrackName.distance(between: result.songName)

            var weighted = agreementScore * agreementWeight
            var available = agreementWeight
            if let durationFit {
                weighted += durationFit * durationWeight
                available += durationWeight
            }
            if let titleSimilarity {
                weighted += titleSimilarity * titleWeight
                available += titleWeight
            }

            return Candidate(
                result: result,
                fingerprint: fingerprint,
                score: min(max(weighted / available, 0), 1),
                arrivalOrder: arrivalOrder
            )
        }

        candidates.sort { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.arrivalOrder < rhs.arrivalOrder
        }

        var deduplicated: [Candidate] = []
        for candidate in candidates {
            let isSameProviderDuplicate = deduplicated.contains { earlier in
                earlier.result.lyricType == candidate.result.lyricType
                    && LyricAgreement.similarity(earlier.fingerprint, candidate.fingerprint) > 0.9
            }
            if !isSameProviderDuplicate {
                deduplicated.append(candidate)
            }
        }

        return (
            deduplicated.map(\.result),
            // The column is headed "Match", so it shows what the ranking actually used.
            Dictionary(uniqueKeysWithValues: deduplicated.map {
                ($0.result.id, $0.score)
            })
        )
    }
    
    var body: some View {
        searchWindow
            .onExitCommand {
                selectedLyric = nil
            }
            .onAppear {
                trackName = viewmodel.currentlyPlayingName ?? ""
                artistName = viewmodel.currentlyPlayingArtist ?? ""
                // start initial search, canceling any potential concurrent search task
                searchTask?.cancel()
                searchTask = Task { @MainActor in
                    do {
                        try await searchLyrics()
                    } catch {
                        print("Search task error: \(error)")
                    }
                }
            }
            .onChange(of: selectedLyric) {
                lyricsAreApplied = false
            }
            .onChange(of: viewmodel.currentlyPlaying) {
                if viewmodel.currentlyPlaying == nil {
                    return
                }
                // cancel stale search tasks
                searchTask?.cancel()
                isFetching = false
                searchResults = []
                agreementScores = [:]
                hasCompletedSearch = false
                lyricsAreApplied = false
            }
            .onChange(of: viewmodel.currentlyPlayingName) { oldName, newName in
                if let newName {
                    trackName = newName
                }
            }
            .onChange(of: viewmodel.currentlyPlayingArtist) { oldArtist, newArtist in
                if let newArtist {
                    artistName = newArtist
                }
            }
            .background {
                ZStack {
                    VisualEffectBackground(
                        material: .hudWindow,
                        blendingMode: .behindWindow
                    )
                    viewmodel.currentBackground
                        .opacity(0.18)
                        .animation(.smooth, value: viewmodel.currentBackground)
                }
                // Full-bleed, title bar included. The window is non-opaque so the material can
                // sample what is behind it, and a region of a non-opaque window with nothing
                // drawn in it does not hit-test -- leaving the title bar strip unclickable and
                // the window undraggable. Covering it with the material restores both.
                .ignoresSafeArea()
            }
        .navigationTitle("Searching for \(viewmodel.currentlyPlayingName ?? "-") by \(viewmodel.currentlyPlayingArtist ?? "-")")
        .presentedWindowToolbarStyle(.unified)
    }
}
