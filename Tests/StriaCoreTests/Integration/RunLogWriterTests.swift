import Foundation
import StriaCore
import Testing

struct RunLogWriterTests {
  @Test func appendsSortedJSONLinesWithExactKeysAndExplicitNulls() async throws {
    try await withTestDataRoot { paths in
      let date = Date(timeIntervalSince1970: 1_750_000_000)
      let writer = RunLogWriter(paths: paths)
      try writer.append(run(id: "r1", date: date))
      try writer.append(run(id: "r2", date: date))

      let lines = try String(contentsOf: paths.runLog(for: date), encoding: .utf8).split(separator: "\n")
      #expect(lines.count == 2)
      let expected = Set(["runId", "kind", "docId", "page", "vendor", "model", "status", "imageCount", "startedAt", "finishedAt", "durationMs", "error"])
      for line in lines {
        let object = try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        #expect(Set(object.keys) == expected)
        let serialized = String(line)
        let sortedFragments = ["\"docId\":", "\"durationMs\":", "\"error\":", "\"finishedAt\":", "\"imageCount\":", "\"kind\":", "\"model\":", "\"page\":", "\"runId\":", "\"startedAt\":", "\"status\":", "\"vendor\":"]
        let positions = sortedFragments.compactMap { fragment in
          serialized.range(of: fragment).map { serialized.distance(from: serialized.startIndex, to: $0.lowerBound) }
        }
        #expect(positions.count == sortedFragments.count)
        #expect(positions == positions.sorted())
        #expect(object["error"] is NSNull)
        #expect(object["docId"] is NSNull)
        #expect(object["model"] is NSNull)
        #expect(!object.keys.contains(where: { $0.localizedCaseInsensitiveContains("prompt") || $0.localizedCaseInsensitiveContains("text") }))
      }
    }
  }

  private func run(id: String, date: Date) -> AgentRunRecord {
    AgentRunRecord(
      id: id, kind: .ocr, documentId: nil, pageNumber: nil, vendor: "anthropic", model: nil,
      status: .ok, error: nil, imageCount: 1, startedAt: date, finishedAt: date, durationMs: 10
    )
  }
}
