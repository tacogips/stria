import StriaCore
import Testing

@Suite("CitationParserTests") struct CitationParserTests {
  @Test func extractsMarkersInTextOrderAndIgnoresInvalidForms() {
    let text = "see [0123456789abcdef p.3] and [0123456789abcdef p.12] [xyz p.3]"
    let markers = CitationParser.markers(in: text)
    #expect(markers.map(\.docId) == ["0123456789abcdef", "0123456789abcdef"])
    #expect(markers.map(\.page) == [3, 12])
    #expect(String(text[markers[0].range]) == "[0123456789abcdef p.3]")
  }

  @Test func toleratesWhitespaceAndPicksCitedContextPages() {
    let text = "[0123456789abcdef p. 3] then [0123456789abcdef  p.3] and [fedcba9876543210 p.9]"
    #expect(CitationParser.markers(in: text).map(\.page) == [3, 3, 9])
    let context = [Citation(docId: "0123456789abcdef", title: "t", page: 3, imagePath: "/a"),
                   Citation(docId: "0123456789abcdef", title: "t", page: 4, imagePath: "/b")]
    #expect(AskResponse.citedPages(in: text, contextPages: context).map(\.page) == [3])
    #expect(AskResponse.citedPages(in: "no markers", contextPages: context).map(\.page) == [3, 4])
  }
}
