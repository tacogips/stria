import Foundation
import Observation

/// Draft of the OCR and agent settings edited in the app's Settings window.
/// Nothing is written until `save()`; a saved config applies to the next
/// OCR or ask call immediately through `StriaLibrary.saveConfig`.
@MainActor
@Observable
public final class SettingsViewModel {
  /// "" stands for "not configured".
  public static let notConfigured = ""
  public static let ocrVendorOptions = [notConfigured, KnownVendors.pdfTextLayer] + KnownVendors.selectable
  public static let summaryVendorOptions = [notConfigured] + KnownVendors.selectable
  /// API vendors whose credential variable name is set in Settings.
  public static let credentialVendors = KnownVendors.apiKeyVendors.sorted()

  public var voiceEngine = "apple"
  public var voiceModel = ""
  public var voiceLanguage = "auto"
  public var voiceAutoSend = false
  public var voiceMaxSeconds = 300
  public var voiceLanguageOptions: [String] {
    VoiceOptions.languages.contains(voiceLanguage) ? VoiceOptions.languages : VoiceOptions.languages + [voiceLanguage]
  }

  public var syncEnabled = false
  public var syncDocuments = true
  public var syncOCR = true
  public var syncSummaries = true
  public var syncChats = true
  public var syncFolder = ""
  public var syncIntervalMinutes = 5
  public var ocrVendor = notConfigured
  public var ocrModel = ""
  public var ocrAPIKeyEnvironment = ""
  public var ocrAutoRunOnImport = true
  public var ocrConcurrency = 2
  public var ocrFormatRetries = OCRDefaults.formatRetries
  /// The OCR prompt as shown for editing; the default text when none is set.
  public var ocrPrompt = OCRDefaults.prompt
  /// Credential variable name per API vendor ("" = none).
  public var credentials: [String: String] = [:]
  /// The prompt as shown for editing; the default text when none is set.
  public var agentSystemPrompt = AgentDefaults.systemPrompt
  public var agentAutoSummarize = true
  public var summaryVendor = notConfigured
  public var summaryModel = ""
  public var summaryAutoRun = false
  /// A `PageSummaryLanguage.options` entry (or a custom name from config).
  public var summaryLanguage = PageSummaryLanguage.auto
  /// The summary prompt template as shown for editing; the default when none is set.
  public var summaryPrompt = PageSummaryDefaults.prompt
  public private(set) var error: String?
  public private(set) var savedAt: Date?
  public var onSaved: (() -> Void)?
  /// Models fetched live from a vendor, keyed by vendor id.
  public private(set) var fetchedModels: [String: [String]] = [:]
  public private(set) var modelFetchError: String?
  public private(set) var isFetchingModels = false
  /// Value of the model picker that reveals the free-text field.
  public static let customModel = "__custom__"

  public var ocrVendorOptions: [String] { [Self.notConfigured, KnownVendors.pdfTextLayer] + KnownVendors.selectable(on: library.environment.platform) }
  public var summaryVendorOptions: [String] { [Self.notConfigured] + KnownVendors.selectable(on: library.environment.platform) }

  /// Saves a mobile API key immediately; values never enter the config draft.
  public func saveCredential(_ value: String, for vendor: String) throws {
    guard library.environment.platform == .iOS, KnownVendors.apiKeyVendors.contains(vendor) else {
      throw StriaError.config("API keys are stored in environment variables on the Mac")
    }
    try library.environment.credentialStore.write(value, vendor: vendor)
  }

  public func deleteCredential(for vendor: String) throws {
    guard library.environment.platform == .iOS else { return }
    try library.environment.credentialStore.delete(vendor: vendor)
  }

  public func hasCredential(for vendor: String) -> Bool {
    guard let name = Self.trimmed(credentials[vendor] ?? "") else { return false }
    return environmentHasValue(name)
  }

