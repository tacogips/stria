import Foundation
import StriaCore
import Testing

@Suite struct CLICommandErrorTests {
  private func errorCode(_ output: CommandOutput) -> String? {
    (try? json(output.stderr))?["error"]?.objectValue?["code"]?.stringValue
  }

  private func importPDF(
    named name: String, pages: [String], paths: StriaPaths, ocr: FakeOCRService, agent: FakeAgentService
  ) async throws -> String {
    let input = paths.root.appendingPathComponent(name)
    try SamplePDFFactory.makePDF(at: input, pages: pages)
    let output = await execute(["import", input.path, "--no-ocr"], home: paths.root.appendingPathComponent("home"),
                               paths: paths, ocr: ocr, agent: agent)
    #expect(output.exitCode == 0)
    return try json(output.stdout)["document"]?.objectValue?["id"]?.stringValue ?? ""
  }

  @Test func ocrUnavailableExitsFourAndLeavesPagesPending() async throws {
    try await withTestDataRoot { paths in
      let home = paths.root.appendingPathComponent("home")
      let ocr = FakeOCRService()
      let agent = FakeAgentService()
      let id = try await importPDF(named: "doc.pdf", pages: ["one", "two"], paths: paths, ocr: ocr, agent: agent)
      await ocr.setDefault(.failure(.unavailable("offline")))

      let output = await execute(["ocr", id], home: home, paths: paths, ocr: ocr, agent: agent)
      #expect(output.exitCode == 4)
      #expect(errorCode(output) == "serviceUnavailable")

      let pageText = await execute(["page", "text", id, "1"], home: home, paths: paths, ocr: ocr, agent: agent)
      #expect(pageText.exitCode == 0)
      #expect(try json(pageText.stdout)["ocrStatus"]?.stringValue == "pending")
    }
  }

  @Test func askAgentFailureExitsFiveAndPersistsErrorMessage() async throws {
    try await withTestDataRoot { paths in
      let home = paths.root.appendingPathComponent("home")
      let ocr = FakeOCRService()
      let agent = FakeAgentService()
      let id = try await importPDF(named: "doc.pdf", pages: ["one", "two"], paths: paths, ocr: ocr, agent: agent)
      await ocr.script(docId: id, page: 1, .success("failure scope text"))
      let ocrOutput = await execute(["ocr", id], home: home, paths: paths, ocr: ocr, agent: agent)
      #expect(ocrOutput.exitCode == 0)

      await agent.enqueue(.failure(.failed("boom")))
      let asked = await execute(["ask", "what happens?", "--doc", id, "--page", "1"], home: home, paths: paths, ocr: ocr, agent: agent)
      #expect(asked.exitCode == 5)
      #expect(errorCode(asked) == "serviceFailed")

      let history = await execute(["history", "--doc", id, "--page", "1"], home: home, paths: paths, ocr: ocr, agent: agent)
      #expect(history.exitCode == 0)
      let messages = try json(history.stdout)["messages"]?.arrayValue?.compactMap(\.objectValue) ?? []
      #expect(messages.count == 2)
      let user = messages.first { $0["role"]?.stringValue == "user" }
      let assistant = messages.first { $0["role"]?.stringValue == "assistant" }
      #expect(user?["content"]?.stringValue == "what happens?")
      #expect(assistant?["status"]?.stringValue == "error")
      #expect(assistant?["content"]?.stringValue == "boom")
    }
  }

  @Test func pageOutOfRangeExitsThreeWithPageNotFound() async throws {
    try await withTestDataRoot { paths in
      let home = paths.root.appendingPathComponent("home")
      let ocr = FakeOCRService()
      let agent = FakeAgentService()
      let id = try await importPDF(named: "doc.pdf", pages: ["one", "two"], paths: paths, ocr: ocr, agent: agent)
      for subcommand in ["image", "text"] {
        let output = await execute(["page", subcommand, id, "99"], home: home, paths: paths, ocr: ocr, agent: agent)
        #expect(output.exitCode == 3)
        #expect(output.stdout.isEmpty)
        #expect(errorCode(output) == "pageNotFound")
      }
    }
  }

  @Test func searchLimitZeroIsUsageError() async throws {
    try await withTestDataRoot { paths in
      let output = await execute(["search", "x", "--limit", "0"], home: paths.root.appendingPathComponent("home"),
                                 paths: paths, ocr: FakeOCRService(), agent: FakeAgentService())
      #expect(output.exitCode == 2)
      #expect(output.stdout.isEmpty)
      #expect(errorCode(output) == "usageError")
    }
  }

  @Test func invalidConfigSetLeavesConfigFileUntouched() async throws {
    try await withTestDataRoot { paths in
      let home = paths.root.appendingPathComponent("home")
      let ocr = FakeOCRService()
      let agent = FakeAgentService()
      let seeded = await execute(["config", "set", "ocr.concurrency", "2"], home: home, paths: paths, ocr: ocr, agent: agent)
      #expect(seeded.exitCode == 0)
      let located = await execute(["paths"], home: home, paths: paths, ocr: ocr, agent: agent)
      let configURL = URL(fileURLWithPath: try json(located.stdout)["config"]?.stringValue ?? "")
      let before = try Data(contentsOf: configURL)

      let invalid = await execute(["config", "set", "render.dpi", "10"], home: home, paths: paths, ocr: ocr, agent: agent)
      #expect(invalid.exitCode == 2)
      #expect(try Data(contentsOf: configURL) == before)
    }
  }

