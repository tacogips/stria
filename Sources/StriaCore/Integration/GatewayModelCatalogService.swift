import AgentGateway
import AgentGatewayAppCore
import Foundation

/// Fetches the live model list of an API vendor through agent-gateway. CLI
/// vendors have no listing and are rejected before any request.
public enum GatewayModelCatalogService {
  public static func models(vendor: String, apiKeyEnvironment: String?,
                            environment: [String: String] = ProcessInfo.processInfo.environment) async throws -> [String] {
    guard let gatewayVendor = GatewayVendor(rawValue: vendor), !gatewayVendor.isCLI, gatewayVendor != .cursorAPI else {
      throw ServiceError.unavailable("\(vendor) does not list models; type the model id")
    }
    guard let name = apiKeyEnvironment, !name.isEmpty else {
      throw ServiceError.unavailable("set the API key environment variable name first")
    }
    guard let value = environment[name], !value.isEmpty else {
      throw ServiceError.unavailable("environment variable \(name) is not set in this app's environment")
    }
    do {
      let result = try await ProductionGatewayExecutor(environment: environment)
        .models(GatewayModelCatalogParams(vendor: gatewayVendor, apiKeyEnvironment: name))
      return result.models.map(\.modelId).sorted()
    } catch {
      throw ServiceError.failed(SecretRedactor.redact(String(describing: error), secrets: [value]))
    }
  }
}
