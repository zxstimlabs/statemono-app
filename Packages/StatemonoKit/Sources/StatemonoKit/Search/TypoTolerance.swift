import Foundation

/// The words in the search index, folded as the tokenizer folds them, with how many items each appears in. Typo
/// tolerance picks its alternatives from here (`fts5vocab` over `itemSearch`).
struct SearchVocabulary: Sendable {
    struct Word: Sendable {
        let text: String
        let scalars: [Unicode.Scalar]
        let documents: Int
    }

    /// Sorted by text, so a prefix is found by binary search.
    let words: [Word]

    init(_ entries: [(text: String, documents: Int)]) {
        words = entries
            .map { Word(text: $0.text, scalars: Array($0.text.unicodeScalars), documents: $0.documents) }
            .sorted { $0.text < $1.text }
    }

    /// Whether some word is `prefix` or starts with it.
    func containsPrefix(_ prefix: String) -> Bool {
        var low = 0
        var high = words.count
        while low < high {
            let middle = (low + high) / 2
            if words[middle].text < prefix { low = middle + 1 } else { high = middle }
        }
        return low < words.count && words[low].text.hasPrefix(prefix)
    }

    /// Other spellings to search for a folded query word that matches nothing as typed.
    ///
    /// - A word that is, or starts, a word in the index gets none: it's probably spelled right, and alternatives would
    ///   pull in unrelated words ("form" would find "from").
    /// - Words of 3 letters or fewer match only as typed.
    /// - Alternatives are index words within 1 edit for words of 4–7 letters, 2 for 8 or more. Swapping two
    ///   neighboring letters counts as one edit.
    /// - The last word may be unfinished, so it's also compared with the beginnings of index words of its length:
    ///   "levenhs" finds words starting with "levensh".
    /// - At most `limit`, the most common first.
    func alternatives(for word: String, isLast: Bool, limit: Int = 10) -> [SearchAlternative] {
        let target = Array(word.unicodeScalars)
        guard target.count > 3, !containsPrefix(word) else { return [] }
        let edits = target.count <= 7 ? 1 : 2
        var found: [SearchAlternative: Int] = [:]
        for candidate in words {
            if editDistance(target, candidate.scalars[...], limit: edits) <= edits {
                found[SearchAlternative(text: candidate.text, isPrefix: false), default: 0] += candidate.documents
            } else if isLast, candidate.scalars.count > target.count,
                      editDistance(target, candidate.scalars.prefix(target.count), limit: edits) <= edits {
                let start = String(String.UnicodeScalarView(candidate.scalars.prefix(target.count)))
                found[SearchAlternative(text: start, isPrefix: true), default: 0] += candidate.documents
            }
        }
        return found
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.text < $1.key.text }
            .prefix(limit)
            .map(\.key)
    }
}

/// Another spelling searched for a query word.
struct SearchAlternative: Hashable, Sendable {
    let text: String
    /// Matches words starting with `text`, not just `text`: an alternative for the word still being typed.
    let isPrefix: Bool
}

/// Damerau–Levenshtein distance between `a` and `b` (optimal string alignment: swapping two neighboring letters is
/// one edit). Stops early and returns `limit + 1` once the distance must be over `limit`.
func editDistance(_ a: [Unicode.Scalar], _ b: ArraySlice<Unicode.Scalar>, limit: Int) -> Int {
    let b = Array(b)
    if abs(a.count - b.count) > limit { return limit + 1 }
    if a.isEmpty || b.isEmpty { return max(a.count, b.count) }
    var beforePrevious = [Int](repeating: 0, count: b.count + 1)
    var previous = Array(0...b.count)
    var current = [Int](repeating: 0, count: b.count + 1)
    for i in 1...a.count {
        current[0] = i
        var rowMinimum = i
        for j in 1...b.count {
            let cost = a[i - 1] == b[j - 1] ? 0 : 1
            current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                current[j] = min(current[j], beforePrevious[j - 2] + 1)
            }
            rowMinimum = min(rowMinimum, current[j])
        }
        if rowMinimum > limit { return limit + 1 }
        (beforePrevious, previous, current) = (previous, current, beforePrevious)
    }
    return previous[b.count]
}
