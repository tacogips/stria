import Foundation
import StriaCore
import Testing

@Suite struct CLIEndToEndTests {
  @Test func importOCRSearchAskAndHistoryFlow() async throws {
    try await withTestDataRoot { paths in
      let inputA = paths.root.appendingPathComponent("a.pdf")
      let inputB = paths.root.appendingPathComponent("b.pdf")
      try SamplePDFFactory.makePDF(at: inputA, pages: ["alpha learning", "alpha second", "alpha third"])
      try SamplePDFFactory.makePDF(at: inputB, pages: ["beta learning", "zebra quantum lattice", "beta third"])
      let ocr = FakeOCRService()
      let agent = FakeAgentService()
      let home = paths.root.appendingPathComponent("home")
      let first = await execute(["import", inputA.path, "--no-ocr"], home: home, paths: paths, ocr: ocr, agent: agent)
      let second = await execute(["import", inputB.path, "--no-ocr"], home: home, paths: paths, ocr: ocr, agent: agent)
      #expect(first.exitCode == 0)
      #expect(second.exitCode == 0)
      let idA = try json(first.stdout)["document"]?.objectValue?["id"]?.stringValue ?? ""
      let idB = try json(second.stdout)["document"]?.objectValue?["id"]?.stringValue ?? ""

      let listed = await execute(["list"], home: home, paths: paths, ocr: ocr, agent: agent)
      #expect(try json(listed.stdout)["documents"]?.arrayValue?.count == 2)
      let image = await execute(["page", "image", idA, "1"], home: home, paths: paths, ocr: ocr, agent: agent)
      let imagePath = try json(image.stdout)["path"]?.stringValue ?? ""
      #expect(FileManager.default.fileExists(atPath: imagePath))

      await ocr.script(docId: idA, page: 2, .success("unique alpha page"))
      await ocr.script(docId: idB, page: 2, .success("zebra quantum lattice"))
      let ocrA = await execute(["ocr", idA], home: home, paths: paths, ocr: ocr, agent: agent)
      let ocrB = await execute(["ocr", idB], home: home, paths: paths, ocr: ocr, agent: agent)
      #expect(ocrA.exitCode == 0)
      #expect(ocrB.exitCode == 0)
      let search = await execute(["search", "zebra quantum lattice"], home: home, paths: paths, ocr: ocr, agent: agent)
      let hit = try json(search.stdout)["results"]?.arrayValue?.first?.objectValue
      #expect(hit?["docId"]?.stringValue == idB)
      #expect(hit?["page"]?.intValue == 2)
      let ask = await execute(["ask", "what is on this page?", "--doc", idB, "--page", "2"], home: home, paths: paths, ocr: ocr, agent: agent)
      #expect(ask.exitCode == 0)
      #expect(try json(ask.stdout)["answer"]?.stringValue != nil)
      let history = await execute(["history", "--doc", idB, "--page", "2"], home: home, paths: paths, ocr: ocr, agent: agent)
      #expect(try json(history.stdout)["messages"]?.arrayValue?.count == 2)
    }
  }
}

func execute(
  _ arguments: [String], home: URL, paths: StriaPaths, ocr: FakeOCRService, agent: FakeAgentService
) async -> CommandOutput {
  await StriaCommand.run(arguments: ["--home", home.path] + arguments,
                         environment: ["STRIA_HOME": paths.root.appendingPathComponent("other-home").path],
                         homeDirectory: paths.root, currentDirectory: paths.root,
                         services: { _, _ in (ocr, agent) })
}

func json(_ value: String) throws -> [String: JSONValue] {
  try #require((JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any]) != nil)
  return try JSONDecoder().decode([String: JSONValue].self, from: Data(value.utf8))
}

extension JSONValue {
  var objectValue: [String: JSONValue]? { if case .object(let value) = self { value } else { nil } }
  var arrayValue: [JSONValue]? { if case .array(let value) = self { value } else { nil } }
  var stringValue: String? { if case .string(let value) = self { value } else { nil } }
  var intValue: Int? { if case .int(let value) = self { value } else { nil } }
}

extension Dictionary where Key == String, Value == JSONValue {
  var keySet: Set<String> { Set(keys) }
}
