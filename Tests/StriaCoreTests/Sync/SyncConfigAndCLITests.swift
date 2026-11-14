import Foundation
@testable import StriaCore
import Testing

@Suite struct SyncConfigAndCLITests {
  @Test func defaultsPartialDecodingValidationAndKeys() throws {
    #expect(try JSONDecoder().decode(StriaConfig.self, from: Data("{}".utf8)).sync == SyncConfig())
    #expect(try JSONDecoder().decode(SyncConfig.self, from: Data(#"{"enabled":true}"#.utf8)) == SyncConfig(enabled: true))
    for key in ["enabled", "documents", "ocr", "summaries", "chats"] {
      #expect(try ConfigKeyPath.value(of: "sync." + key, in: ConfigKeyPath.setting("sync." + key, to: "false", in: .defaults)) == .bool(false))
    }
    #expect(try ConfigKeyPath.setting("sync.intervalMinutes", to: "120", in: .defaults).sync.intervalMinutes == 120)
    for raw in ["0", "121"] {
      #expect(throws: StriaError.self) { try ConfigKeyPath.setting("sync.intervalMinutes", to: raw, in: .defaults) }
    }
    let config = try ConfigKeyPath.setting("sync.folder", to: "/tmp/cloud", in: .defaults)
    #expect(try ConfigKeyPath.value(of: "sync.folder", in: config) == .string("/tmp/cloud"))
    #expect(try ConfigKeyPath.setting("sync.folder", to: "null", in: config).sync.folder == nil)
    let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(SyncConfig())) as? [String: Any]
    #expect(encoded?["folder"] is NSNull)
  }

  @Test func folderPriorityAvailabilityAndMobileProvider() async throws {
    try await withTestDataRoot { paths in
      let home = paths.root
      let cloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
      let defaultFolder = SyncFolder(environment: [:], homeDirectory: home, platform: .macOS)
      #expect(throws: StriaError.self) { try defaultFolder.resolve(options: .init()) }
      try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
      #expect(try defaultFolder.resolve(options: .init()).url == cloud.appendingPathComponent("Stria", isDirectory: true))
      #expect(try defaultFolder.resolve(options: .init(folder: "/tmp/override")).url.path == "/tmp/override")
      let environment = SyncFolder(environment: ["STRIA_SYNC_DIR": "/tmp/environment"], homeDirectory: home, platform: .macOS)
      #expect(try environment.resolve(options: .init(folder: "/tmp/override")).url.path == "/tmp/environment")
      let mobile = SyncFolder(environment: [:], platform: .iOS, provider: { .init(url: cloud, securityScoped: true) })
      #expect(try mobile.resolve(options: .init(folder: "/tmp/ignored")).securityScoped)
      #expect(try mobile.resolve(options: .init()).url == cloud)
    }
  }

  @Test func cliReportKeysAndUnavailableExitCode() async throws {
    try await withTestDataRoot { paths in
      func execute(_ args: [String], environment: [String: String] = [:]) async -> CommandOutput {
        await StriaCommand.run(arguments: ["--home", paths.root.appendingPathComponent("device").path] + args,
                               environment: environment, homeDirectory: paths.root, currentDirectory: paths.root,
                               services: { _, _ in (FakeOCRService(), FakeAgentService()) },
                               syncFileCoordinator: LocalSyncFileCoordinator())
      }
      let unavailable = await execute(["sync"])
      #expect(unavailable.exitCode == 4 && unavailable.stdout.isEmpty)
      #expect(unavailable.stderr.contains("iCloud Drive is not available"))
      let invalid = paths.root.appendingPathComponent("file")
      try Data().write(to: invalid)
      #expect(await execute(["sync", "--folder", invalid.path]).exitCode == 4)
      let folder = paths.root.appendingPathComponent("cloud")
      let synced = await execute(["sync", "--folder", folder.path])
      #expect(synced.exitCode == 0)
      let value = try json(synced.stdout)
      #expect(value.keySet == Set(["documents", "ocr", "summaries", "chats", "pending", "errors", "folder"]))
      for key in ["documents", "ocr", "summaries", "chats"] {
        #expect(value[key]?.objectValue?.keySet == Set(["pushed", "pulled"]))
      }
      #expect(value["folder"]?.stringValue == folder.path)
      #expect(try CommandLineParser.parse(["sync", "--folder", "cloud"]).command == .sync(folder: "cloud"))
      #expect(Usage.text(for: "sync").contains("sync [--folder <path>]"))
      let other = await execute(["sync"], environment: ["STRIA_SYNC_DIR": folder.path])
      #expect(other.exitCode == 0)
    }
  }

  @Test @MainActor func settingsDraftRoundTripsSync() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("stria-sync-settings-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = StriaPaths(root: root)
    do {
      let library = try StriaLibrary.open(environment: makeTestEnvironment(paths: paths, config: .defaults))
      let settings = SettingsViewModel(library: library, processEnvironment: [:])
      settings.syncEnabled = true; settings.syncDocuments = false; settings.syncOCR = false
      settings.syncSummaries = false; settings.syncChats = false
      settings.syncFolder = "/tmp/chosen"; settings.syncIntervalMinutes = 10
      #expect(settings.save())
      #expect(library.environment.config.sync == SyncConfig(enabled: true, documents: false, ocr: false, summaries: false,
                                                          chats: false, folder: "/tmp/chosen", intervalMinutes: 10))
      settings.syncIntervalMinutes = 121
      #expect(!settings.save())
      settings.load()
      #expect(settings.syncIntervalMinutes == 10)
    }
  }
}
