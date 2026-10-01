@testable import StriaCore
import Testing

struct PreflightTests {
  @Test func rejectsUnknownVendor() throws {
    #expect(throws: ServiceError.unavailable("unknown vendor nope")) {
      try GatewayPreflight.check(.init(vendor: "nope", model: nil, apiKeyEnvironment: nil), environment: [:])
    }
  }

  @Test func validatesAPISettingsAndNamesMissingVariable() throws {
    #expect(throws: ServiceError.unavailable("model is required for vendor anthropic")) {
      try GatewayPreflight.check(.init(vendor: "anthropic", model: nil, apiKeyEnvironment: "KEY"), environment: ["KEY": "secret"])
    }
    #expect(throws: ServiceError.unavailable("apiKeyEnvironment is required for vendor anthropic")) {
      try GatewayPreflight.check(.init(vendor: "anthropic", model: "m", apiKeyEnvironment: nil), environment: [:])
    }
    #expect(throws: ServiceError.unavailable("environment variable ANTHROPIC_API_KEY is not set")) {
      try GatewayPreflight.check(.init(vendor: "anthropic", model: "m", apiKeyEnvironment: "ANTHROPIC_API_KEY"), environment: [:])
    }
  }

  @Test func acceptsConfiguredAPIVendorAndCLIVendor() throws {
    let api = try GatewayPreflight.check(
      .init(vendor: "anthropic", model: "m", apiKeyEnvironment: "ANTHROPIC_API_KEY"),
      environment: ["ANTHROPIC_API_KEY": "sk-test-123"]
    )
    #expect(api.secretValue == "sk-test-123")
    let cli = try GatewayPreflight.check(.init(vendor: "claude-code", model: nil, apiKeyEnvironment: nil), environment: [:])
    #expect(cli.secretValue == nil)
  }

  @Test func checksCursorAPIBeforeModelAndKey() throws {
    #expect(throws: ServiceError.unavailable("vendor cursor-api does not support image input")) {
      try GatewayPreflight.check(.init(vendor: "cursor-api", model: nil, apiKeyEnvironment: nil), environment: [:])
    }
  }

  @Test func configuredCLIKeyMustBePresent() throws {
    #expect(throws: ServiceError.unavailable("environment variable FOO_KEY is not set")) {
      try GatewayPreflight.check(.init(vendor: "claude-code", model: nil, apiKeyEnvironment: "FOO_KEY"), environment: [:])
    }
  }
}
