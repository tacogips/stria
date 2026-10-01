import StriaCore
import Testing

struct RedactorTests {
  @Test func replacesEverySecretOccurrence() {
    #expect(SecretRedactor.redact("token secret then secret", secrets: ["secret"]) == "token [REDACTED] then [REDACTED]")
  }

  @Test func truncatesAtCharacterBoundary() {
    #expect(SecretRedactor.truncate(String(repeating: "x", count: 3000)).count == 2000)
  }

  @Test func emptySecretsKeepText() {
    #expect(SecretRedactor.redact("unchanged", secrets: []) == "unchanged")
  }
}
