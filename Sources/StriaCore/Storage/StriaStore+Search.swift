import Foundation

extension StriaStore {
  public func search(text: String, documentId: String?, limit: Int) throws -> SearchOutcome {
    let normalized = SearchQueryBuilder.normalize(text)
    let terms = SearchQueryBuilder.terms(normalized)
    guard !terms.isEmpty else { throw StriaError.usage("Search query must not be empty") }
    guard (1...100).contains(limit) else { throw StriaError.usage("Search limit must be between 1 and 100") }
    let mode = SearchQueryBuilder.mode(backend: searchBackend, terms: terms)
    return SearchOutcome(matchMode: mode, hits: try mode == .fts
      ? ftsSearch(terms: terms, documentId: documentId, limit: limit)
      : likeSearch(terms: terms, documentId: documentId, limit: limit))
  }

  public func fuzzyRetrieve(question: String, documentId: String?, limit: Int) throws -> [PageRef] {
    let query = SearchQueryBuilder.trigrams(question: question)
    if query.trigrams.isEmpty && query.shortTokens.isEmpty { return [] }
    guard (1...100).contains(limit) else { throw StriaError.usage("Search limit must be between 1 and 100") }
    if query.trigrams.isEmpty { return try fuzzyShortLike(tokens: query.shortTokens, documentId: documentId, limit: limit) }
    if searchBackend == .fts5 {
      let expression = SearchQueryBuilder.ftsMatchExpression(terms: query.trigrams).replacingOccurrences(of: " AND ", with: " OR ")
      let statement = try database.prepare("""
        SELECT document_id,page_number FROM page_fts WHERE page_fts MATCH ?
        \(documentId == nil ? "" : "AND document_id=?") ORDER BY bm25(page_fts) LIMIT ?
        """)
      try statement.bind(expression, at: 1)
      var index: Int32 = 2
      if let documentId { try statement.bind(documentId, at: index); index += 1 }
      try statement.bind(limit, at: index)
      var refs: [PageRef] = []
      while try statement.step() {
        if let doc = statement.string(0), let page = Int(statement.string(1) ?? "") { refs.append(PageRef(docId: doc, page: page)) }
      }
      return refs
    }
    return try fuzzyLike(tokens: query.trigrams, documentId: documentId, limit: limit)
  }

  private func ftsSearch(terms: [String], documentId: String?, limit: Int) throws -> [SearchHit] {
    let statement = try database.prepare("""
      SELECT documents.id,documents.title,CAST(page_fts.page_number AS INTEGER),snippet(page_fts,2,'[',']','...',16),-bm25(page_fts)
      FROM page_fts JOIN documents ON documents.id=page_fts.document_id WHERE page_fts MATCH ?
      \(documentId == nil ? "" : "AND page_fts.document_id=?") ORDER BY bm25(page_fts) LIMIT ?
      """)
    try statement.bind(SearchQueryBuilder.ftsMatchExpression(terms: terms), at: 1)
    var index: Int32 = 2
    if let documentId { try statement.bind(documentId, at: index); index += 1 }
    try statement.bind(limit, at: index)
    var hits: [SearchHit] = []
    while try statement.step() {
      guard let doc = statement.string(0), let title = statement.string(1), let snippet = statement.string(3) else { continue }
      hits.append(SearchHit(docId: doc, title: title, page: statement.int(2), snippet: snippet,
                            score: (statement.double(4) * 1_000_000).rounded() / 1_000_000))
    }
    return hits
  }

  /// LIKE mode ranks pages by how many times the terms occur on the page
  /// (`lower()` keeps the count consistent with LIKE's ASCII case folding).
  private func likeSearch(terms: [String], documentId: String?, limit: Int) throws -> [SearchHit] {
    let predicates = Array(repeating: "p.search_text LIKE ? ESCAPE '\\'", count: terms.count).joined(separator: " AND ")
    let occurrences = Array(repeating: "(LENGTH(p.search_text)-LENGTH(REPLACE(lower(p.search_text),lower(?),'')))/LENGTH(?)",
                            count: terms.count).joined(separator: "+")
    let statement = try database.prepare("""
      SELECT d.id,d.title,p.page_number,p.search_text,\(occurrences) AS score
      FROM pages p JOIN documents d ON d.id=p.document_id
      WHERE \(predicates) \(documentId == nil ? "" : "AND p.document_id=?")
      ORDER BY score DESC,p.document_id,p.page_number LIMIT ?
      """)
    var index: Int32 = 1
    for term in terms {
      try statement.bind(term, at: index)
      try statement.bind(term, at: index + 1)
      index += 2
    }
    for term in terms { try statement.bind(SearchQueryBuilder.likePattern(term: term), at: index); index += 1 }
    if let documentId { try statement.bind(documentId, at: index); index += 1 }
    try statement.bind(limit, at: index)
    var hits: [SearchHit] = []
    while try statement.step() {
      guard let doc = statement.string(0), let title = statement.string(1), let text = statement.string(3) else { continue }
      hits.append(SearchHit(docId: doc, title: title, page: statement.int(2),
                            snippet: SearchQueryBuilder.swiftSnippet(text: text, term: terms[0]), score: statement.double(4)))
    }
    return hits
  }

  private func fuzzyShortLike(tokens: [String], documentId: String?, limit: Int) throws -> [PageRef] {
    let predicates = tokens.map { _ in "search_text LIKE ? ESCAPE '\\'" }.joined(separator: " AND ")
    let statement = try database.prepare("""
      SELECT document_id,page_number FROM pages WHERE search_text IS NOT NULL AND \(predicates)
      \(documentId == nil ? "" : "AND document_id=?") ORDER BY document_id,page_number LIMIT ?
      """)
    var index: Int32 = 1
    for token in tokens { try statement.bind(SearchQueryBuilder.likePattern(term: token), at: index); index += 1 }
    if let documentId { try statement.bind(documentId, at: index); index += 1 }
    try statement.bind(limit, at: index)
    var refs: [PageRef] = []
    while try statement.step() {
      if let doc = statement.string(0) { refs.append(PageRef(docId: doc, page: statement.int(1))) }
    }
    return refs
  }

  private func fuzzyLike(tokens: [String], documentId: String?, limit: Int) throws -> [PageRef] {
    let clauses = tokens.map { _ in "(search_text LIKE ? ESCAPE '\\')" }.joined(separator: "+")
    let statement = try database.prepare("""
      SELECT document_id,page_number,\(clauses) AS score FROM pages
      WHERE search_text IS NOT NULL \(documentId == nil ? "" : "AND document_id=?")
      GROUP BY document_id,page_number HAVING score >= 1
      ORDER BY score DESC,document_id,page_number LIMIT ?
      """)
    var index: Int32 = 1
    for token in tokens { try statement.bind(SearchQueryBuilder.likePattern(term: token), at: index); index += 1 }
    if let documentId { try statement.bind(documentId, at: index); index += 1 }
    try statement.bind(limit, at: index)
    var refs: [PageRef] = []
    while try statement.step() {
      if let doc = statement.string(0) { refs.append(PageRef(docId: doc, page: statement.int(1))) }
    }
    return refs
  }
}
