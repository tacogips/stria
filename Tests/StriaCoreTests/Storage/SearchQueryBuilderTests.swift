import Foundation
@testable import StriaCore
import Testing

@Suite("SearchQueryBuilderTests") struct SearchQueryBuilderTests {
  @Test func quotingTrigramsAndSnippets() {
    #expect(SearchQueryBuilder.ftsMatchExpression(terms: ["a\"b", "foo"]) == "\"a\"\"b\" AND \"foo\"")
    let terms = SearchQueryBuilder.trigrams(question: "transformer transformer encoder")
    #expect(terms.trigrams.first == "tra")
    #expect(terms.trigrams.count == Set(terms.trigrams).count)
    #expect(SearchQueryBuilder.trigrams(question: String(repeating: "abcdef ", count: 20)).trigrams.count == 64)
    #expect(SearchQueryBuilder.trigrams(question: "AI 学習").shortTokens == ["AI", "学習"])
    #expect(SearchQueryBuilder.swiftSnippet(text: "before transformer after", term: "transformer").contains("[transformer]"))
    #expect(SearchQueryBuilder.likePattern(term: "a%_\\b") == "%a\\%\\_\\\\b%")
  }
}
