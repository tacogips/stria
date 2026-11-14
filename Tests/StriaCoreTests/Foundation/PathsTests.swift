import Foundation
import StriaCore
import Testing

@Test func pathsResolveByPrecedenceAndNormalize() {
  let home = URL(fileURLWithPath: "/Users/test")
  let cwd = URL(fileURLWithPath: "/tmp/c")
  #expect(StriaPaths.resolve(homeFlag: "/tmp/a", environment: ["STRIA_HOME": "/tmp/b"], homeDirectory: home, currentDirectory: cwd).root.path == "/tmp/a")
  #expect(StriaPaths.resolve(homeFlag: nil, environment: ["STRIA_HOME": "/tmp/b"], homeDirectory: home, currentDirectory: cwd).root.path == "/tmp/b")
  #expect(StriaPaths.resolve(homeFlag: nil, environment: ["STRIA_HOME": ""], homeDirectory: home, currentDirectory: cwd).root.path == "/Users/test/.local/stria")
  #expect(StriaPaths.resolve(homeFlag: "rel/x", environment: [:], homeDirectory: home, currentDirectory: cwd).root.path == "/tmp/c/rel/x")
}

@Test func pathsExposeStableLocationsAndCacheNames() throws {
  let paths = StriaPaths(root: URL(fileURLWithPath: "/tmp/stria-test"))
  #expect(paths.cachedPage(docId: "abc", page: 1).lastPathComponent == "page-0001.png")
  #expect(paths.cachedPage(docId: "abc", page: 12345).lastPathComponent == "page-12345.png")
  let date = try #require(ISO8601DateFormatter().date(from: "2026-10-01T23:30:00Z"))
  #expect(paths.runLog(for: date).lastPathComponent == "agent-runs-2026-10-01.jsonl")
  #expect(StriaDateFormat.string(from: date) == "2026-10-01T23:30:00Z")
  #expect(paths.allLocations.allSatisfy { $0.path == paths.root.path || $0.path.hasPrefix(paths.root.path + "/") })
}

@Test func ensureDirectoriesUsesPrivatePermissions() async throws {
  try await withTestDataRoot { paths in
    try paths.ensureDirectories()
    for directory in [paths.root, paths.originals, paths.cache, paths.logs] {
      let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
      #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }
  }
}
