import Foundation
import StriaCore

public actor FakeOCRService: OCRService {
  private var results: [String: Result<String, ServiceError>] = [:]
  private var defaultResult: Result<String, ServiceError>?
  private var delay: UInt64 = 0
  private var inFlight = 0
  public private(set) var maxInFlight = 0
  public private(set) var requests: [OCRRequest] = []

  public init() {}
  public func script(docId: String, page: Int, _ result: Result<String, ServiceError>) { results[key(docId, page)] = result }
  public func setDefault(_ result: Result<String, ServiceError>) { defaultResult = result }
  public func setDelay(nanoseconds: UInt64) { delay = nanoseconds }
  public func recognize(_ request: OCRRequest) async throws -> OCRResult {
    requests.append(request); inFlight += 1; maxInFlight = max(maxInFlight, inFlight)
    defer { inFlight -= 1 }
    if delay > 0 { try await Task.sleep(nanoseconds: delay) }
    let fallback = defaultResult ?? .success("text \(request.docId) p\(request.page)")
    switch results[key(request.docId, request.page)] ?? fallback {
    case .success(let text): return OCRResult(text: text)
    case .failure(let error): throw error
    }
  }
  private func key(_ docId: String, _ page: Int) -> String { "\(docId):\(page)" }
}
