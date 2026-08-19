//
//  SearchWindow.swift
//  Lyric Fever
//
//  Created by Avi Wadhwa on 2025-09-02.
//

import SwiftUI

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
    
    private let overlayHeight: CGFloat = 250
    
    @ViewBuilder
    var searchControlsView: some View {
        HStack {
            Text("Song Name")
            TextField("", text: $trackName)
                .padding(.trailing, 30)
            Text("Artist Name:")
            TextField("", text: $artistName)
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
            HStack {
                LyricPreviewNSTableView(lyrics: selectedLyricLyric.lyrics)
                              .frame(width: 400)
                Spacer()
                Button {
                    let cleanLyrics = NetworkFetchReturn(lyrics: selectedLyricLyric.lyrics).processed(withSongName: trackName, duration: viewmodel.duration).lyrics
                    
                    if let currentIndex = viewmodel.currentlyPlayingLyricsIndex, currentIndex >= cleanLyrics.count {
                        // set currentindex to nil to prevent out of bounds index access with existing UI
                        viewmodel.currentlyPlayingLyricsIndex = nil
                    }
                    
                    viewmodel.setNewLyricsColorTranslationRomanizationAndStartUpdater(with: cleanLyrics)
                    guard let spotifyID = viewmodel.currentlyPlaying else {
                        return
                    }
                    // thats how i save to coredata
                    let _ = SongObject(from: cleanLyrics, with: viewmodel.coreDataContainer.viewContext, trackID: spotifyID, trackName: trackName)
                    viewmodel.saveCoreData()
                    lyricsAreApplied = true
                } label: {
                    Label(lyricsAreApplied ? "Lyrics were applied!" : "Click to Use", systemImage: "checkmark")
                        .bold()
                        .frame(width: 230)
                }
                .buttonStyle(.borderedProminent)
                .disabled(lyricsAreApplied)
                .tint(lyricsAreApplied ? .gray : .green)
            }
            .padding()
//            .id(selectedLyric)
            .transition(.move(edge: .bottom))
            .frame(maxWidth: .infinity)
            .frame(height: overlayHeight)
            .background(
                .thinMaterial
            )
        }
    }
    
    @ViewBuilder
    var searchWindow: some View {
        VStack {
            searchControlsView
            ZStack {
                searchResultsView
                loadingView
            }
        }
        // Reserve space when the bottom overlay is visible so rows aren’t hidden
        .padding(.bottom, selectedLyric != nil ? overlayHeight : 0)
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
        let ranked = rankAndDeduplicate(collectedResults, targetDurationMS: viewmodel.duration)
        guard !Task.isCancelled else { return }

        agreementScores = ranked.scores
        searchResults = ranked.results
        hasCompletedSearch = true
    }

    private func rankAndDeduplicate(
        _ results: [SongResult],
        targetDurationMS: Int
    ) -> (results: [SongResult], scores: [UUID: Double]) {
        struct Candidate {
            let result: SongResult
            let fingerprint: Set<String>
            let agreementScore: Double
            let arrivalOrder: Int
        }

        let fingerprints = Dictionary(uniqueKeysWithValues: results.map {
            ($0.id, LyricAgreement.fingerprint($0.lyrics))
        })

        var candidates = results.enumerated().map { arrivalOrder, result in
            let fingerprint = fingerprints[result.id] ?? []
            let agreementScore = results.lazy
                .filter { $0.lyricType != result.lyricType }
                .map { LyricAgreement.similarity(fingerprint, fingerprints[$0.id] ?? []) }
                .max() ?? 0

            return Candidate(
                result: result,
                fingerprint: fingerprint,
                agreementScore: agreementScore,
                arrivalOrder: arrivalOrder
            )
        }

        candidates.sort { lhs, rhs in
            if lhs.agreementScore != rhs.agreementScore {
                return lhs.agreementScore > rhs.agreementScore
            }

            let lhsDifference = lhs.result.durationMS.map { abs($0 - targetDurationMS) }
            let rhsDifference = rhs.result.durationMS.map { abs($0 - targetDurationMS) }
            switch (lhsDifference, rhsDifference) {
            case let (lhs?, rhs?) where lhs != rhs:
                return lhs < rhs
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.arrivalOrder < rhs.arrivalOrder
            }
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
            Dictionary(uniqueKeysWithValues: deduplicated.map {
                ($0.result.id, $0.agreementScore)
            })
        )
    }
    
    var body: some View {
        searchWindow
            .onExitCommand {
                selectedLyric = nil
            }
            .overlay(
                VStack {
                    selectedLyricView.ignoresSafeArea()
                }
                    .animation(.snappy(duration: 0.2), value: selectedLyric)
                , alignment: .bottom)
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
            .tint(viewmodel.currentBackground)
        .navigationTitle("Searching for \(viewmodel.currentlyPlayingName ?? "-") by \(viewmodel.currentlyPlayingArtist ?? "-")")
        .presentedWindowToolbarStyle(.unified)
    }
}
