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
    #expect(!model.library.agentConfigured)
    let settings = model.settings
    #expect(settings.ocrVendor == SettingsViewModel.notConfigured)
    #expect(settings.systemPromptIsDefault)

    settings.ocrVendor = "claude-code"
    #expect(!settings.save())
    #expect(settings.error?.contains("model is required") == true)
    settings.applySuggestions(ocr: true)
    #expect(settings.ocrModel == ModelCatalog.defaultModel(for: "claude-code"))
    #expect(settings.ocrModel == "claude-opus-5-5")
    settings.ocrAutoRunOnImport = false
    settings.agentVendor = "anthropic"
    settings.applySuggestions(ocr: false)
    #expect(settings.agentAPIKeyEnvironment == "ANTHROPIC_API_KEY")
    settings.agentSystemPrompt = "custom prompt"
    #expect(settings.save())
    #expect(settings.error == nil)
    #expect(model.configRevision == 1)
    #expect(model.library.ocrConfigured)
    #expect(!model.library.ocrRunsAutomatically)
    let saved = try ConfigStore.loadOrCreate(paths: paths)
    #expect(saved.ocr.vendor == "claude-code")
    #expect(saved.agent.systemPrompt == "custom prompt")
    #expect(library.environment.config.agent.vendor == "anthropic")

    settings.resetSystemPrompt()
    #expect(settings.systemPromptIsDefault)
    #expect(settings.save())
    #expect(try ConfigStore.loadOrCreate(paths: paths).agent.systemPrompt == nil)
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

      settings.agentVendor = "claude-code"
      settings.applySuggestions(ocr: false)
      #expect(settings.agentModel == "claude-opus-5-5")
      settings.agentVendor = "gemini"
      settings.applySuggestions(ocr: false)
      #expect(settings.agentModel == "gemini-3.5-flash-lite")
      #expect(ModelCatalog.models(for: "openai") == ["gpt-6-luna", "gpt-6-sol", "gpt-6-astra"])
      #expect(ModelCatalog.models(for: "openrouter").contains("anthropic/claude-opus-5-5"))
      #expect(!ModelCatalog.updatedAt.isEmpty)

      settings.agentVendor = "anthropic"
      settings.agentAPIKeyEnvironment = ""
      await settings.fetchModels(ocr: false)
      #expect(settings.modelFetchError == "no key")
      settings.agentAPIKeyEnvironment = "ANTHROPIC_API_KEY"
      await settings.fetchModels(ocr: false)
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
