import StriaCore
import Testing

@Suite struct ParserTests {
  @Test func globalOptionsAndBasicCommands() throws {
    #expect(try CommandLineParser.parse(["--home", "/tmp/x", "list"]) == ParsedInvocation(home: "/tmp/x", command: .list))
    #expect(try CommandLineParser.parse(["list", "--home", "/tmp/x"]) == ParsedInvocation(home: "/tmp/x", command: .list))
    #expect(try CommandLineParser.parse(["import", "a.pdf", "--no-ocr", "--json"]).command == .importPDF(path: "a.pdf", noOCR: true))
    #expect(try CommandLineParser.parse(["page", "image", "abc", "3", "--output", "/tmp/o.png"]).command == .pageImage(docId: "abc", page: 3, output: "/tmp/o.png"))
    #expect(try CommandLineParser.parse(["search", "foo", "--doc", "d", "--limit", "5"]).command == .search(query: "foo", docId: "d", limit: 5))
    #expect(try CommandLineParser.parse(["history", "--doc", "d", "--page", "2"]).command == .history(docId: "d", page: 2, limit: nil))
    #expect(try CommandLineParser.parse(["remove", "d"]).command == .remove(docId: "d"))
    #expect(try CommandLineParser.parse(["config"]).command == .configGet(key: nil))
    #expect(try CommandLineParser.parse(["config", "set", "ocr.concurrency", "4"]).command == .configSet(key: "ocr.concurrency", value: "4"))
    #expect(try CommandLineParser.parse(["ocr", "d", "--pages", "1,3-5", "--retry-failed"]).command == .ocr(docId: "d", pages: "1,3-5", retryFailed: true))
  }

  @Test func helpAndVersion() throws {
    #expect(try CommandLineParser.parse([]).command == .help(topic: nil))
    #expect(try CommandLineParser.parse(["search", "--help"]).command == .help(topic: "search"))
    #expect(try CommandLineParser.parse(["--version"]).command == .version)
  }

  @Test func invalidInvocationIsUsageError() {
    for args in [["page", "text", "abc", "0"], ["search"], ["search", "a", "b"], ["ask", "q", "--page", "2"], ["list", "--foo"], ["--home"], ["list", "--home", "--json"], ["search", "foo", "--limit", "0"]] {
      do {
        _ = try CommandLineParser.parse(args)
        Issue.record("Expected usageError for \(args)")
      } catch {
        #expect(error.code == .usageError)
      }
    }
  }

  @Test func unknownOptionsNameCommand() {
    do {
      _ = try CommandLineParser.parse(["search", "foo", "--foo"])
      Issue.record("Expected unknown option error")
    } catch {
      #expect(error.message == "Unknown option --foo for search")
    }
  }

  @Test func parsesRemainingCommandForms() throws {
    #expect(try CommandLineParser.parse(["ask", "q", "--doc", "d", "--page", "2", "--query", "x y", "--limit", "3"]).command == .ask(question: "q", docId: "d", page: 2, query: "x y", limit: 3))
    #expect(try CommandLineParser.parse(["page", "text", "abc", "2"]).command == .pageText(docId: "abc", page: 2))
    #expect(try CommandLineParser.parse(["show", "abc"]).command == .show(docId: "abc"))
    #expect(try CommandLineParser.parse(["paths"]).command == .paths)
    #expect(try CommandLineParser.parse(["config", "get", "ocr.model"]).command == .configGet(key: "ocr.model"))
    #expect(try CommandLineParser.parse(["-h"]).command == .help(topic: nil))
  }

  @Test func rejectsRemainingMalformedInvocations() {
    for args in [["frobnicate"], ["search", "q", "--doc", "--limit"], ["--home", "a", "--home", "b", "list"]] {
      do {
        _ = try CommandLineParser.parse(args)
        Issue.record("Expected usageError for \(args)")
      } catch {
        #expect(error.code == .usageError)
      }
    }
  }
}
