import Foundation
public struct OCRRequest: Equatable, Sendable {
  public var docId: String; public var page: Int; public var pngPath: URL; public var prompt: String; public var settings: ServiceSettings
  public init(docId: String, page: Int, pngPath: URL, prompt: String, settings: ServiceSettings) {
    self.docId = docId; self.page = page; self.pngPath = pngPath; self.prompt = prompt; self.settings = settings
  }
}
public struct OCRResult: Equatable, Sendable {
  public var text: String
  public init(text: String) { self.text = text }
}
public protocol OCRService: Sendable { func recognize(_ request: OCRRequest) async throws -> OCRResult }
