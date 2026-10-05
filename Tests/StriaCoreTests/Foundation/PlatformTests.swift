import Foundation
@testable import StriaCore
import Testing

/// Tests use a locked store instead of the user's Keychain.
final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String: String] = [:]

  func read(vendor: String) -> String? {
    lock.lock(); defer { lock.unlock() }
    return values[vendor]
  }

  func write(_ value: String, vendor: String) {
    lock.lock(); defer { lock.unlock() }
    values[vendor] = value.isEmpty ? nil : value
  }

  func delete(vendor: String) {
    lock.lock(); defer { lock.unlock() }
    values[vendor] = nil
  }
}

@Suite("PlatformTests") struct PlatformTests {
  @Test func vendorPolicies() {
    #expect(KnownVendors.selectable(on: .macOS) == KnownVendors.gateway)
    #expect(Set(KnownVendors.selectable(on: .iOS)) == KnownVendors.apiKeyVendors)
    for vendor in KnownVendors.cliVendors {
      #expect(!KnownVendors.isAvailableOnThisPlatform(vendor, platform: .iOS))
      #expect(KnownVendors.isAvailableOnThisPlatform(vendor, platform: .macOS))
    }
    #expect(KnownVendors.isAvailableOnThisPlatform(KnownVendors.pdfTextLayer, platform: .iOS))
  }

