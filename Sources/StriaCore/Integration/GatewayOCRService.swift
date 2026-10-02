import Foundation

public struct GatewayOCRService: OCRService {
  private let paths: StriaPaths
  private let environment: [String: String]
  let runner: GatewayPromptRunner

  public init(paths: StriaPaths, environment: [String: String]) {
    self.init(paths: paths, environment: environment, runner: GatewayPromptRunner())
  }

  init(paths: StriaPaths, environment: [String: String], runner: GatewayPromptRunner) {
    self.paths = paths
    self.environment = environment
    self.runner = runner
  }

  public func recognize(_ request: OCRRequest) async throws -> OCRResult {
    let preflight = try GatewayPreflight.check(request.settings, environment: environment)
    let text = try await runner.run(
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
    if OCRTextPostProcessor.clean(text) == OCRDefaults.noTextSentinel { return OCRResult(text: "") }
    return OCRResult(text: text)
  }
}
