import Foundation

public struct GatewayOCRService: OCRService {
  private let paths: StriaPaths
  private let environment: [String: String]

  public init(paths: StriaPaths, environment: [String: String]) {
    self.paths = paths
    self.environment = environment
  }

  public func recognize(_ request: OCRRequest) async throws -> OCRResult {
    let preflight = try GatewayPreflight.check(request.settings, environment: environment)
    let text = try await GatewayPromptRunner().run(
      settings: request.settings,
      systemPrompt: nil,
      parts: GatewayPromptParts.ocrParts(request),
      cwd: paths.cache,
      environment: environment,
      secretValue: preflight.secretValue
    )
    if let reason = GatewayOCRReplyCheck.rejectionReason(for: text) {
      throw ServiceError.failed(reason)
    }
    return OCRResult(text: text)
  }
}
