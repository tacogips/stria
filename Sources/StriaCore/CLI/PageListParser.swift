public enum PageListParser {
  public static func parse(_ text: String, pageCount: Int) throws(StriaError) -> [Int] {
    var pages = Set<Int>()
    for token in text.components(separatedBy: ",") {
      guard !token.isEmpty else { throw .usage("Empty page-list element") }
      let bounds = token.components(separatedBy: "-")
      guard bounds.count == 1 || bounds.count == 2,
            let first = positivePage(bounds[0]),
            let last = bounds.count == 1 ? first : positivePage(bounds[1]) else {
        throw .usage("Invalid page-list token '\(token)'")
      }
      guard first <= last else { throw .usage("Reversed page range '\(token)'") }
      guard last <= pageCount else { throw .usage("Page-list token '\(token)' exceeds page count \(pageCount)") }
      pages.formUnion(first...last)
    }
    return pages.sorted()
  }

  private static func positivePage(_ value: String) -> Int? {
    guard !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }), let page = Int(value), page > 0 else { return nil }
    return page
  }
}
