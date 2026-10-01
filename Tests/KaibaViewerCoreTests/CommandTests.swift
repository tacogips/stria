import Testing
@testable import KaibaViewerCore

@Test func commandReportsVersion() throws {
  let command = KaibaViewerCommand(arguments: ["--version"])
  #expect(try command.run() == Version.current)
}

@Test func commandReportsUsage() throws {
  let command = KaibaViewerCommand(arguments: ["--help"])
  #expect(try command.run().contains("Usage: kaiba-viewer"))
}

@Test func commandRejectsUnknownFlags() throws {
  let command = KaibaViewerCommand(arguments: ["--unknown"])
  do {
    _ = try command.run()
    Issue.record("Expected an unknown argument error")
  } catch KaibaViewerCommand.Error.unknownArgument(let argument) {
    #expect(argument == "--unknown")
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}
