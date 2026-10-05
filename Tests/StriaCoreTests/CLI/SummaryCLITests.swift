import Foundation
import StriaCore
import Testing

@Suite struct SummaryCLITests {
  @Test func summarizeAndReadPageSummaries() async throws {
    try await withTestDataRoot { paths in
      let input = paths.root.appendingPathComponent("s.pdf")
      try SamplePDFFactory.makePDF(at: input, pages: ["first", "second"])
      let ocr = FakeOCRService()
      let agent = FakeAgentService()
      let home = paths.root.appendingPathComponent("home")
      let imported = await execute(["import", input.path, "--ocr"], home: home, paths: paths, ocr: ocr, agent: agent)
      let id = try json(imported.stdout)["document"]?.objectValue?["id"]?.stringValue ?? ""

      let unconfigured = await execute(["summarize", id], home: home, paths: paths, ocr: ocr, agent: agent)
      #expect(unconfigured.exitCode == 4)
      #expect(await execute(["config", "set", "summary.vendor", "claude-code"], home: home, paths: paths, ocr: ocr, agent: agent).exitCode == 0)
      #expect(await execute(["config", "set", "summary.model", "m"], home: home, paths: paths, ocr: ocr, agent: agent).exitCode == 0)

      let text = await execute(["page", "text", id, "1"], home: home, paths: paths, ocr: ocr, agent: agent)
      #expect(try json(text.stdout)["tags"]?.arrayValue == [])
      #expect(try json(text.stdout)["text"]?.stringValue == "text \(id) p1")

      let empty = await execute(["page", "summary", id, "1"], home: home, paths: paths, ocr: ocr, agent: agent)
      #expect(try json(empty.stdout)["status"]?.stringValue == "none")
      #expect(try json(empty.stdout)["summary"] == .null)

      await agent.enqueue(.success("One."))
      await agent.enqueue(.success("Two."))
      let all = await execute(["summarize", id], home: home, paths: paths, ocr: ocr, agent: agent)
      #expect(all.exitCode == 0)
      #expect(try json(all.stdout)["summarized"]?.arrayValue?.compactMap(\.intValue) == [1, 2])
      #expect(try json(all.stdout).keySet == Set(["docId", "ocred", "ocrFailures", "summarized", "skipped", "failures",
                                                  "ocrUnavailableReason"]))

      await agent.enqueue(.success("Deux."))
      let redo = await execute(["summarize", id, "--pages", "2", "--instruction", "In French", "--language", "French"],
                               home: home, paths: paths, ocr: ocr, agent: agent)
      #expect(redo.exitCode == 0)
      let page = await execute(["page", "summary", id, "2"], home: home, paths: paths, ocr: ocr, agent: agent)
      let object = try json(page.stdout)
      #expect(object["summary"]?.stringValue == "Deux.")
      #expect(object["language"]?.stringValue == "French")
      #expect(object["instruction"]?.stringValue == "In French")
      #expect(object["stale"] == .bool(false))
      #expect(object.keySet == Set(["docId", "page", "status", "summary", "error", "language", "instruction", "vendor", "model",
                                    "stale", "updatedAt"]))
      let outOfRange = await execute(["page", "summary", id, "3"], home: home, paths: paths, ocr: ocr, agent: agent)
      #expect(outOfRange.exitCode == 3)
      let badPages = await execute(["summarize", id, "--pages", "5"], home: home, paths: paths, ocr: ocr, agent: agent)
      #expect(badPages.exitCode == 2)
    }
  }
}
