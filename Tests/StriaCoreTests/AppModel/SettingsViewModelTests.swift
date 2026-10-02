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
    #expect(settings.ocrModel == "claude-sonnet-5-5")
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
