import GRDB

/// FTS5 tokenizer for Vietnamese, and everything else. `unicode61 remove_diacritics 2` strips tone marks
/// (ở → o, Nguyễn → nguyen) but keeps đ as its own letter, so this wrapper folds đ to d. It runs on both the indexed
/// text and the query, so "duong" finds "đường", while the stored text keeps its đ.
///
/// Every connection that touches the search table needs it registered (`AppDatabase.configuration`), including the
/// share extension's, or writes fail with "no such tokenizer".
final class StatemonoTokenizer: FTS5WrapperTokenizer {
    static let name = "statemono"
    let wrappedTokenizer: any FTS5Tokenizer

    init(db: Database, arguments: [String]) throws {
        wrappedTokenizer = try db.makeTokenizer(.unicode61(diacritics: .remove))
    }

    func accept(token: String, flags: FTS5TokenFlags, for tokenization: FTS5Tokenization, tokenCallback: FTS5WrapperTokenCallback) throws {
        // unicode61 has already lowercased Đ to đ.
        guard token.contains("đ") else { return try tokenCallback(token, flags) }
        try tokenCallback(token.replacingOccurrences(of: "đ", with: "d"), flags)
    }
}
