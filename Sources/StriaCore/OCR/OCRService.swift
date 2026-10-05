import Foundation
/// What the OCR reply is expected to be: plain text (the local PDF text
/// layer) or a JSON object with `body` and `tags` (model vendors).
public enum OCRReplyFormat: Equatable, Sendable { case plain, json }

public struct OCRRequest: Equatable, Sendable {
  public var docId: String; public var page: Int; public var pngPath: URL; public var prompt: String; public var settings: ServiceSettings
  public var format: OCRReplyFormat
  public init(docId: String, page: Int, pngPath: URL, prompt: String, settings: ServiceSettings, format: OCRReplyFormat = .plain) {
    self.docId = docId; self.page = page; self.pngPath = pngPath; self.prompt = prompt; self.settings = settings
    self.format = format
  }
}
/// The service's reply: the model's raw text (JSON for `.json` requests).
public struct OCRResult: Equatable, Sendable {
  public var text: String
  public init(text: String) { self.text = text }
}
public protocol OCRService: Sendable { func recognize(_ request: OCRRequest) async throws -> OCRResult }
