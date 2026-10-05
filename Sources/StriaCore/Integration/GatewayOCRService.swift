import Foundation

public struct GatewayOCRService: OCRService {
  private let paths: StriaPaths
  private let credentials: CredentialEnvironment
  let runner: GatewayPromptRunner

  public init(paths: StriaPaths, environment: [String: String], platform: StriaPlatform = .current,
              credentialStore: any CredentialStore = KeychainCredentialStore()) {
    self.init(paths: paths, environment: environment, runner: GatewayPromptRunner(), platform: platform, credentialStore: credentialStore)
  }

  init(paths: StriaPaths, environment: [String: String], runner: GatewayPromptRunner, platform: StriaPlatform = .current,
       credentialStore: any CredentialStore = KeychainCredentialStore()) {
    self.paths = paths
    credentials = CredentialEnvironment(environment: environment, platform: platform, store: credentialStore)
    self.runner = runner
  }

  public func recognize(_ request: OCRRequest) async throws -> OCRResult {
    guard KnownVendors.isAvailableOnThisPlatform(request.settings.vendor, platform: credentials.platform) else {
      throw ServiceError.unavailable(KnownVendors.platformUnavailableReason)
    }
    let environment = try credentials.merged(settings: request.settings)
    let preflight = try GatewayPreflight.check(request.settings, environment: environment, platform: credentials.platform)
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