  private let library: StriaLibrary
  private let modelLister: @Sendable (String, String?) async throws -> [String]
  private let processEnvironment: [String: String]

  public init(library: StriaLibrary,
              processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
              modelLister: (@Sendable (String, String?) async throws -> [String])? = nil) {
    self.library = library
    self.processEnvironment = processEnvironment
    self.modelLister = modelLister ?? { vendor, name in
      try await GatewayModelCatalogService.models(vendor: vendor, apiKeyEnvironment: name,
                                                  environment: processEnvironment,
                                                  platform: library.environment.platform,
                                                  credentialStore: library.environment.credentialStore)
    }
    load()
  }

  /// Whether the named variable has a process value or a matching mobile API key.
  public func environmentHasValue(_ name: String) -> Bool {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    if library.environment.platform == .iOS {
      var vendors = credentials.filter { Self.trimmed($0.value) == trimmed }.map(\.key)
      if Self.trimmed(ocrAPIKeyEnvironment) == trimmed { vendors.append(ocrVendor) }
      for vendor in vendors where KnownVendors.apiKeyVendors.contains(vendor) {
        if let value = try? library.environment.credentialStore.read(vendor: vendor), !value.isEmpty { return true }
      }
    }
    return processEnvironment[trimmed].map { !$0.isEmpty } ?? false
  }

  /// Models the picker offers for a vendor: the known catalog plus anything
  /// fetched live, de-duplicated and sorted, with the current value kept.
  public func modelOptions(for vendor: String, current: String) -> [String] {
    var options = ModelCatalog.models(for: vendor) + (fetchedModels[vendor] ?? [])
    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty, !options.contains(trimmed) { options.append(trimmed) }
    var seen = Set<String>()
    return options.filter { seen.insert($0).inserted }.sorted()
  }

  public func canFetchModels(for vendor: String) -> Bool { ModelCatalog.supportsListing(vendor) }

  public func fetchModels(ocr: Bool) async {
    _ = ocr
    await fetchModels(vendor: ocrVendor, apiKeyEnvironment: ocrAPIKeyEnvironment)
  }

  /// Fetches a vendor's models with the named key variable (empty = none).
  public func fetchModels(vendor: String, apiKeyEnvironment: String) async {
    let keyName = Self.trimmed(apiKeyEnvironment)
    isFetchingModels = true
    modelFetchError = nil
    defer { isFetchingModels = false }
    do {
      fetchedModels[vendor] = try await modelLister(vendor, keyName)
    } catch let failure as ServiceError {
      switch failure {
      case .unavailable(let reason), .failed(let reason): modelFetchError = reason
      }
    } catch {
      modelFetchError = error.localizedDescription
    }
  }

  /// Reloads the draft from the current configuration, discarding edits.
  public func load() {
    let config = library.environment.config
    voiceEngine = config.voice.engine
    voiceModel = config.voice.model ?? ""
    voiceLanguage = config.voice.language
    voiceAutoSend = config.voice.autoSend
    voiceMaxSeconds = config.voice.maxSeconds
    syncEnabled = config.sync.enabled
    syncDocuments = config.sync.documents
    syncOCR = config.sync.ocr
    syncSummaries = config.sync.summaries
    syncChats = config.sync.chats
    syncFolder = config.sync.folder ?? ""
    syncIntervalMinutes = config.sync.intervalMinutes
    ocrVendor = config.ocr.vendor ?? Self.notConfigured
    ocrModel = config.ocr.model ?? ""
    ocrAPIKeyEnvironment = config.ocr.apiKeyEnvironment ?? ""
    ocrAutoRunOnImport = config.ocr.autoRunOnImport
    ocrConcurrency = config.ocr.concurrency
    ocrFormatRetries = config.ocr.formatRetries
    ocrPrompt = config.ocr.prompt ?? OCRDefaults.prompt
    summaryVendor = config.summary.vendor ?? Self.notConfigured
    summaryModel = config.summary.model ?? ""
    summaryAutoRun = config.summary.autoRunAfterOCR
    summaryLanguage = config.summary.language
    summaryPrompt = config.summary.prompt ?? PageSummaryDefaults.prompt
    credentials = config.agent.credentials
    for vendor in Self.credentialVendors where credentials[vendor] == nil { credentials[vendor] = "" }
    agentSystemPrompt = config.agent.systemPrompt ?? AgentDefaults.systemPrompt
    agentAutoSummarize = config.agent.autoSummarize
    error = nil
  }

