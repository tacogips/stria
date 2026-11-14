import Foundation
public struct OCRProgress: Codable, Equatable, Sendable {
  public var done: Int; public var failed: Int; public var pending: Int; public var total: Int
  public init(done: Int, failed: Int, pending: Int, total: Int) { self.done = done; self.failed = failed; self.pending = pending; self.total = total }
}
public enum ImportOCRStatus: String, Codable, Equatable, Sendable { case completed, partial, skipped, unavailable }
public struct ImportOCROutcome: Codable, Equatable, Sendable {
  public var status: ImportOCRStatus; public var reason: String?; public var done: Int; public var failed: Int; public var pending: Int
  public init(status: ImportOCRStatus, reason: String?, done: Int, failed: Int, pending: Int) {
    self.status = status; self.reason = reason; self.done = done; self.failed = failed; self.pending = pending
  }
}
public struct ImportResult: Codable, Equatable, Sendable {
  public var alreadyImported: Bool; public var document: DocumentSummary; public var ocr: ImportOCROutcome
  public init(alreadyImported: Bool, document: DocumentSummary, ocr: ImportOCROutcome) { self.alreadyImported = alreadyImported; self.document = document; self.ocr = ocr }
}
public enum ImportEvent: Equatable, Sendable {
  case copied(docId: String), rendered(page: Int, total: Int), ocr(OCRProgress), finished(ImportResult), failed(StriaError)
}
public enum OCRSelection: Equatable, Sendable { case pending, pendingAndFailed, pages([Int]) }
public struct OCRFailure: Codable, Equatable, Sendable {
  public var page: Int; public var error: String
  public init(page: Int, error: String) { self.page = page; self.error = error }
}
public struct OCRRunSummary: Codable, Equatable, Sendable {
  public var docId: String; public var processed: [Int]; public var done: Int; public var failed: Int; public var pending: Int
  public var failures: [OCRFailure]; public var unavailableReason: String?
  public init(docId: String, processed: [Int], done: Int, failed: Int, pending: Int, failures: [OCRFailure], unavailableReason: String?) {
    self.docId = docId; self.processed = processed; self.done = done; self.failed = failed; self.pending = pending
    self.failures = failures; self.unavailableReason = unavailableReason
  }
}
public enum OCREvent: Equatable, Sendable { case progress(OCRProgress), finished(OCRRunSummary), failed(StriaError) }
