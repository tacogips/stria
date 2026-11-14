import Foundation
@testable import StriaCore
import Testing

/// Records the backoff the coordinator asked for.
final class DelayRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [Int] = []
  var attempts: [Int] { lock.lock(); defer { lock.unlock() }; return values }
  func record(_ attempt: Int) -> Duration {
    lock.lock(); values.append(attempt); lock.unlock()
    return .zero
  }
}

private func makeLibrary(paths: StriaPaths, ocr: FakeOCRService, retries: Int, delays: DelayRecorder) throws -> (StriaLibrary, URL) {
  let source = paths.root.appendingPathComponent("json.pdf")
  try SamplePDFFactory.makePDF(at: source, pages: ["one", "two"])
  var config = StriaConfig.testing
  config.ocr.formatRetries = retries
  config.ocr.concurrency = 1
  let environment = StriaEnvironment(paths: paths, config: config, ocrService: ocr, agentService: FakeAgentService(),
                                     ocrRetryDelay: { delays.record($0) })
  return (try StriaLibrary.open(environment: environment), source)
}

@Suite struct OCRJSONReplyTests {
  @Test func parserAcceptsTheObjectAndNormalizesTags() throws {
    let reply = """
      ```json
      {"body": "第1条 契約\\n本文", "tags": [" 契約 ", "#山田太郎", "契約", "", "ＡＢＣ", "abc"]}
      ```
      """
    let parsed = try OCRReplyParser.parse(reply)
    #expect(parsed.body == "第1条 契約\n本文")
    #expect(parsed.tags == ["契約", "山田太郎", "ＡＢＣ"])
    #expect(try OCRReplyParser.parse(#"{"body": "[NO TEXT]", "tags": []}"#) == ParsedOCRReply(body: "", tags: []))
    let many = (0..<60).map { "tag\($0)" }
    #expect(OCRReplyParser.normalizedTags(many).count == OCRReplyParser.maxTags)
    #expect(OCRReplyParser.normalizedTags([String(repeating: "x", count: 200)]).first?.count == OCRReplyParser.maxTagLength)
  }

  @Test func parserRejectsOtherShapes() {
    let cases: [(String, String)] = [
      ("plain transcription", "not a JSON object"),
      ("{body: nope}", "not valid JSON"),
      (#"{"text": "x", "tags": []}"#, "no string \"body\""),
      (#"{"body": "x"}"#, "no \"tags\" array"),
      (#"{"body": "x", "tags": "a, b"}"#, "no \"tags\" array"),
      (#"{"body": "x", "tags": [1, 2]}"#, "no \"tags\" array")
    ]
    for (reply, reason) in cases {
      do {
        _ = try OCRReplyParser.parse(reply)
        Issue.record("Expected a format error for \(reply)")
      } catch {
        #expect(error.message.contains(reason), "\(reply): \(error.message)")
      }
    }
  }

  @Test func malformedRepliesAreRetriedWithBackoffThenStored() async throws {
    try await withTestDataRoot { paths in
      let ocr = FakeOCRService()
      let delays = DelayRecorder()
      let (library, source) = try makeLibrary(paths: paths, ocr: ocr, retries: 2, delays: delays)
      let id = try await library.importDocument(at: source, runOCR: false).document.id
      await ocr.scriptRawReplies(docId: id, page: 1, [
        "Here is the text: one",
        #"{"body": "one"}"#,
        #"{"body": "one", "tags": ["Alice", "Kickoff meeting", "alice"]}"#
      ])
      let summary = try await library.runOCR(documentId: id, selection: .pages([1]))
      #expect(summary.failures.isEmpty)
      #expect(delays.attempts == [1, 2])
      let requests = await ocr.requests
      #expect(requests.count == 3)
      #expect(requests.allSatisfy { $0.format == .json })
      #expect(requests.first?.prompt.hasSuffix(OCRDefaults.jsonFormatInstruction) == true)
      #expect(requests.first?.prompt.hasPrefix(OCRDefaults.prompt) == true)
      let page = try #require(try await library.store.pageInfo(documentId: id, page: 1))
      #expect(page.ocrStatus == .done)
      #expect(page.ocrText == "one")
      #expect(page.ocrTags == ["Alice", "Kickoff meeting"])
      // Tags are not searched; the body is.
      #expect(try await library.search(query: "Kickoff").results.isEmpty)
    }
  }

  @Test func exhaustedRetriesFailThePageAndClearItsTags() async throws {
    try await withTestDataRoot { paths in
      let ocr = FakeOCRService()
      let delays = DelayRecorder()
      let (library, source) = try makeLibrary(paths: paths, ocr: ocr, retries: 1, delays: delays)
      let id = try await library.importDocument(at: source, runOCR: false).document.id
      await ocr.scriptRawReplies(docId: id, page: 2, [#"{"body": "two", "tags": ["Bob"]}"#])
      _ = try await library.runOCR(documentId: id, selection: .pages([2]))
      #expect(try await library.store.pageInfo(documentId: id, page: 2)?.ocrTags == ["Bob"])

      await ocr.scriptRawReplies(docId: id, page: 2, ["no json", "still no json", "never used"])
      let summary = try await library.runOCR(documentId: id, selection: .pages([2]))
      #expect(summary.failures.first?.error == "OCR reply is not a JSON object (after 2 attempts)")
      #expect(delays.attempts == [1])
      let page = try #require(try await library.store.pageInfo(documentId: id, page: 2))
      #expect(page.ocrStatus == .failed)
      #expect(page.ocrTags.isEmpty)
      #expect(await ocr.requests.count == 3)
    }
  }

  @Test func zeroRetriesFailsOnTheFirstBadReply() async throws {
    try await withTestDataRoot { paths in
      let ocr = FakeOCRService()
      let delays = DelayRecorder()
      let (library, source) = try makeLibrary(paths: paths, ocr: ocr, retries: 0, delays: delays)
      let id = try await library.importDocument(at: source, runOCR: false).document.id
      await ocr.scriptRawReplies(docId: id, page: 1, ["nope"])
      let summary = try await library.runOCR(documentId: id, selection: .pages([1]))
      #expect(summary.failures.first?.error == "OCR reply is not a JSON object (after 1 attempt)")
      #expect(delays.attempts.isEmpty)
    }
  }

  @Test func backoffDoublesAndIsCapped() {
    let delays = (1...6).map(StriaEnvironment.exponentialBackoff)
    #expect(delays == [.seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(30), .seconds(30)])
  }

  @Test func formatRetriesIsAConfigKey() throws {
    #expect(StriaConfig.defaults.ocr.formatRetries == 2)
    let config = try ConfigKeyPath.setting("ocr.formatRetries", to: "4", in: .defaults)
    #expect(try ConfigKeyPath.value(of: "ocr.formatRetries", in: config) == .int(4))
    #expect(throws: StriaError.self) { try ConfigKeyPath.setting("ocr.formatRetries", to: "6", in: .defaults) }
    let decoded = try JSONDecoder().decode(StriaConfig.self, from: Data(#"{"version":1,"ocr":{"concurrency":1}}"#.utf8))
    #expect(decoded.ocr.formatRetries == 2)
  }
}
