import Foundation

public struct SyncConfig: Codable, Equatable, Sendable {
  public var enabled: Bool
  public var documents: Bool
  public var ocr: Bool
  public var summaries: Bool
  public var chats: Bool
  public var folder: String?
  public var intervalMinutes: Int

  public init(enabled: Bool = false, documents: Bool = true, ocr: Bool = true, summaries: Bool = true,
              chats: Bool = true, folder: String? = nil, intervalMinutes: Int = 5) {
    self.enabled = enabled; self.documents = documents; self.ocr = ocr; self.summaries = summaries
    self.chats = chats; self.folder = folder; self.intervalMinutes = intervalMinutes
  }

  enum CodingKeys: String, CodingKey { case enabled, documents, ocr, summaries, chats, folder, intervalMinutes }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
              documents: try c.decodeIfPresent(Bool.self, forKey: .documents) ?? true,
              ocr: try c.decodeIfPresent(Bool.self, forKey: .ocr) ?? true,
              summaries: try c.decodeIfPresent(Bool.self, forKey: .summaries) ?? true,
              chats: try c.decodeIfPresent(Bool.self, forKey: .chats) ?? true,
              folder: try c.decodeIfPresent(String.self, forKey: .folder),
              intervalMinutes: try c.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? 5)
  }

  public func validate() throws(StriaError) {
    guard (1...120).contains(intervalMinutes) else { throw .config("sync.intervalMinutes must be in 1...120") }
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(enabled, forKey: .enabled); try c.encode(documents, forKey: .documents)
    try c.encode(ocr, forKey: .ocr); try c.encode(summaries, forKey: .summaries); try c.encode(chats, forKey: .chats)
    try c.encode(folder, forKey: .folder); try c.encode(intervalMinutes, forKey: .intervalMinutes)
  }
}
