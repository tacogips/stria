import Foundation

struct LiveOCRService: OCRService {
  private let paths: StriaPaths
  private let environment: [String: String]
  private let platform: StriaPlatform
  private let credentialStore: any CredentialStore

  init(paths: StriaPaths, environment: [String: String], platform: StriaPlatform = .current,
       credentialStore: any CredentialStore = KeychainCredentialStore()) {
    self.paths = paths
    self.environment = environment
    self.platform = platform
    self.credentialStore = credentialStore
  }

  func recognize(_ request: OCRRequest) async throws -> OCRResult {
    if request.settings.vendor == KnownVendors.pdfTextLayer {
      return try await PDFTextLayerOCRService(paths: paths).recognize(request)
    }
    return try await GatewayOCRService(paths: paths, environment: environment, platform: platform, credentialStore: credentialStore).recognize(request)
  }
}

public extension StriaEnvironment {
  static func liveServices(paths: StriaPaths, config: StriaConfig) -> (any OCRService, any AgentService) {
    _ = config
    let environment = ProcessInfo.processInfo.environment
    return (LiveOCRService(paths: paths, environment: environment), GatewayAgentService(paths: paths, environment: environment))
  }

  static func live(
    paths: StriaPaths,
    config: StriaConfig,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    platform: StriaPlatform = .current, credentialStore: any CredentialStore = KeychainCredentialStore()
  ) -> StriaEnvironment {
    let services = (
      LiveOCRService(paths: paths, environment: environment, platform: platform, credentialStore: credentialStore),
      GatewayAgentService(paths: paths, environment: environment, platform: platform, credentialStore: credentialStore)
    )
    return StriaEnvironment(paths: paths, config: config, ocrService: services.0, agentService: services.1,
                            platform: platform, credentialStore: credentialStore)
  }
}
