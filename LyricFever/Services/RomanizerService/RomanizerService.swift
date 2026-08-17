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
        let romanized = romajiTokens.map{$0.reading}.joined()
        //hachimitsu ha kuma no dai kōbutsu desu 。
        return romanized
    }
    static func generateRomanizedLyric(_ lyric: LyricLine) -> String? {
        print("Generating Romanized String for lyric \(lyric.words)")
        if let language = NLLanguageRecognizer.dominantLanguage(for: lyric.words), language == .japanese {
            return generateJapaneseRomanizedString(lyric.words)
        } else {
            return lyric.words.applyingTransform(.toLatin, reverse: false)
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
