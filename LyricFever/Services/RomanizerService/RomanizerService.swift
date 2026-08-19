//
//  RegularRomanizer.swift
//  Lyric Fever
//
//  Created by Avi Wadhwa on 2025-07-26.
//


//
//  RegularRomanizer.swift
//  Lyric Fever
//
//  Created by Avi Wadhwa on 2025-07-18.
//

import NaturalLanguage
import Mecab_Swift
import IPADic
import OpenCC

// Isolated to the main actor because every caller (ViewModel) already is, and
// because the shared instances below are not safe to hand to arbitrary threads:
// MeCab's tokenizer in particular is not threadsafe. Moving this work off the
// main actor needs a per-context instance rather than a shared one.
@MainActor
class RomanizerService {
    // Building a converter or tokenizer loads and compiles its dictionaries, so
    // these are meant to be built once and reused. Building one per lyric line
    // also leaked permanently: SwiftyOpenCC's ChineseConverter never frees its
    // underlying CCConverterRef, so a single 50-line song stranded ~50 compiled
    // dictionaries and grew the process by hundreds of MB per track.
    private static let ipadicTokenizer: Tokenizer? = {
        let ipadic = IPADic()
        return try? Tokenizer(dictionary: ipadic)
    }()
    private static let simplifiedConverter = try? ChineseConverter(options: [.simplify])
    private static let traditionalNeutralConverter = try? ChineseConverter(options: [.traditionalize])
    private static let hongKongConverter = try? ChineseConverter(options: [.traditionalize, .hkStandard])
    private static let taiwanConverter = try? ChineseConverter(options: [.traditionalize, .twStandard, .twIdiom])

    private static func generateJapaneseRomanizedString(_ string: String) -> String? {
        guard let romajiTokens = ipadicTokenizer?.tokenize(text: string, transliteration: .romaji) else {
            return nil
        }
        let romanized = romajiTokens.map{$0.reading}.filter{!$0.isEmpty}.joined(separator: " ")
        //hachimitsu ha kuma no dai kōbutsu desu 。
        return romanized
    }
    // The language decision belongs to the song, not the line. A lyric line is often
    // three or four characters, and NLLanguageRecognizer reads a kanji-only line as
    // Chinese often enough that the non-Japanese branch below then returns Mandarin
    // pinyin -- leaving one Japanese song half romaji and half pinyin.
    private static func songIsJapanese(_ lyrics: [String]) -> Bool {
        let wholeSong = lyrics.joined(separator: "\n")
        // Kana is exclusive to Japanese among the scripts that reach this app, so a
        // single kana anywhere in the song settles it. The recognizer is only the
        // fallback for the rare all-kanji lyric, and it reads the song, not a line.
        let containsKana = wholeSong.unicodeScalars.contains { scalar in
            (0x3040...0x309F).contains(scalar.value) || (0x30A0...0x30FF).contains(scalar.value)
        }
        return containsKana || NLLanguageRecognizer.dominantLanguage(for: wholeSong) == .japanese
    }

    static func generateRomanizedLyrics(_ lyrics: [String]) -> [String] {
        let isJapanese = songIsJapanese(lyrics)
        print("Romanizing \(lyrics.count) lines as \(isJapanese ? "Japanese" : "non-Japanese")")
        // A line that fails to transform falls back to itself: romanizedLyrics is read
        // in lockstep with the lyric array, so dropping one element would shift every
        // line after it onto the wrong timestamp.
        return lyrics.map { line in
            let romanized = isJapanese
                ? generateJapaneseRomanizedString(line)
                : line.applyingTransform(.toLatin, reverse: false)
            return romanized ?? line
        }
    }
    
    static func generateRomanizedString(_ string: String) -> String? {
        print("Generating Romanized String for string \(string)")
        if let language = NLLanguageRecognizer.dominantLanguage(for: string), language == .japanese {
            return generateJapaneseRomanizedString(string)
        } else {
            return string.applyingTransform(.toLatin, reverse: false)
        }
    }


    static func generateMainlandTransliteration(_ lyric: LyricLine) -> String? {
        guard let converter = simplifiedConverter else {
            print("RomanizerService: MainlandTransliteration error: converter unavailable")
            return nil
        }
        return converter.convert(lyric.words)
    }
    
    static func generateTraditionalNeutralTransliteration(_ lyric: LyricLine) -> String? {
        guard let converter = traditionalNeutralConverter else {
            print("RomanizerService: TraditionalNeutralTransliteration error: converter unavailable")
            return nil
        }
        return converter.convert(lyric.words)
    }
    
    static func generateHongKongTransliteration(_ lyric: LyricLine) -> String? {
        guard let converter = hongKongConverter else {
            print("RomanizerService: HongKongTransliteration error: converter unavailable")
            return nil
        }
        return converter.convert(lyric.words)
    }
    
    static func generateTaiwanTransliteration(_ lyric: LyricLine) -> String? {
        guard let converter = taiwanConverter else {
            print("RomanizerService: TaiwanTransliteration error: converter unavailable")
            return nil
        }
        return converter.convert(lyric.words)
    }
}