  @Test func platformRootsAndOverrides() {
    let home = URL(fileURLWithPath: "/container")
    #expect(StriaPaths.defaultRoot(homeDirectory: home, platform: .macOS).path == "/container/.local/stria")
    #expect(StriaPaths.defaultRoot(homeDirectory: home, platform: .iOS).path == "/container/Library/Application Support/Stria")
    #expect(StriaPaths.resolve(homeFlag: nil, environment: [:], homeDirectory: home, currentDirectory: home,
                              platform: .iOS).root == StriaPaths.defaultRoot(homeDirectory: home, platform: .iOS))
    #expect(StriaPaths.resolve(homeFlag: "/flag", environment: ["STRIA_HOME": "/env"], homeDirectory: home,
                              currentDirectory: home, platform: .iOS).root.path == "/flag")
    #expect(StriaPaths.resolve(homeFlag: nil, environment: ["STRIA_HOME": "/env"], homeDirectory: home,
                              currentDirectory: home, platform: .iOS).root.path == "/env")
  }

  @Test func credentialEnvironmentReadsCurrentKeysAndKeepsMacEnvironment() throws {
    let store = InMemoryCredentialStore()
    let names = ["openai": "CUSTOM_KEY", "anthropic": "OTHER_KEY"]
    let mobile = CredentialEnvironment(environment: ["PATH": "/bin", "CUSTOM_KEY": "process"], platform: .iOS, store: store)
    store.write("first", vendor: "openai")
    store.write("other", vendor: "anthropic")
    #expect(try mobile.merged(credentials: names) == ["PATH": "/bin", "CUSTOM_KEY": "first", "OTHER_KEY": "other"])
    store.write("next", vendor: "openai")
    #expect(try mobile.merged(credentials: names)["CUSTOM_KEY"] == "next")
    store.delete(vendor: "openai")
    #expect(try mobile.merged(credentials: names)["CUSTOM_KEY"] == "process")
    let mac = CredentialEnvironment(environment: [:], platform: .macOS, store: store)
    #expect(try mac.merged(credentials: names).isEmpty)
  }

  @Test @MainActor func mobilePickersAvailabilityAndSettingsValidation() async throws {
    try await withAppModelDataRoot { paths in
      var config = StriaConfig.defaults
      config.agent.vendor = "openai"
      config.agent.model = "m"
      let store = InMemoryCredentialStore()
      let library = try StriaLibrary.open(environment: StriaEnvironment(paths: paths, config: config,
        ocrService: FakeOCRService(), agentService: FakeAgentService(), platform: .iOS, credentialStore: store))
      let settings = SettingsViewModel(library: library, processEnvironment: [:])
      let reader = ReaderViewModel(library: library, documentId: "doc")
      let pane = AgentPaneViewModel(library: library, reader: reader, processEnvironment: [:])
      #expect(settings.ocrVendorOptions.contains(KnownVendors.pdfTextLayer))
      #expect(!settings.summaryVendorOptions.contains(KnownVendors.pdfTextLayer))
      for vendor in KnownVendors.cliVendors {
        #expect(!settings.ocrVendorOptions.contains(vendor))
        #expect(!settings.summaryVendorOptions.contains(vendor))
        #expect(!pane.vendorOptions.contains(vendor))
        #expect(pane.availability(of: vendor) == .unavailableOnThisPlatform)
        settings.ocrVendor = vendor
        #expect(!settings.save())
        #expect(settings.error == KnownVendors.platformUnavailableReason)
        settings.ocrVendor = ""
        settings.summaryVendor = vendor
        #expect(!settings.save())
        #expect(settings.error == KnownVendors.platformUnavailableReason)
        settings.summaryVendor = ""
      }
      #expect(pane.availability(of: "openai") == .missingKey("OPENAI_API_KEY"))
      try settings.saveCredential("test-value", for: "openai")
      #expect(settings.hasCredential(for: "openai"))
      #expect(pane.availability(of: "openai") == .ready)
      #expect(settings.save())
      let json = try String(contentsOf: paths.config, encoding: .utf8)
      #expect(!json.contains("test-value"))
      try settings.deleteCredential(for: "openai")
      #expect(!settings.environmentHasValue("OPENAI_API_KEY"))
    }
  }

  @Test func storedSelectionAndThreadSummariesCannotBypassPlatformPolicy() async throws {
    try await withTestDataRoot { paths in
      var config = StriaConfig.testing
      config.agent.vendor = "openai"
      let agent = FakeAgentService()
      let library = try StriaLibrary.open(environment: StriaEnvironment(paths: paths, config: config,
        ocrService: FakeOCRService(), agentService: agent, platform: .iOS, credentialStore: InMemoryCredentialStore()))
      let source = paths.root.appendingPathComponent("source.pdf")
      try SamplePDFFactory.makePDF(at: source, pages: ["hello"])
      let imported = try await library.importDocument(at: source, runOCR: false)
      let answer = try await library.ask(AskRequest(question: "hello", context: .page(docId: imported.document.id, page: 1)))
      let unavailable = StriaError.serviceUnavailable(KnownVendors.platformUnavailableReason)
      try await library.setLastAgentSelection(AgentSelection(vendor: "codex", model: "m"))
      await #expect(throws: unavailable) { try await library.ask(AskRequest(question: "again", context: .library)) }
      await #expect(throws: unavailable) { try await library.summarizeThread(threadId: answer.threadId) }
      await #expect(throws: unavailable) { try await library.titleThread(threadId: answer.threadId) }
      #expect(await agent.requests.count == 1)
    }
  }

  @Test(arguments: KnownVendors.cliVendors.sorted()) func runtimeRejectsCLIWithoutCallingServices(vendor: String) async throws {
    try await withTestDataRoot { paths in
      var config = StriaConfig.testing
      config.ocr.vendor = vendor
      config.agent.vendor = vendor
      config.summary.vendor = vendor
      let ocr = FakeOCRService()
      let agent = FakeAgentService()
      let library = try StriaLibrary.open(environment: StriaEnvironment(paths: paths, config: config,
        ocrService: ocr, agentService: agent, platform: .iOS, credentialStore: InMemoryCredentialStore()))
      let unavailable = StriaError.serviceUnavailable(KnownVendors.platformUnavailableReason)
      await #expect(throws: unavailable) { try await library.runOCR(documentId: "unused", selection: .pending) }
      await #expect(throws: unavailable) { try await library.ask(AskRequest(question: "hello", context: .library)) }
      await #expect(throws: unavailable) {
        try await library.ask(AskRequest(question: "hello", context: .library, selection: AgentSelection(vendor: vendor, model: "m")))
      }
      await #expect(throws: unavailable) {
        try await library.summarizePages(documentId: "unused", request: PageSummaryRequest(selection: .missing))
      }
      #expect(await ocr.requests.isEmpty)
      #expect(await agent.requests.isEmpty)
    }
  }
}
