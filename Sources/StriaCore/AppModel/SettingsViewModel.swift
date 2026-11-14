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
  public static let ocrVendorOptions = [notConfigured, KnownVendors.pdfTextLayer] + KnownVendors.gateway
  /// API vendors whose credential variable name is set in Settings.
  public static let credentialVendors = KnownVendors.apiKeyVendors.sorted()

  public var ocrVendor = notConfigured
  public var ocrModel = ""
  public var ocrAPIKeyEnvironment = ""
  public var ocrAutoRunOnImport = true
  public var ocrConcurrency = 2
  /// Credential variable name per API vendor ("" = none).
  public var credentials: [String: String] = [:]
  /// The prompt as shown for editing; the default text when none is set.
  public var agentSystemPrompt = AgentDefaults.systemPrompt
  public private(set) var error: String?
  public private(set) var savedAt: Date?
  public var onSaved: (() -> Void)?
  /// Models fetched live from a vendor, keyed by vendor id.
  public private(set) var fetchedModels: [String: [String]] = [:]
  public private(set) var modelFetchError: String?
  public private(set) var isFetchingModels = false
  /// Value of the model picker that reveals the free-text field.
  public static let customModel = "__custom__"

  private let library: StriaLibrary
  private let modelLister: @Sendable (String, String?) async throws -> [String]
  private let processEnvironment: [String: String]

  public init(library: StriaLibrary,
              processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
              modelLister: @escaping @Sendable (String, String?) async throws -> [String] = {
                try await GatewayModelCatalogService.models(vendor: $0, apiKeyEnvironment: $1)
              }) {
    self.library = library
    self.processEnvironment = processEnvironment
    self.modelLister = modelLister
    load()
  }

  /// Whether the named variable is set in this app's environment.
  public func environmentHasValue(_ name: String) -> Bool {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let value = processEnvironment[trimmed] else { return false }
    return !value.isEmpty
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
    let vendor = ocrVendor
    let keyName = Self.trimmed(ocrAPIKeyEnvironment)
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
    ocrVendor = config.ocr.vendor ?? Self.notConfigured
    ocrModel = config.ocr.model ?? ""
    ocrAPIKeyEnvironment = config.ocr.apiKeyEnvironment ?? ""
    ocrAutoRunOnImport = config.ocr.autoRunOnImport
    ocrConcurrency = config.ocr.concurrency
    credentials = config.agent.credentials
    for vendor in Self.credentialVendors where credentials[vendor] == nil { credentials[vendor] = "" }
    agentSystemPrompt = config.agent.systemPrompt ?? AgentDefaults.systemPrompt
    error = nil
  }

  public var systemPromptIsDefault: Bool {
    agentSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines) == AgentDefaults.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public func resetSystemPrompt() { agentSystemPrompt = AgentDefaults.systemPrompt }

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
    config.ocr.vendor = ocrVendor == Self.notConfigured ? nil : ocrVendor
    config.ocr.model = Self.trimmed(ocrModel)
    config.ocr.apiKeyEnvironment = Self.trimmed(ocrAPIKeyEnvironment)
    config.ocr.autoRunOnImport = ocrAutoRunOnImport
    config.ocr.concurrency = ocrConcurrency
    config.agent.credentials = credentials.reduce(into: [:]) { result, entry in
      if let name = Self.trimmed(entry.value) { result[entry.key] = name }
    }
    // The default is stored as nil, so a future default change reaches users who never edited it.
    config.agent.systemPrompt = systemPromptIsDefault ? nil : Self.trimmed(agentSystemPrompt)
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
