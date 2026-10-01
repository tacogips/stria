import Foundation

public struct PageImageResult: Sendable, Equatable {
  public let docId: String
  public let page: Int
  public let path: URL
  public let width: Int
  public let height: Int
  public let cached: Bool

  public init(docId: String, page: Int, path: URL, width: Int, height: Int, cached: Bool) {
    self.docId = docId
    self.page = page
    self.path = path
    self.width = width
    self.height = height
    self.cached = cached
  }
}
