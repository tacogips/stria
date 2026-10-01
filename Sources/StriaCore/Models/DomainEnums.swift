public enum ImageFormat: String, Codable, Equatable, Sendable { case heic, jpeg }
public enum OCRStatus: String, Codable, Equatable, Sendable { case pending, done, failed }
public enum ImportStatus: String, Codable, Equatable, Sendable { case rendering, ready }
public enum ChatScope: String, Codable, Equatable, Sendable { case page, nearby, document, library }
public enum ChatRole: String, Codable, Equatable, Sendable { case user, assistant }
public enum MessageStatus: String, Codable, Equatable, Sendable { case ok, error }
public enum RunKind: String, Codable, Equatable, Sendable { case ocr, ask }
public enum RunStatus: String, Codable, Equatable, Sendable { case ok, failed }
public enum SearchBackend: String, Codable, Equatable, Sendable { case fts5, like }
public enum MatchMode: String, Codable, Equatable, Sendable { case fts, like }
public enum DocumentOrder: String, Codable, Equatable, Sendable { case importedDescending, recents }
