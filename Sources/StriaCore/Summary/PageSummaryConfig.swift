import Foundation

private enum SummaryConfigCodingKeys: String, CodingKey {
  case vendor, model, prompt, language, autoRunAfterOCR, timeoutSeconds
}

public extension StriaConfig {
  /// Per-page summaries written after OCR. They are stored apart from the OCR
  /// text and never searched.
  struct SummaryConfig: Codable, Equatable, Sendable {
    /// nil means not configured: nothing is summarized.
    public var vendor: String?
    public var model: String?
    /// The prompt template; nil means `PageSummaryDefaults.prompt`.
    /// `{language}` is replaced with the chosen language.
    public var prompt: String?
    /// A language name such as "Japanese", or "auto" for the page's language.
    public var language: String
    /// Summarize the pages an OCR run finished, right after it.
    public var autoRunAfterOCR: Bool
    /// Upper bound for one page's model call.
    public var timeoutSeconds: Int

    public var isConfigured: Bool { vendor != nil }

    public init(vendor: String? = nil, model: String? = nil, prompt: String? = nil,
                language: String = PageSummaryLanguage.auto, autoRunAfterOCR: Bool = false, timeoutSeconds: Int = 300) {
      self.vendor = vendor; self.model = model; self.prompt = prompt
      self.language = language; self.autoRunAfterOCR = autoRunAfterOCR; self.timeoutSeconds = timeoutSeconds
    }

    public init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: SummaryConfigCodingKeys.self)
      func optional(_ key: SummaryConfigCodingKeys) throws -> String? {
        guard c.contains(key), try !c.decodeNil(forKey: key) else { return nil }
        return try c.decode(String.self, forKey: key)
      }
      self.init(vendor: try optional(.vendor), model: try optional(.model), prompt: try optional(.prompt),
                language: try c.decodeIfPresent(String.self, forKey: .language) ?? PageSummaryLanguage.auto,
                autoRunAfterOCR: try c.decodeIfPresent(Bool.self, forKey: .autoRunAfterOCR) ?? false,
                timeoutSeconds: try c.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 300)
    }

    public func encode(to encoder: Encoder) throws {
      var c = encoder.container(keyedBy: SummaryConfigCodingKeys.self)
      try c.encode(vendor, forKey: .vendor); try c.encode(model, forKey: .model)
      try c.encode(prompt, forKey: .prompt); try c.encode(language, forKey: .language)
      try c.encode(autoRunAfterOCR, forKey: .autoRunAfterOCR); try c.encode(timeoutSeconds, forKey: .timeoutSeconds)
    }

    func validate() throws(StriaError) {
      guard (10...3600).contains(timeoutSeconds) else { throw .config("summary.timeoutSeconds must be 10...3600") }
      if let vendor, !KnownVendors.gateway.contains(vendor) { throw .config("Unknown summary vendor '\(vendor)'") }
      let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, trimmed.count <= 64 else { throw .config("summary.language must be 1...64 characters") }
    }
  }
}

/// The languages the Settings picker offers; any other name also works.
public enum PageSummaryLanguage {
  public static let auto = "auto"
  public static let options = [
    auto, "English", "Japanese", "Chinese (Simplified)", "Chinese (Traditional)", "Korean", "French", "German",
    "Spanish", "Portuguese", "Italian", "Russian"
  ]

  public static func displayName(_ language: String) -> String {
    language == auto ? "Same as the page" : language
  }

  /// The text that replaces `{language}` in the prompt template.
  public static func promptValue(_ language: String) -> String {
    language == auto ? "the same language as the target page's text" : language
  }
}

public enum PageSummaryDefaults {
  /// The default template. `{language}` is replaced before each call.
  public static let prompt = """
    You summarize one page of a PDF for a reader who skims the document page by page in Stria.
    Write the summary in {language}.
    Summarize only the target page: its main points, key facts, figures, names and conclusions, as three to six short \
    bullet points (fewer for a short page). The previous page's text and summary are context only: use them to \
    understand a sentence, list or table that continues onto the target page, and do not summarize the previous page again.
    Do not add anything that is not on the target page. Output only the summary, with no heading or preamble.
    """

  public static let placeholder = "{language}"

  /// The template with `{language}` filled in.
  public static func render(_ template: String, language: String) -> String {
    template.replacingOccurrences(of: placeholder, with: PageSummaryLanguage.promptValue(language))
  }
}
