import Foundation

/// BERT's uncased WordPiece tokenizer, as Hugging Face's `BertTokenizer` runs it with `do_lower_case` (the Smart Search
/// model's setting). The text is cleaned, lowercased with its accents removed, and split on spaces and punctuation,
/// with each CJK character on its own. Each word is then split into the longest pieces the vocabulary has, marking
/// pieces after the first with "##". The result starts with [CLS] and ends with [SEP].
///
/// Everything is compared by Unicode scalars, as Python compares code points. Swift's `String` equality would treat
/// canonically equivalent text as equal, and find a precomposed Hangul syllable in the vocabulary for its jamo.
struct WordPieceTokenizer: Sendable {
    private let vocabulary: [[UInt32]: Int32]
    let unknown: Int32
    let start: Int32
    let end: Int32

    static let maxScalarsPerWord = 100

    /// `text` is `vocab.txt`: one token per line, its line number being its id.
    init(vocabulary text: String) throws {
        var vocabulary: [[UInt32]: Int32] = [:]
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            var token = line
            if token.hasSuffix("\r") { token = token.dropLast() }
            if token.isEmpty, index == lines.count - 1 { continue }
            // Like Hugging Face's `load_vocab`, a repeated token keeps its last id.
            vocabulary[token.unicodeScalars.map(\.value)] = Int32(index)
        }
        func id(_ token: String) throws -> Int32 {
            guard let id = vocabulary[token.unicodeScalars.map(\.value)] else { throw SearchModelError.damagedFile("vocab.txt") }
            return id
        }
        self.vocabulary = vocabulary
        unknown = try id("[UNK]")
        start = try id("[CLS]")
        end = try id("[SEP]")
    }

    /// Token ids for `text`, cut to `maxTokens` including [CLS] and [SEP].
    func tokenize(_ text: String, maxTokens: Int = 512) -> [Int32] {
        var ids: [Int32] = [start]
        for word in Self.words(in: text) {
            ids += pieces(of: word)
            if ids.count >= maxTokens - 1 { break }
        }
        return Array(ids.prefix(maxTokens - 1)) + [end]
    }

    /// Greedy longest-match-first, as BERT's WordPiece does. A word with a part the vocabulary lacks is [UNK] as a whole.
    private func pieces(of word: [UInt32]) -> [Int32] {
        guard word.count <= Self.maxScalarsPerWord else { return [unknown] }
        var ids: [Int32] = []
        var start = 0
        while start < word.count {
            var end = word.count
            var found: Int32?
            while start < end {
                let piece = (start > 0 ? Self.continuation : []) + word[start..<end]
                if let id = vocabulary[piece] {
                    found = id
                    break
                }
                end -= 1
            }
            guard let found else { return [unknown] }
            ids.append(found)
            start = end
        }
        return ids
    }

    private static let continuation: [UInt32] = [35, 35] // "##"

    // MARK: - Basic tokenizer

    /// The words of `text` as Unicode scalars: cleaned, lowercased without accents, split on whitespace and punctuation.
    static func words(in text: String) -> [[UInt32]] {
        var words: [[UInt32]] = []
        var current = ""
        func flush() {
            guard !current.isEmpty else { return }
            words += split(normalize(current))
            current = ""
        }
        for scalar in text.unicodeScalars {
            if scalar.value == 0 || scalar.value == 0xFFFD || isControl(scalar) { continue }
            if isWhitespace(scalar) {
                flush()
            } else if isCJK(scalar.value) {
                flush()
                // Normalized too: a compatibility ideograph decomposes to the unified one.
                words += split(normalize(String(scalar)))
            } else {
                current.unicodeScalars.append(scalar)
            }
        }
        flush()
        return words
    }

    /// Lowercased, then decomposed with the combining marks dropped: "Café" becomes "cafe".
    private static func normalize(_ word: String) -> [UInt32] {
        word.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars
            .filter { $0.properties.generalCategory != .nonspacingMark }
            .map(\.value)
    }

    /// Each punctuation mark becomes a word of its own.
    private static func split(_ scalars: [UInt32]) -> [[UInt32]] {
        var words: [[UInt32]] = []
        var current: [UInt32] = []
        for value in scalars {
            if let scalar = Unicode.Scalar(value), isPunctuation(scalar) {
                if !current.isEmpty { words.append(current) }
                words.append([value])
                current = []
            } else {
                current.append(value)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    private static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        [" ", "\t", "\n", "\r"].contains(scalar) || scalar.properties.generalCategory == .spaceSeparator
    }

    /// Control and format characters, except the whitespace ones.
    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        if ["\t", "\n", "\r"].contains(scalar) { return false }
        switch scalar.properties.generalCategory {
        case .control, .format, .unassigned, .privateUse, .surrogate: return true
        default: return false
        }
    }

    /// Unicode punctuation, plus every ASCII symbol, as BERT counts "$" and "^" as punctuation too.
    private static func isPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        if (33...47).contains(value) || (58...64).contains(value) || (91...96).contains(value) || (123...126).contains(value) {
            return true
        }
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation, .initialPunctuation,
             .finalPunctuation, .otherPunctuation:
            return true
        default:
            return false
        }
    }

    /// CJK ideographs, which BERT treats as words of their own. Hangul and kana aren't among them.
    private static func isCJK(_ value: UInt32) -> Bool {
        (0x4E00...0x9FFF).contains(value) || (0x3400...0x4DBF).contains(value) || (0x20000...0x2A6DF).contains(value)
            || (0x2A700...0x2B73F).contains(value) || (0x2B740...0x2B81F).contains(value) || (0x2B820...0x2CEAF).contains(value)
            || (0xF900...0xFAFF).contains(value) || (0x2F800...0x2FA1F).contains(value)
    }
}
