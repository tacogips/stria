import Foundation
import StriaCore

public actor FakeOCRService: OCRService {
  private var results: [String: Result<String, ServiceError>] = [:]
  /// Raw replies returned (in order, unwrapped) before `results` applies.
  private var rawReplies: [String: [String]] = [:]
  private var defaultResult: Result<String, ServiceError>?
  private var delay: UInt64 = 0
  private var inFlight = 0
  public private(set) var maxInFlight = 0
  public private(set) var requests: [OCRRequest] = []

  public init() {}
  public func script(docId: String, page: Int, _ result: Result<String, ServiceError>) { results[key(docId, page)] = result }
  /// Replies sent exactly as given, one per call (for malformed-JSON tests).
  public func scriptRawReplies(docId: String, page: Int, _ replies: [String]) { rawReplies[key(docId, page)] = replies }
  public func setDefault(_ result: Result<String, ServiceError>) { defaultResult = result }
  public func setDelay(nanoseconds: UInt64) { delay = nanoseconds }
  public func recognize(_ request: OCRRequest) async throws -> OCRResult {
    requests.append(request); inFlight += 1; maxInFlight = max(maxInFlight, inFlight)
    defer { inFlight -= 1 }
    if delay > 0 { try await Task.sleep(nanoseconds: delay) }
    if var queue = rawReplies[key(request.docId, request.page)], !queue.isEmpty {
      let reply = queue.removeFirst()
      rawReplies[key(request.docId, request.page)] = queue
      return OCRResult(text: reply)
    }
    let fallback = defaultResult ?? .success("text \(request.docId) p\(request.page)")
    switch results[key(request.docId, request.page)] ?? fallback {
    case .success(let text):
      // Model vendors must answer JSON; scripted plain text becomes its body.
      guard request.format == .json, !text.hasPrefix("{") else { return OCRResult(text: text) }
      let body = String(bytes: try JSONEncoder().encode(text), encoding: .utf8) ?? "\"\""
      return OCRResult(text: #"{"body": \#(body), "tags": []}"#)
    case .failure(let error): throw error
    }
  }
  private func key(_ docId: String, _ page: Int) -> String { "\(docId):\(page)" }
}
