import Foundation
import PDFKit

public enum OutlineExtractor {
  public static func extract(from document: PDFDocument) -> [OutlineNode] {
    guard let root = document.outlineRoot else { return [] }
    return (0..<root.numberOfChildren).compactMap { index in
      root.child(at: index).map { node($0, document: document) }
    }
  }

  public static func encodeJSON(_ nodes: [OutlineNode]) -> String {
    guard let data = try? JSONEncoder().encode(nodes), let json = String(data: data, encoding: .utf8) else { return "[]" }
    return json
  }

  public static func decodeJSON(_ json: String) -> [OutlineNode] {
    guard let data = json.data(using: .utf8), let nodes = try? JSONDecoder().decode([OutlineNode].self, from: data) else { return [] }
    return nodes
  }

  private static func node(_ outline: PDFOutline, document: PDFDocument) -> OutlineNode {
    let page = outline.destination?.page.map { document.index(for: $0) + 1 }
    let children = (0..<outline.numberOfChildren).compactMap { index in
      outline.child(at: index).map { node($0, document: document) }
    }
    return OutlineNode(title: outline.label ?? "", page: page, children: children)
  }
}
