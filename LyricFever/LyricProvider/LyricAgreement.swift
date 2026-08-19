//
//  LyricAgreement.swift
//  Lyric Fever
//

import Foundation

enum LyricAgreement {
    /// Normalised comparison keys for a lyric body: one entry per sung line.
    static func fingerprint(_ lyrics: [LyricLine]) -> Set<String> {
        var sungLines = lyrics[...]
        if let lastLine = sungLines.last?.words.trimmingCharacters(in: .whitespacesAndNewlines),
           lastLine.lowercased().hasPrefix("now playing:") {
            sungLines = sungLines.dropLast()
        }

        let charactersToStrip = CharacterSet.punctuationCharacters
            .union(.whitespacesAndNewlines)

        return Set(sungLines.compactMap { line in
            let normalisedScalars = line.words.lowercased().unicodeScalars.filter {
                !charactersToStrip.contains($0)
            }
            let key = String(String.UnicodeScalarView(normalisedScalars))
            return key.isEmpty ? nil : key
        })
    }

    /// 0...1. Jaccard overlap of two fingerprints.
    static func similarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        let unionCount = a.union(b).count
        guard unionCount > 0 else { return 0 }
        return Double(a.intersection(b).count) / Double(unionCount)
    }
}
