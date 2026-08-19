//
//  SearchResultsNSTableView.swift
//  Lyric Fever
//
//  Created by Salman Navroz on 4/2/26.
//

import SwiftUI

struct SearchResultsNSTableView: NSViewRepresentable {
    let results: [SongResult]
    let agreementScores: [UUID: Double]
    @Binding var selectedID: UUID?
    let textColor: Color

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = NSTableView()

        // Width is (initial, minimum). The two numeric columns need far less room than the
        // three that hold names, and a name column squeezed to nothing is what makes the
        // "Song Name" and "Album Name" ellipses unreadable.
        for (id, title, width, minWidth) in [
            ("provider", "Lyric Provider", 110.0, 60.0),
            ("length", "Length", 60.0, 44.0),
            ("match", "Match", 60.0, 44.0),
            ("song", "Song Name", 170.0, 60.0),
            ("album", "Album Name", 150.0, 60.0),
            ("artist", "Artist Name", 150.0, 60.0)
        ] {
            let col = NSTableColumn(identifier: .init(id))
            col.title = title
            col.width = width
            col.minWidth = minWidth
            // Both masks: `.autoresizingMask` alone lets the table share out its own width
            // changes but leaves the divider inert, so the columns could never be dragged.
            col.resizingMask = [.userResizingMask, .autoresizingMask]
            tableView.addTableColumn(col)
        }

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.allowsMultipleSelection = false
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.style = .inset
        tableView.allowsColumnResizing = true
        // Widths are the user's decision once they have made it, so remember them rather than
        // resetting to the defaults above every time the window opens.
        tableView.autosaveName = "SearchResultsColumns"
        tableView.autosaveTableColumns = true

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let c = context.coordinator
        c.results = results
        c.parent = self
        c.textColor = NSColor(textColor)

        guard let tableView = nsView.documentView as? NSTableView else { return }
        tableView.reloadData()

        if let selectedID, let idx = results.firstIndex(where: { $0.id == selectedID }) {
            tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }
    }

    class Coordinator: NSObject {
        var parent: SearchResultsNSTableView
        var results: [SongResult] = []
        var textColor: NSColor

        init(_ parent: SearchResultsNSTableView) {
            self.parent = parent
            self.textColor = NSColor(parent.textColor)
        }
    }
}

extension SearchResultsNSTableView.Coordinator: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        results.count
    }
}
extension SearchResultsNSTableView.Coordinator: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < results.count else { return nil }
        let result = results[row]
        let text: String
        switch tableColumn?.identifier.rawValue {
        case "provider":
            text = result.lyricType
        case "length":
            text = result.durationMS.map(Self.formatDuration) ?? ""
        case "match":
            let score = parent.agreementScores[result.id] ?? 0
            text = score > 0 ? "\(Int((score * 100).rounded()))%" : ""
        case "song":
            text = result.songName
        case "album":
            text = result.albumName
        case "artist":
            text = result.artistName
        default:         
            text = ""
        }
        let cell = NSTextField(labelWithString: text)
        cell.lineBreakMode = .byTruncatingTail
        cell.textColor = textColor
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTableView else { return }
        let row = tv.selectedRow
        if row >= 0, row < results.count {
            parent.selectedID = results[row].id
        } else {
            parent.selectedID = nil
        }
    }

    private static func formatDuration(_ durationMS: Int) -> String {
        let totalSeconds = durationMS / 1_000
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }
}
