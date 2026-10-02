public enum OCRDefaults {
  public static let prompt = "Transcribe all text visible in this page image. "
    + "The text may be Japanese, English or both; vertical Japanese text is read top to bottom, right to left. "
    + "Preserve the reading order and line breaks. Keep numbers, dates and names exactly as printed and do not translate. "
    + "Write each table row on one line with cells separated by \" | \". "
    + "Output only the transcribed text with no commentary, headings or code fences. "
    + "If the page has no text at all, output exactly \(noTextSentinel)."

  /// What the model writes for a page without text; stored as empty text.
  public static let noTextSentinel = "[NO TEXT]"
}
