import Foundation
import StriaCore
import Testing

@Suite @MainActor struct SettingsViewModelTests {
@Test func freshRootIsUnconfiguredAndSettingsSaveAppliesLive() async throws {
  try await withAppModelDataRoot { paths in
    let config = try ConfigStore.loadOrCreate(paths: paths)
    #expect(config.ocr.vendor == nil)
    #expect(config.agent.vendor == nil)
    #expect(config.ocr.autoRunOnImport)
    let (library, _) = try makeAppModelFixture(paths: paths, pageTexts: ["one"], config: config)
    let model = AppModel(library: library)
    #expect(!model.library.ocrConfigured)
    let settings = model.settings
    #expect(settings.credentials["anthropic"] == "ANTHROPIC_API_KEY")
    #expect(settings.ocrVendor == SettingsViewModel.notConfigured)
    #expect(settings.systemPromptIsDefault)
    #expect(settings.ocrPromptIsDefault)
    #expect(settings.ocrPrompt == OCRDefaults.prompt)

    settings.ocrVendor = "claude-code"
    #expect(!settings.save())
    #expect(settings.error?.contains("model is required") == true)
    settings.applySuggestions(ocr: true)
    #expect(settings.ocrModel == ModelCatalog.defaultModel(for: "claude-code"))
    #expect(settings.ocrModel == "claude-opus-5-5")
    settings.ocrAutoRunOnImport = false
    settings.credentials["openai"] = "MY_OPENAI_KEY"
    settings.credentials["gemini"] = ""
    settings.agentSystemPrompt = "custom prompt"
    settings.ocrPrompt = "  Transcribe this page.\n"
    #expect(!settings.ocrPromptIsDefault)
    #expect(settings.save())
    #expect(settings.error == nil)
    #expect(model.configRevision == 1)
    #expect(model.library.ocrConfigured)
    #expect(!model.library.ocrRunsAutomatically)
    let saved = try ConfigStore.loadOrCreate(paths: paths)
    #expect(saved.ocr.vendor == "claude-code")
    #expect(saved.agent.systemPrompt == "custom prompt")
    #expect(saved.ocr.prompt == "Transcribe this page.")
    #expect(library.environment.config.ocr.prompt == "Transcribe this page.")
    #expect(saved.agent.credentials["openai"] == "MY_OPENAI_KEY")
    #expect(saved.agent.credentials["gemini"] == nil)
    #expect(library.environment.config.agent.credential(for: "openai") == "MY_OPENAI_KEY")
    #expect(settings.environmentHasValue("PATH"))
    #expect(!settings.environmentHasValue("STRIA_SURELY_UNSET_VARIABLE"))

    settings.resetSystemPrompt()
    #expect(settings.systemPromptIsDefault)
    settings.resetOCRPrompt()
    #expect(settings.ocrPromptIsDefault)
    #expect(settings.save())
    #expect(try ConfigStore.loadOrCreate(paths: paths).agent.systemPrompt == nil)
    #expect(try ConfigStore.loadOrCreate(paths: paths).ocr.prompt == nil)
  }
}

@Test func unconfiguredOCRLeavesPagesPendingAndAgentIsUnavailable() async throws {
  try await withAppModelDataRoot { paths in
    let ocr = FakeOCRService()
    let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["one", "two"], ocr: ocr, config: .defaults)
    let model = LibraryViewModel(library: library)
    model.importFiles([source])
    await model.waitForImports()
    #expect(model.rows.first?.ocr.pending == 2)
    #expect(model.rows.first?.unavailableReason == "not configured")
    #expect(await ocr.requests.isEmpty)
    let imported = try #require(model.rows.first)
    await model.runOCR(documentId: imported.id, retryFailed: false)
    #expect(model.rows.first?.unavailableReason?.contains("not configured") == true)
    await #expect(throws: StriaError.self) {
      _ = try await library.ask(AskRequest(question: "q", context: .page(docId: imported.id, page: 1)))
    }
    #expect(try await library.history(documentId: imported.id).isEmpty)
  }
}

@Test func autoOCROffWaitsForRunOCR() async throws {
  try await withAppModelDataRoot { paths in
    var config = StriaConfig.testing
    config.ocr.autoRunOnImport = false
    let ocr = FakeOCRService()
    let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["one"], ocr: ocr, config: config)
    let model = LibraryViewModel(library: library)
    model.importFiles([source])
    await model.waitForImports()
    #expect(model.rows.first?.ocr.pending == 1)
    #expect(await ocr.requests.isEmpty)
    await model.runOCR(documentId: try #require(model.rows.first?.id), retryFailed: false)
    #expect(model.rows.first?.ocr.done == 1)
  }
}
}

