import Foundation
import StriaCore
import Testing

@Suite struct CLICommandTests {
  @Test func helpAndVersionDoNotCreateSelectedRoot() async throws {
    try await withTestDataRoot { paths in
      let home = paths.root.appendingPathComponent("missing-home")
      for args in [["--help"], ["--version"]] {
        let output = await execute(args, home: home, paths: paths, ocr: FakeOCRService(), agent: FakeAgentService())
        #expect(output.exitCode == 0)
        #expect(!FileManager.default.fileExists(atPath: home.path))
      }
    }
  }

  @Test func askPassesQueryAndLimitAndMapsScopes() async throws {
    try await withTestDataRoot { paths in
      let input = paths.root.appendingPathComponent("doc.pdf")
      try SamplePDFFactory.makePDF(at: input, pages: ["searchable phrase", "another page"])
      let ocr = FakeOCRService()
      let agent = FakeAgentService()
      let imported = await execute(["import", input.path, "--no-ocr"], home: paths.root.appendingPathComponent("home"), paths: paths, ocr: ocr, agent: agent)
      let id = try json(imported.stdout)["document"]?.objectValue?["id"]?.stringValue ?? ""
      await ocr.script(docId: id, page: 2, .success("searchable phrase"))
      _ = await execute(["ocr", id], home: paths.root.appendingPathComponent("home"), paths: paths, ocr: ocr, agent: agent)

      let invalid = await execute(["ask", "q", "--limit", "11"], home: paths.root.appendingPathComponent("home"), paths: paths, ocr: ocr, agent: agent)
      #expect(invalid.exitCode == 2)
      #expect(invalid.stderr.contains("usageError"))
      let asked = await execute(["ask", "q", "--doc", id, "--query", "searchable phrase", "--limit", "1"], home: paths.root.appendingPathComponent("home"), paths: paths, ocr: ocr, agent: agent)
      #expect(asked.exitCode == 0)
      let requests = await agent.requests
      #expect(requests.last?.question == "q")
      #expect(requests.last?.contextPages.map(\.page) == [2])

      let pageScope = try CommandLineParser.parse(["ask", "q", "--doc", id, "--page", "2"]).command
      let documentScope = try CommandLineParser.parse(["ask", "q", "--doc", id]).command
      let libraryScope = try CommandLineParser.parse(["ask", "q"]).command
      #expect(pageScope == .ask(question: "q", docId: id, page: 2, query: nil, limit: nil, thread: nil))
      #expect(documentScope == .ask(question: "q", docId: id, page: nil, query: nil, limit: nil, thread: nil))
      #expect(libraryScope == .ask(question: "q", docId: nil, page: nil, query: nil, limit: nil, thread: nil))
    }
  }

  @Test func unknownDocumentAndInvalidSearchLimitUseStableErrors() async throws {
    try await withTestDataRoot { paths in
      let home = paths.root.appendingPathComponent("home")
      let ocr = FakeOCRService()
      let agent = FakeAgentService()
      let missing = await execute(["show", "missing"], home: home, paths: paths, ocr: ocr, agent: agent)
      #expect(missing.exitCode == 3)
      #expect(missing.stderr.contains("documentNotFound"))
      let invalid = await execute(["search", "x", "--limit", "101"], home: home, paths: paths, ocr: ocr, agent: agent)
      #expect(invalid.exitCode == 2)
      #expect(invalid.stderr.contains("usageError"))
    }
  }

  @Test func homeFlagPrecedesEnvironmentAndOutputKeysAreExplicit() async throws {
    try await withTestDataRoot { paths in
      let flagHome = paths.root.appendingPathComponent("flag-home")
      let otherHome = paths.root.appendingPathComponent("env-home")
      let output = await StriaCommand.run(arguments: ["--home", flagHome.path, "paths"],
                                          environment: ["STRIA_HOME": otherHome.path], homeDirectory: paths.root,
                                          currentDirectory: paths.root, services: { _, _ in (FakeOCRService(), FakeAgentService()) })
      let value = try json(output.stdout)
      #expect(value["home"]?.stringValue == flagHome.path)
      #expect(Set(value.keys) == Set(["home", "database", "originals", "cache", "config", "logs"]))
      #expect(!FileManager.default.fileExists(atPath: otherHome.path))
    }
  }

