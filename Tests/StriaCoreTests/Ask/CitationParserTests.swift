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
}
