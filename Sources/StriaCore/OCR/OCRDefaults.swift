public enum OCRDefaults {
  public static let prompt = "Transcribe all text visible in this page image. "
    + "The text may be Japanese, English or both; vertical Japanese text is read top to bottom, right to left. "
    + "Preserve the reading order and line breaks. Keep numbers, dates and names exactly as printed and do not translate. "
    + "Write each table row on one line with cells separated by \" | \". "
    + "Transcribe only; add no commentary or headings."

  /// What the model writes for a page without text; stored as empty text.
  public static let noTextSentinel = "[NO TEXT]"

  /// Appended to every model OCR prompt (default or custom), so an edited
  /// prompt cannot break the reply contract that `OCRReplyParser` checks.
  public static let jsonFormatInstruction = """
    Reply with only one JSON object and nothing else (no code fences, no commentary), in exactly this shape:
    {"body": "<the transcribed text of the page>", "tags": ["<tag>", "<tag>"]}
    - body: the full transcription as instructed above, with line breaks written as \\n. Use "" when the page has no text.
    - tags: 3 to 20 short tags for the page's key terms, people, organizations, places, events and dates, written as \
    they appear on the page, without duplicates. Use [] when the page has no text.
    """

  /// Retries of a reply that is not the JSON object, by default.
  public static let formatRetries = 2
}