  @Test func commandOutputsKeepExactKeysAndExplicitNulls() async throws {
    try await withTestDataRoot { paths in
      let home = paths.root.appendingPathComponent("home")
      let input = paths.root.appendingPathComponent("contract.pdf")
      try SamplePDFFactory.makePDF(at: input, pages: ["unique key phrase", "second page"])
      let ocr = FakeOCRService()
      let agent = FakeAgentService()

      let imported = await execute(["import", input.path, "--no-ocr"], home: home, paths: paths, ocr: ocr, agent: agent)
      let importJSON = try json(imported.stdout)
      #expect(Set(importJSON.keys) == Set(["alreadyImported", "document", "ocr"]))
      #expect(importJSON["document"]?.objectValue?.keySet == Set(["id", "title", "pageCount", "importStatus", "importedAt", "originalPath", "ocr"]))
      #expect(importJSON["document"]?.objectValue?["ocr"]?.objectValue?.keySet == Set(["done", "failed", "pending"]))
      #expect(importJSON["ocr"]?.objectValue?.keySet == Set(["status", "reason", "done", "failed", "pending"]))
      #expect(importJSON["ocr"]?.objectValue?["reason"] == .null)
      let id = importJSON["document"]?.objectValue?["id"]?.stringValue ?? ""

      let listed = try json((await execute(["list"], home: home, paths: paths, ocr: ocr, agent: agent)).stdout)
      #expect(Set(listed.keys) == Set(["documents"]))
      #expect(listed["documents"]?.arrayValue?.first?.objectValue?.keySet == Set(["id", "title", "pageCount", "importStatus", "importedAt", "originalPath", "ocr"]))
      let shown = try json((await execute(["show", id], home: home, paths: paths, ocr: ocr, agent: agent)).stdout)
      #expect(Set(shown.keys) == Set(["document", "outline"]))
      #expect(shown["document"]?.objectValue?.keySet == Set(["id", "title", "pageCount", "importStatus", "importedAt", "originalPath", "ocr", "sha256", "byteSize", "renderDpi", "imageFormat", "ocrVendor", "ocrModel"]))
      #expect(shown["document"]?.objectValue?["ocrVendor"] == .string("anthropic"))

      let image = try json((await execute(["page", "image", id, "1"], home: home, paths: paths, ocr: ocr, agent: agent)).stdout)
      #expect(Set(image.keys) == Set(["docId", "page", "path", "width", "height", "format", "cached"]))
      let pageText = try json((await execute(["page", "text", id, "1"], home: home, paths: paths, ocr: ocr, agent: agent)).stdout)
      #expect(Set(pageText.keys) == Set(["docId", "page", "ocrStatus", "text", "ocrError", "ocrVendor", "ocrModel"]))
      #expect(pageText["text"] == .null)

      await ocr.script(docId: id, page: 1, .success("unique key phrase"))
      let ocrResult = try json((await execute(["ocr", id], home: home, paths: paths, ocr: ocr, agent: agent)).stdout)
      #expect(Set(ocrResult.keys) == Set(["docId", "processed", "done", "failed", "pending", "failures"]))
      let search = try json((await execute(["search", "unique key phrase"], home: home, paths: paths, ocr: ocr, agent: agent)).stdout)
      #expect(Set(search.keys) == Set(["query", "matchMode", "results"]))
      #expect(search["results"]?.arrayValue?.first?.objectValue?.keySet == Set(["docId", "title", "page", "snippet", "score", "imagePath", "imageCached"]))
      let asked = try json((await execute(["ask", "summarize", "--doc", id, "--query", "unique key phrase"], home: home, paths: paths, ocr: ocr, agent: agent)).stdout)
      #expect(Set(asked.keys) == Set(["threadId", "answer", "vendor", "model", "runId", "citations", "contextPages"]))
      let history = try json((await execute(["history", "--doc", id], home: home, paths: paths, ocr: ocr, agent: agent)).stdout)
      #expect(Set(history.keys) == Set(["messages"]))
      #expect(history["messages"]?.arrayValue?.first?.objectValue?.keySet == Set(["id", "threadId", "role", "status", "content", "docId", "page", "vendor", "model", "runId", "citations", "createdAt"]))

      let config = try json((await execute(["config", "get", "ocr.model"], home: home, paths: paths, ocr: ocr, agent: agent)).stdout)
      #expect(Set(config.keys) == Set(["key", "value"]))
      let locations = try json((await execute(["paths"], home: home, paths: paths, ocr: ocr, agent: agent)).stdout)
      #expect(Set(locations.keys) == Set(["home", "database", "originals", "cache", "config", "logs"]))

      let badOption = await execute(["list", "--bad"], home: home, paths: paths, ocr: ocr, agent: agent)
      #expect(badOption.exitCode == 2)
      #expect(badOption.stdout.isEmpty)
      #expect(try json(badOption.stderr)["error"]?.objectValue?.keySet == Set(["code", "message"]))
    }
  }
}