  public var systemPromptIsDefault: Bool {
    agentSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines) == AgentDefaults.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public func resetSystemPrompt() { agentSystemPrompt = AgentDefaults.systemPrompt }

  public var ocrPromptIsDefault: Bool {
    ocrPrompt.trimmingCharacters(in: .whitespacesAndNewlines) == OCRDefaults.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public func resetOCRPrompt() { ocrPrompt = OCRDefaults.prompt }

  public var summaryPromptIsDefault: Bool {
    summaryPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
      == PageSummaryDefaults.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public func resetSummaryPrompt() { summaryPrompt = PageSummaryDefaults.prompt }

  /// The language picker's entries, keeping a custom configured name.
  public var summaryLanguageOptions: [String] {
    PageSummaryLanguage.options.contains(summaryLanguage)
      ? PageSummaryLanguage.options : PageSummaryLanguage.options + [summaryLanguage]
  }

  /// The credential variable a summary vendor uses (from Agent API Keys).
  public var summaryCredentialName: String { credentials[summaryVendor] ?? "" }

  /// Fills an empty model with the summary vendor's suggestion and drops a
  /// model that belongs to another vendor.
  public func applySummarySuggestions() {
    if !summaryModel.isEmpty, !Self.modelMayBelong(summaryModel, to: summaryVendor) { summaryModel = "" }
    if summaryModel.isEmpty, let model = Self.suggestedModel(for: summaryVendor) { summaryModel = model }
  }

  public static func displayName(for vendor: String) -> String {
    switch vendor {
    case notConfigured: "Not configured"
    case KnownVendors.pdfTextLayer: "PDF text layer (no model, embedded text only)"
    case "claude-code": "Claude Code CLI"
    case "codex": "Codex CLI"
    case "cursor": "Cursor CLI"
    case "cursor-api": "Cursor API (no image input)"
    case "openai": "OpenAI API"
    case "anthropic": "Anthropic API"
    case "gemini": "Gemini API"
    case "openrouter": "OpenRouter API"
    default: vendor
    }
  }

  /// API vendors need a credential variable; CLI vendors use their own login.
  public static func requiresAPIKey(_ vendor: String) -> Bool { KnownVendors.apiKeyVendors.contains(vendor) }

  public static func needsModel(_ vendor: String) -> Bool {
    vendor != notConfigured && vendor != KnownVendors.pdfTextLayer
  }

  /// The vendor's first curated model (see `ModelCatalog`).
  public static func suggestedModel(for vendor: String) -> String? {
    ModelCatalog.defaultModel(for: vendor)
  }

  public static func suggestedAPIKeyEnvironment(for vendor: String) -> String? {
    switch vendor {
    case "anthropic": "ANTHROPIC_API_KEY"
    case "openai": "OPENAI_API_KEY"
    case "gemini": "GEMINI_API_KEY"
    case "openrouter": "OPENROUTER_API_KEY"
    case "cursor-api": "CURSOR_API_KEY"
    default: nil
    }
  }

  /// Fills empty model and credential fields with the vendor's suggestions,
  /// and drops a model that does not belong to the newly chosen vendor.
  public func applySuggestions(ocr: Bool) {
    if ocr {
      if !ocrModel.isEmpty, !Self.modelMayBelong(ocrModel, to: ocrVendor) { ocrModel = "" }
      if ocrModel.isEmpty, let model = Self.suggestedModel(for: ocrVendor) { ocrModel = model }
      if ocrAPIKeyEnvironment.isEmpty, let name = Self.suggestedAPIKeyEnvironment(for: ocrVendor) { ocrAPIKeyEnvironment = name }
    }
  }

  /// A model kept across a vendor change only when the new vendor's catalog
  /// knows it (custom ids are cleared, so no model from vendor A is sent to B).
  static func modelMayBelong(_ model: String, to vendor: String) -> Bool {
    ModelCatalog.models(for: vendor).contains(model)
  }

  /// The configuration the draft describes, or the reason it is invalid.
  public func draftConfig() throws(StriaError) -> StriaConfig {
    var config = library.environment.config
    config.voice = StriaConfig.VoiceConfig(engine: voiceEngine, model: Self.trimmed(voiceModel), language: voiceLanguage,
                                         autoSend: voiceAutoSend, maxSeconds: voiceMaxSeconds)
    config.sync = SyncConfig(enabled: syncEnabled, documents: syncDocuments, ocr: syncOCR, summaries: syncSummaries,
                             chats: syncChats, folder: Self.trimmed(syncFolder), intervalMinutes: syncIntervalMinutes)
    for vendor in [ocrVendor, summaryVendor, config.agent.vendor].compactMap({ $0 }) {
      guard KnownVendors.isAvailableOnThisPlatform(vendor, platform: library.environment.platform) else {
        throw .config(KnownVendors.platformUnavailableReason)
      }
    }
    config.ocr.vendor = ocrVendor == Self.notConfigured ? nil : ocrVendor
    config.ocr.model = Self.trimmed(ocrModel)
    config.ocr.apiKeyEnvironment = Self.trimmed(ocrAPIKeyEnvironment)
    config.ocr.autoRunOnImport = ocrAutoRunOnImport
    config.ocr.concurrency = ocrConcurrency
    config.ocr.formatRetries = ocrFormatRetries
    // Stored as null while it matches the default, so a later default reaches users who never edited it.
    config.ocr.prompt = ocrPromptIsDefault ? nil : Self.trimmed(ocrPrompt)
    config.agent.credentials = credentials.reduce(into: [:]) { result, entry in
      if let name = Self.trimmed(entry.value) { result[entry.key] = name }
    }
    // The default is stored as nil, so a future default change reaches users who never edited it.
    config.agent.systemPrompt = systemPromptIsDefault ? nil : Self.trimmed(agentSystemPrompt)
    config.agent.autoSummarize = agentAutoSummarize
    config.summary.vendor = summaryVendor == Self.notConfigured ? nil : summaryVendor
    config.summary.model = Self.trimmed(summaryModel)
    config.summary.autoRunAfterOCR = summaryAutoRun
    config.summary.language = Self.trimmed(summaryLanguage) ?? PageSummaryLanguage.auto
    config.summary.prompt = summaryPromptIsDefault ? nil : Self.trimmed(summaryPrompt)
    if Self.needsModel(summaryVendor), config.summary.model == nil {
      throw .config("Page summaries: a model is required for \(Self.displayName(for: summaryVendor))")
    }
    if Self.needsModel(ocrVendor), config.ocr.model == nil { throw .config("OCR: a model is required for \(Self.displayName(for: ocrVendor))") }
    if Self.requiresAPIKey(ocrVendor), config.ocr.apiKeyEnvironment == nil {
      throw .config("OCR: an API key environment variable name is required for \(Self.displayName(for: ocrVendor))")
    }
    try config.validate()
    return config
  }

  @discardableResult
  public func save() -> Bool {
    do {
      try library.saveConfig(try draftConfig())
      error = nil
      savedAt = Date()
      onSaved?()
      return true
    } catch let failure as StriaError {
      error = failure.message
    } catch {
      self.error = error.localizedDescription
    }
    return false
  }

  private static func trimmed(_ value: String) -> String? {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
  }
}
