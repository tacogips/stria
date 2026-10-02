import AgentGateway
import Foundation

struct PreflightResult: Equatable, Sendable {
  let vendor: GatewayVendor
  let secretValue: String?
}

enum GatewayPreflight {
  static func check(_ settings: ServiceSettings, environment: [String: String]) throws(ServiceError) -> PreflightResult {
    guard let vendor = GatewayVendor(rawValue: settings.vendor) else {
      throw .unavailable("unknown vendor \(settings.vendor)")
    }
    guard vendor != .cursorAPI else {
      throw .unavailable("vendor cursor-api does not support image input")
    }
    // agent-gateway rejects a session without a model for every vendor, CLI
    // vendors included, so a null model is a config problem, not a call failure.
    if settings.model == nil {
      throw .unavailable("model is required for vendor \(settings.vendor)")
    }
    if KnownVendors.apiKeyVendors.contains(settings.vendor), settings.apiKeyEnvironment == nil {
      throw .unavailable("apiKeyEnvironment is required for vendor \(settings.vendor)")
    }
    if let name = settings.apiKeyEnvironment {
      guard let value = environment[name], !value.isEmpty else {
        throw .unavailable("environment variable \(name) is not set")
      }
      return PreflightResult(vendor: vendor, secretValue: value)
    }
    return PreflightResult(vendor: vendor, secretValue: nil)
  }
}
