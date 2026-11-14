import StriaCore
import Testing

@Suite struct PageListTests {
  @Test func parsesSortedUniquePages() throws {
    #expect(try PageListParser.parse("1,3-5", pageCount: 5) == [1, 3, 4, 5])
    #expect(try PageListParser.parse("3,1,1", pageCount: 5) == [1, 3])
  }

  @Test func rejectsInvalidPageTokens() {
    for (text, count) in [("5-3", 5), ("0", 5), ("6", 5), ("1,,2", 5)] {
      do {
        _ = try PageListParser.parse(text, pageCount: count)
        Issue.record("Expected usageError for \(text)")
      } catch {
        #expect(error.code == .usageError)
      }
    }
  }
}
