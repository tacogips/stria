@testable import StriaCore
import Testing

struct PreflightTests {
  private struct UnavailableCase {
    let settings: ServiceSettings
    let environment: [String: String]
    let expectedMessage: String
  }

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
    let cli = try GatewayPreflight.check(.init(vendor: "claude-code", model: "m", apiKeyEnvironment: nil), environment: [:])
    #expect(cli.secretValue == nil)
  }

  @Test func checksCursorAPIBeforeModelAndKey() throws {
    #expect(throws: ServiceError.unavailable("vendor cursor-api does not support image input")) {
      try GatewayPreflight.check(.init(vendor: "cursor-api", model: nil, apiKeyEnvironment: nil), environment: [:])
    }
  }

  @Test func configuredCLIKeyMustBePresent() throws {
    #expect(throws: ServiceError.unavailable("environment variable FOO_KEY is not set")) {
      try GatewayPreflight.check(.init(vendor: "claude-code", model: "m", apiKeyEnvironment: "FOO_KEY"), environment: [:])
    }
  }

  @Test func unavailableErrorsNeverRevealConfiguredSecrets() throws {
    let secret = "sk-SECRET-123"
    let cases = [
      UnavailableCase(settings: .init(vendor: "nope", model: nil, apiKeyEnvironment: nil), environment: [:], expectedMessage: "unknown vendor nope"),
      UnavailableCase(settings: .init(vendor: "anthropic", model: nil, apiKeyEnvironment: "KEY"), environment: ["KEY": secret], expectedMessage: "model is required for vendor anthropic"),
      UnavailableCase(settings: .init(vendor: "anthropic", model: "m", apiKeyEnvironment: nil), environment: [:], expectedMessage: "apiKeyEnvironment is required for vendor anthropic"),
      UnavailableCase(settings: .init(vendor: "anthropic", model: "m", apiKeyEnvironment: "ANTHROPIC_API_KEY"), environment: [:], expectedMessage: "environment variable ANTHROPIC_API_KEY is not set"),
      UnavailableCase(settings: .init(vendor: "cursor-api", model: "m", apiKeyEnvironment: "CURSOR_API_KEY"), environment: ["CURSOR_API_KEY": secret], expectedMessage: "vendor cursor-api does not support image input"),
      UnavailableCase(settings: .init(vendor: "claude-code", model: "m", apiKeyEnvironment: "FOO_KEY"), environment: [:], expectedMessage: "environment variable FOO_KEY is not set"),
      UnavailableCase(settings: .init(vendor: "codex", model: nil, apiKeyEnvironment: nil), environment: [:], expectedMessage: "model is required for vendor codex")
    ]

    for testCase in cases {
      do {
        _ = try GatewayPreflight.check(testCase.settings, environment: testCase.environment)
        Issue.record("Expected unavailable for vendor \(testCase.settings.vendor)")
      } catch let error {
        #expect(error == .unavailable(testCase.expectedMessage))
        #expect(!String(describing: error).contains(secret))
      }
    }
  }

  @Test func cliVendorWithoutModelIsUnavailableNotFailed() {
    let settings = ServiceSettings(vendor: "claude-code", model: nil, apiKeyEnvironment: nil)
    #expect(throws: ServiceError.unavailable("model is required for vendor claude-code")) {
      try GatewayPreflight.check(settings, environment: [:])
    }
  }
}
