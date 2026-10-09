import Foundation
import StriaCore
import Testing

@Suite @MainActor struct AgentChatConfigurationTests {
  @Test(arguments: [StriaPlatform.macOS, .iOS])
  func missingAPISetupWarnsAndSavingAKeyClearsIt(platform: StriaPlatform) async throws {
    try await withAppModelDataRoot { paths in
      var config = StriaConfig.defaults
      config.agent.vendor = "openai"
      config.agent.model = "model"
      config.agent.credentials = [:]
      let store = InMemoryCredentialStore()
      let library = try StriaLibrary.open(environment: StriaEnvironment(paths: paths, config: config,
        ocrService: FakeOCRService(), agentService: FakeAgentService(), platform: platform, credentialStore: store))
      let reader = ReaderViewModel(library: library, documentId: "doc")
      let pane = AgentPaneViewModel(library: library, reader: reader, processEnvironment: [:])
      #expect(pane.configurationWarning?.contains("API key for OpenAI") == true)
      #expect(!pane.canSend)
      config.agent.credentials = ["openai": "OPENAI_API_KEY"]
      library.environment.updateConfig(config)
      #expect(pane.configurationWarning?.contains("API key for OpenAI") == true)
      let settings = SettingsViewModel(library: library, processEnvironment: [:])
      var credentialChanges = 0
      settings.onCredentialsChanged = {
        credentialChanges += 1
        pane.refreshCredentialStatus()
      }
      try settings.saveCredential("fixture-key", for: "openai")
      #expect(credentialChanges == 1)
      #expect(pane.configurationWarning == nil)
      #expect(pane.canSend)
      try settings.deleteCredential(for: "openai")
      #expect(credentialChanges == 2)
      #expect(pane.configurationWarning != nil)
      #expect(!pane.canSend)
    }
  }

  @Test func noVendorAndMissingModelWarnWithoutMislabelingMacCLI() async throws {
    try await withAppModelDataRoot { paths in
      var config = StriaConfig.defaults
      let library = try StriaLibrary.open(environment: StriaEnvironment(paths: paths, config: config,
        ocrService: FakeOCRService(), agentService: FakeAgentService(), platform: .macOS,
        credentialStore: InMemoryCredentialStore()))
      let reader = ReaderViewModel(library: library, documentId: "doc")
      let unconfigured = AgentPaneViewModel(library: library, reader: reader, processEnvironment: [:])
      #expect(unconfigured.configurationWarning?.contains("Choose a vendor") == true)
      config.agent.vendor = "codex"
      library.environment.updateConfig(config)
      let missingModel = AgentPaneViewModel(library: library, reader: reader, processEnvironment: [:])
      #expect(missingModel.configurationWarning?.contains("Choose a model") == true)
      config.agent.model = "model"
      library.environment.updateConfig(config)
      let configuredCLI = AgentPaneViewModel(library: library, reader: reader, processEnvironment: [:])
      #expect(configuredCLI.configurationWarning == nil)
      #expect(configuredCLI.canSend)
    }
  }
}