  @Test func configSetThenGetRoundTripsInteger() async throws {
    try await withTestDataRoot { paths in
      let home = paths.root.appendingPathComponent("home")
      let ocr = FakeOCRService()
      let agent = FakeAgentService()
      let set = await execute(["config", "set", "ocr.concurrency", "4"], home: home, paths: paths, ocr: ocr, agent: agent)
      #expect(set.exitCode == 0)
      let get = await execute(["config", "get", "ocr.concurrency"], home: home, paths: paths, ocr: ocr, agent: agent)
      #expect(get.exitCode == 0)
      let value = try json(get.stdout)
      #expect(value["key"]?.stringValue == "ocr.concurrency")
      #expect(value["value"] == .int(4))
    }
  }

  @Test func reimportReportsAlreadyImportedWithSameId() async throws {
    try await withTestDataRoot { paths in
      let home = paths.root.appendingPathComponent("home")
      let ocr = FakeOCRService()
      let agent = FakeAgentService()
      let input = paths.root.appendingPathComponent("doc.pdf")
      try SamplePDFFactory.makePDF(at: input, pages: ["one", "two"])
      let first = await execute(["import", input.path, "--no-ocr"], home: home, paths: paths, ocr: ocr, agent: agent)
      let second = await execute(["import", input.path, "--no-ocr"], home: home, paths: paths, ocr: ocr, agent: agent)
      #expect(first.exitCode == 0)
      #expect(second.exitCode == 0)
      let firstJSON = try json(first.stdout)
      let secondJSON = try json(second.stdout)
      #expect(firstJSON["alreadyImported"] == .bool(false))
      #expect(secondJSON["alreadyImported"] == .bool(true))
      let firstId = firstJSON["document"]?.objectValue?["id"]?.stringValue
      #expect(firstId != nil)
      #expect(secondJSON["document"]?.objectValue?["id"]?.stringValue == firstId)
    }
  }

  @Test func pageImagePathIsEmittedWithoutEscapedSlashes() async throws {
    try await withTestDataRoot { paths in
      let ocr = FakeOCRService()
      let agent = FakeAgentService()
      let id = try await importPDF(named: "doc.pdf", pages: ["one"], paths: paths, ocr: ocr, agent: agent)
      let output = await execute(["page", "image", id, "1"], home: paths.root.appendingPathComponent("home"),
                                 paths: paths, ocr: ocr, agent: agent)
      #expect(output.exitCode == 0)
      let path = try json(output.stdout)["path"]?.stringValue ?? ""
      #expect(path.hasPrefix("/"))
      #expect(output.stdout.contains("\"path\":\"\(path)\""))
      #expect(!output.stdout.contains("\\/"))
    }
  }

  @Test func pathsValuesAreStringsUnderSelectedHome() async throws {
    try await withTestDataRoot { paths in
      let home = paths.root.appendingPathComponent("home")
      let output = await execute(["paths"], home: home, paths: paths, ocr: FakeOCRService(), agent: FakeAgentService())
      #expect(output.exitCode == 0)
      let value = try json(output.stdout)
      #expect(value.count == 6)
      for (key, entry) in value {
        let text = entry.stringValue
        #expect(text != nil, "paths.\(key) must be a string")
        #expect(text?.hasPrefix(home.path) == true, "paths.\(key) must live under the selected home")
      }
    }
  }

  @Test func askScopeMappingReachesAgentContextThroughHandler() async throws {
    try await withTestDataRoot { paths in
      let home = paths.root.appendingPathComponent("home")
      let ocr = FakeOCRService()
      let agent = FakeAgentService()
      let phrase = "zephyr quokka lattice"
      let idA = try await importPDF(named: "a.pdf", pages: ["a1", "a2", "a3"], paths: paths, ocr: ocr, agent: agent)
      let idB = try await importPDF(named: "b.pdf", pages: ["b1", "b2", "b3"], paths: paths, ocr: ocr, agent: agent)
      await ocr.script(docId: idA, page: 1, .success(phrase))
      await ocr.script(docId: idB, page: 3, .success(phrase))
      for id in [idA, idB] {
        let output = await execute(["ocr", id], home: home, paths: paths, ocr: ocr, agent: agent)
        #expect(output.exitCode == 0)
      }

      let document = await execute(["ask", "q", "--doc", idA, "--query", phrase], home: home, paths: paths, ocr: ocr, agent: agent)
      #expect(document.exitCode == 0)
      let documentPages = await agent.requests.last?.contextPages ?? []
      #expect(!documentPages.isEmpty)
      #expect(documentPages.allSatisfy { $0.docId == idA })

      let library = await execute(["ask", "q", "--query", phrase], home: home, paths: paths, ocr: ocr, agent: agent)
      #expect(library.exitCode == 0)
      let libraryDocs = Set((await agent.requests.last?.contextPages ?? []).map(\.docId))
      #expect(libraryDocs == Set([idA, idB]))

      let page = await execute(["ask", "q", "--doc", idB, "--page", "2"], home: home, paths: paths, ocr: ocr, agent: agent)
      #expect(page.exitCode == 0)
      let pagePairs = (await agent.requests.last?.contextPages ?? []).map { "\($0.docId)#\($0.page)" }
      #expect(pagePairs == ["\(idB)#2"])
    }
  }
}
