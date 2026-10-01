import Foundation
@testable import StriaCore
import Testing

@Suite struct CLIJSONTests {
  private struct Example: Encodable {
    let zPath: String
    let aValue: JSONValue
  }

  @Test func successUsesCanonicalJSONSettings() throws {
    let output = try CLIJSON.success(Example(zPath: "/a/b", aValue: .null))
    #expect(output.exitCode == 0)
    #expect(output.stderr.isEmpty)
    #expect(output.stdout.contains("\"aValue\":null"))
    #expect(output.stdout.contains("\"zPath\":\"/a/b\""))
    #expect(output.stdout.range(of: "aValue")!.lowerBound < output.stdout.range(of: "zPath")!.lowerBound)
  }

  @Test func failureUsesStableEnvelopeAndExitCode() throws {
    let output = CLIJSON.failure(.usage("bad input"))
    #expect(output.stdout.isEmpty)
    #expect(output.exitCode == 2)
    let data = try #require(output.stderr.data(using: .utf8))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let error = try #require(object["error"] as? [String: String])
    #expect(error["code"] == "usageError")
    #expect(error["message"] == "bad input")
  }

  @Test func rejectsNonFiniteNumbersAsIOErrors() {
    do {
      _ = try CLIJSON.success(JSONValue.double(.nan))
      Issue.record("Expected non-finite JSON number to fail")
    } catch let error as StriaError {
      #expect(error.code == .ioError)
    } catch {
      Issue.record("Expected StriaError, got \(error)")
    }
  }

  @Test func failureEscapesSpecialMessageCharacters() throws {
    let message = "he said \"hi\" \\ and \nnewline"
    let output = CLIJSON.failure(.usage(message))
    let data = try #require(output.stderr.data(using: .utf8))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let error = try #require(object["error"] as? [String: String])
    #expect(error["message"] == message)
  }

  @Test func fallbackEnvelopeEscapesSpecialMessageCharacters() throws {
    let message = "he said \"hi\" \\ and \nnewline"
    let json = CLIJSON.fallbackEnvelope(code: .usageError, message: message)
    let data = try #require(json.data(using: .utf8))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let error = try #require(object["error"] as? [String: String])
    #expect(error["code"] == "usageError")
    #expect(error["message"] == message)
  }
}
