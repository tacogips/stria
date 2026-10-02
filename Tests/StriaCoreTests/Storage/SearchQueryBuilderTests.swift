import Foundation
@testable import StriaCore
import Testing

@Suite("SearchQueryBuilderTests") struct SearchQueryBuilderTests {
  @Test func quotingTrigramsAndSnippets() {
    #expect(SearchQueryBuilder.ftsMatchExpression(terms: ["a\"b", "foo"]) == "\"a\"\"b\" AND \"foo\"")
    let terms = SearchQueryBuilder.trigrams(question: "transformer transformer encoder")
    #expect(terms.trigrams.first == "tra")
    #expect(terms.trigrams.count == Set(terms.trigrams).count)
    #expect(SearchQueryBuilder.trigrams(question: String(repeating: "abcdef ", count: 20)).trigrams == ["abc", "bcd", "cde", "def"])
    let scalars = (0x4E00...0x4E4F).compactMap(UnicodeScalar.init)
    let capped = SearchQueryBuilder.trigrams(question: String(String.UnicodeScalarView(scalars))).trigrams
    #expect(capped.count == 64)
    #expect(capped.first == String(String.UnicodeScalarView(scalars[0...2])))
    #expect(capped.last == String(String.UnicodeScalarView(scalars[63...65])))
    #expect(Set(capped).count == 64)
    #expect(SearchQueryBuilder.trigrams(question: "AI 学習").shortTokens == ["AI", "学習"])
    #expect(SearchQueryBuilder.swiftSnippet(text: "before transformer after", term: "transformer").contains("[transformer]"))
    let accentSnippet = SearchQueryBuilder.swiftSnippet(text: "café then cafe", term: "cafe")
    #expect(accentSnippet.contains("[cafe]"))
    #expect(!accentSnippet.contains("[café]"))
    #expect(SearchQueryBuilder.likePattern(term: "a%_\\b") == "%a\\%\\_\\\\b%")
  }

  @Test func stopWordsDoNotContributeTrigrams() {
    let terms = SearchQueryBuilder.trigrams(question: "What does the document say about zebra?")
    #expect(terms.trigrams == ["zeb", "ebr", "bra"])
    #expect(SearchQueryBuilder.trigrams(question: "What is this?").trigrams.isEmpty)
    let japanese = SearchQueryBuilder.trigrams(question: "機械学習とは")
    #expect(japanese.trigrams.first == "機械学")
  }
}
