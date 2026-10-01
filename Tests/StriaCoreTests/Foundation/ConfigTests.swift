import Foundation
import StriaCore
import Testing

@Test func configCreatesDefaultsAndPreservesExistingBytes() async throws {
  try await withTestDataRoot { paths in
    let initial = try ConfigStore.loadOrCreate(paths: paths)
    #expect(initial == .defaults)
    #expect(FileManager.default.fileExists(atPath: paths.config.path))
    let data = Data(#"{"ocr":{"concurrency":4}}"#.utf8)
    try data.write(to: paths.config)
    let partial = try ConfigStore.loadOrCreate(paths: paths)
    #expect(partial.ocr.concurrency == 4)
    #expect(partial.agent == StriaConfig.defaults.agent)
    #expect(try Data(contentsOf: paths.config) == data)
  }
}

@Test func configOptionalNullValidationAndRoundTrip() async throws {
  try await withTestDataRoot { paths in
    try paths.ensureDirectories()
    let nullModel = Data(#"{"ocr":{"model":null}}"#.utf8)
    try nullModel.write(to: paths.config)
    #expect(try ConfigStore.loadOrCreate(paths: paths).ocr.model == nil)
    let encoded = try JSONEncoder().encode(StriaConfig.defaults)
    #expect(String(data: encoded, encoding: .utf8)?.contains("\"prompt\":null") == true)
    try ConfigStore.save(.defaults, paths: paths)
    #expect(try ConfigStore.loadOrCreate(paths: paths) == .defaults)
  }
}

@Test func invalidConfigIsRejectedWithoutChangingBytes() async throws {
  try await withTestDataRoot { paths in
    try paths.ensureDirectories()
    for bytes in [Data("{invalid".utf8), Data(#"{"render":{"dpi":10}}"#.utf8), Data(#"{"ocr":{"apiKeyEnvironment":"sk-abc"}}"#.utf8)] {
      try bytes.write(to: paths.config)
      do {
        _ = try ConfigStore.loadOrCreate(paths: paths)
        Issue.record("Expected invalid config")
      } catch let error as StriaError {
        #expect(error.code == .configInvalid)
      }
      #expect(try Data(contentsOf: paths.config) == bytes)
    }
  }
}