@Suite @MainActor struct SettingsModelCatalogTests {
  @Test func modelOptionsFollowTheVendorAndFetchMerges() async throws {
    try await withAppModelDataRoot { paths in
      let (library, _) = try makeAppModelFixture(paths: paths, pageTexts: ["one"])
      let settings = SettingsViewModel(library: library) { vendor, key in
        guard vendor == "anthropic", key == "ANTHROPIC_API_KEY" else { throw ServiceError.unavailable("no key") }
        return ["claude-sonnet-5-5", "claude-fetched-1"]
      }
      #expect(settings.modelOptions(for: "claude-code", current: "") == ModelCatalog.models(for: "claude-code").sorted())
      #expect(settings.modelOptions(for: "claude-code", current: "my-custom") .contains("my-custom"))
      #expect(ModelCatalog.models(for: "cursor").isEmpty)

      settings.ocrVendor = "claude-code"
      settings.applySuggestions(ocr: true)
      #expect(settings.ocrModel == "claude-opus-5-5")
      settings.ocrVendor = "gemini"
      settings.applySuggestions(ocr: true)
      #expect(settings.ocrModel == "gemini-3.5-flash-lite")
      #expect(ModelCatalog.models(for: "openai") == ["gpt-6-luna", "gpt-6.1-sol", "gpt-6-sol", "gpt-6-astra"])
      #expect(ModelCatalog.models(for: "codex").contains("gpt-6.1-sol"))
      #expect(ModelCatalog.models(for: "openrouter").contains("anthropic/claude-opus-5-5"))
      #expect(!ModelCatalog.updatedAt.isEmpty)

      settings.ocrVendor = "anthropic"
      settings.ocrAPIKeyEnvironment = ""
      await settings.fetchModels(ocr: true)
      #expect(settings.modelFetchError == "no key")
      settings.ocrAPIKeyEnvironment = "ANTHROPIC_API_KEY"
      await settings.fetchModels(ocr: true)
      #expect(settings.modelFetchError == nil)
      #expect(settings.modelOptions(for: "anthropic", current: "").contains("claude-fetched-1"))
      #expect(settings.modelOptions(for: "anthropic", current: "").filter { $0 == "claude-sonnet-5-5" }.count == 1)
    }
  }
}

@Suite struct AppearanceTests {
  @Test func lightIsDefaultAndToggleAlwaysChangesScheme() {
    #expect(Appearance.default == .light)
    #expect(Appearance.light.toggled == .dark)
    #expect(Appearance.dark.toggled == .light)
    #expect(Appearance.system.toggled == .dark)
    #expect(Appearance(rawValue: "light") == .light)
  }
}

@Suite struct RelativeAgeTests {
  @Test func coarseGranularity() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(RelativeAge.string(from: now.addingTimeInterval(-30), now: now) == "just now")
    #expect(RelativeAge.string(from: now.addingTimeInterval(-125), now: now) == "2 min ago")
    #expect(RelativeAge.string(from: now.addingTimeInterval(-3_600), now: now) == "1 hour ago")
    #expect(RelativeAge.string(from: now.addingTimeInterval(-5 * 3_600), now: now) == "5 hours ago")
    #expect(RelativeAge.string(from: now.addingTimeInterval(-3 * 86_400), now: now) == "3 days ago")
    #expect(RelativeAge.string(from: now.addingTimeInterval(-40 * 86_400), now: now).hasPrefix("20"))
  }
}

@Suite @MainActor struct ChatVendorSelectionTests {
  @Test func selectionIsPerQuestionPersistedAndKeyGated() async throws {
    try await withAppModelDataRoot { paths in
      var noAutoSummary = StriaConfig.defaults
      noAutoSummary.agent.autoSummarize = false
      let fakeAgent = FakeAgentService()
      let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["one"], agent: fakeAgent, config: noAutoSummary)
      let imported = try await library.importDocument(at: source, runOCR: false)
      let reader = ReaderViewModel(library: library, documentId: imported.document.id)
      try await reader.open()
      let pane = AgentPaneViewModel(library: library, reader: reader, processEnvironment: ["OPENAI_API_KEY": "sk-x"])
      await pane.loadSelection()
      #expect(pane.selectedVendor == nil)
      #expect(!pane.canSend)
      #expect(pane.availability(of: "claude-code") == .ready)
      #expect(pane.availability(of: "anthropic") == .missingKey("ANTHROPIC_API_KEY"))
      #expect(pane.availability(of: "openai") == .ready)

      await pane.select(vendor: "anthropic")
      #expect(pane.selectedVendor == nil)
      await pane.select(vendor: "openai")
      #expect(pane.selectedVendor == "openai")
      #expect(pane.selectedModel == "gpt-6-luna")
      await pane.select(model: "gpt-6-sol")
      #expect(try await library.lastAgentSelection() == AgentSelection(vendor: "openai", model: "gpt-6-sol"))

      pane.input = "q"
      await pane.send()
      let requests = await fakeAgent.requests
      #expect(requests.last?.settings.vendor == "openai")
      #expect(requests.last?.settings.model == "gpt-6-sol")
      #expect(requests.last?.settings.apiKeyEnvironment == "OPENAI_API_KEY")

      let next = AgentPaneViewModel(library: library, reader: reader, processEnvironment: [:])
      await next.loadSelection()
      #expect(next.selectedVendor == "openai")
      #expect(next.selectedModel == "gpt-6-sol")
      #expect(!next.canSend)
      #expect(next.availability(of: "openai") == .missingKey("OPENAI_API_KEY"))
      next.input = "q2"
      await next.send()
      #expect(next.notice?.contains("API key") == true)
      #expect(await fakeAgent.requests.count == requests.count)
      await reader.close()
    }
  }
}
