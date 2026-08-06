import Foundation

/// Tag normalization rules from SPEC §5.3: sort names fall back to
/// casefolded, diacritics-stripped values with leading articles moved aside.
public enum Normalize {
    /// Articles stripped from the head of a name when no explicit SORT tag exists.
    private static let leadingArticles = ["the ", "a ", "an "]

    /// Produces a sort key: casefold, strip diacritics, drop a leading article.
    /// "The Beatles" → "beatles", "Björk" → "bjork", "Кино" → "кино".
    public static func sortName(for name: String) -> String {
        var result =
            name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for article in leadingArticles where result.hasPrefix(article) {
            result = String(result.dropFirst(article.count))
                .trimmingCharacters(in: .whitespaces)
            break
        }
        return result
    }
}
