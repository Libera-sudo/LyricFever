//
//  LocalTranslationService.swift
//  Lyric Fever
//

import Foundation
import NaturalLanguage

/// Translates lyrics with a locally hosted Hy-MT2 model, served by LM Studio on an
/// OpenAI-compatible endpoint at 127.0.0.1:1234.
///
/// Hy-MT2 is a translation-specialised model driven by a fixed prompt template: it treats
/// everything it is handed as text to translate. That makes it structurally immune to
/// instruction injection, but it also means it will not honour any structural contract we
/// ask for. Given several lines at once it merges and reorders them as it sees fit, and the
/// line count drifts. Lyrics are timestamped per line, so a drifting line count desyncs the
/// entire song -- far worse than a clumsy translation. Every line is therefore sent as its
/// own request and reassembled by index: the correspondence is guaranteed by construction
/// rather than by the model's cooperation.
///
/// Anything short of a complete result returns nil so the caller can fall back to Apple's
/// translator. A song showing half local and half Apple translations would be worse than
/// either one alone.
enum LocalTranslationService {
    private static let endpoint = URL(string: "http://127.0.0.1:1234/v1/chat/completions")!
    private static let modelsEndpoint = URL(string: "http://127.0.0.1:1234/v1/models")!
    private static let model = "hy-mt2-1.8b"

    /// LM Studio serves a small number of parallel slots; four keeps them busy without
    /// queueing requests behind each other.
    private static let maxConcurrent = 4

    /// Individual lines translate in well under a second when the model is warm. The
    /// generous ceiling only exists to cover the first request after the model is loaded.
    private static let lineTimeout: TimeInterval = 20
    private static let probeTimeout: TimeInterval = 2

    /// The whole song has to resolve within this budget or the local path gives up. Per-line
    /// timeouts do not bound the total -- 50 lines four at a time can stack into minutes on a
    /// stalled model, and the user watches an untranslated song for every one of them.
    private static let overallTimeout: TimeInterval = 12

    // MARK: - Entry point

    /// Returns one translation per input line, or nil if the local model could not
    /// translate all of them.
    static func translate(_ lines: [LyricLine], to target: Locale.Language) async -> [String]? {
        guard !lines.isEmpty else { return [] }
        // Race the batch against a single deadline, then cancel whichever task lost.
        return await withTaskGroup(of: TimedOutcome.self) { group in
            group.addTask { .finished(await translateAll(lines, to: target)) }
            group.addTask {
                try? await Task.sleep(for: .seconds(overallTimeout))
                return .timedOut
            }
            var outcome: [String]?
            switch await group.next() ?? .timedOut {
                case .finished(let translated):
                    outcome = translated
                case .timedOut:
                    print("Local Translation: song exceeded \(Int(overallTimeout))s, falling back")
                    outcome = nil
            }
            group.cancelAll()
            return outcome
        }
    }

    private enum TimedOutcome: Sendable {
        case finished([String]?)
        case timedOut
    }

    private static func translateAll(_ lines: [LyricLine], to target: Locale.Language) async -> [String]? {
        guard let targetName = englishLanguageName(for: target) else {
            print("Local Translation: no English name for target language, skipping local model")
            return nil
        }
        guard await isAvailable() else {
            print("Local Translation: hy-mt2 not reachable on :1234, falling back")
            return nil
        }

        var results = [String?](repeating: nil, count: lines.count)
        do {
            try await withThrowingTaskGroup(of: (Int, String).self) { group in
                var next = 0
                func addTask(_ index: Int) {
                    let source = lines[index].words
                    group.addTask {
                        (index, try await translateLine(source, into: targetName))
                    }
                }
                while next < lines.count, next < maxConcurrent {
                    addTask(next)
                    next += 1
                }
                while let (index, translated) = try await group.next() {
                    results[index] = translated
                    if next < lines.count {
                        addTask(next)
                        next += 1
                    }
                }
            }
        } catch {
            print("Local Translation: failed (\(error.localizedDescription)), falling back")
            return nil
        }

        let complete = results.compactMap { $0 }
        guard complete.count == lines.count else {
            print("Local Translation: incomplete result, falling back")
            return nil
        }
        print("Local Translation: translated \(complete.count) lines into \(targetName)")
        return complete
    }

    // MARK: - Single line

    private static func translateLine(_ source: String, into targetName: String) async throws -> String {
        // Blank lines and pure punctuation/notation (♪, instrumental markers) carry no
        // text to translate; sending them wastes a slot and invites the model to invent
        // something. Their slot still has to be filled to keep the line count intact.
        guard source.rangeOfCharacter(from: .letters) != nil else { return source }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = lineTimeout

        // Hy-MT2's official template, with no system prompt. The model is tuned for exactly
        // this phrasing; deviating from it degrades output quality.
        let prompt = "Translate the following segment into \(targetName), without additional explanation.\n\n\(source)"
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            // Low temperature keeps output reproducible. Deliberately no repetition
            // penalty: lyrics repeat lines on purpose, and penalising that corrupts them.
            "temperature": 0.1,
            "max_tokens": 512,
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LocalTranslationError.badResponse
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw LocalTranslationError.unreadableBody
        }

        let translated = content.trimmingCharacters(in: .whitespacesAndNewlines)
        // An empty completion would silently blank out a lyric line; treat it as failure
        // so the whole song falls back rather than showing a hole.
        guard !translated.isEmpty else { throw LocalTranslationError.emptyCompletion }
        return translated
    }

    // MARK: - Availability

    /// A quick liveness probe. The model server is frequently off (it is unloaded to free
    /// memory), so this has to fail fast rather than make every song wait for a timeout.
    private static func isAvailable() async -> Bool {
        var request = URLRequest(url: modelsEndpoint)
        request.timeoutInterval = probeTimeout
        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse, http.statusCode == 200,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let models = json["data"] as? [[String: Any]]
        else { return false }
        return models.contains { ($0["id"] as? String)?.hasPrefix("hy-mt2") == true }
    }

    // MARK: - Language naming

    /// The template needs the target language written in English ("Chinese", "Japanese").
    /// Deriving it from Locale keeps every language the app already offers working, instead
    /// of a hand-maintained table that silently misses one.
    private static func englishLanguageName(for language: Locale.Language) -> String? {
        guard let code = language.languageCode?.identifier else { return nil }
        return Locale(identifier: "en_US").localizedString(forLanguageCode: code)
    }
}

enum LocalTranslationError: Error {
    case badResponse
    case unreadableBody
    case emptyCompletion
}
