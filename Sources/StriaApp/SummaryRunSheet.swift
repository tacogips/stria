import SwiftUI
import StriaCore

/// Asks which pages to summarize (again), in which language, and with what
/// extra instructions. Pages run one at a time in page order.
struct SummaryRunSheet: View {
  let row: LibraryRow
  let currentPage: Int
  /// OCRed pages without a current summary.
  let missingCount: Int
  let defaultLanguage: String
  let vendorDescription: String
  let run: (OCRRange, String?, String) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var choice: PageRangeChoice = .pages
  @State private var pagesText = ""
  @State private var instruction = ""
  @State private var language = PageSummaryLanguage.auto
  @FocusState private var pagesFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Summarize Pages").font(.headline)
      Text(row.title).foregroundStyle(.secondary).lineLimit(2)
      PageRangeChoices(
        choice: $choice, pagesText: $pagesText, pagesFocused: $pagesFocused,
        remainingLabel: missingCount == 0
          ? "Pages without a current summary (none)"
          : "Pages without a current summary (\(missingCount))",
        pageCount: row.pageCount, onSubmit: commit
      )
      Picker("Language", selection: $language) {
        ForEach(languageOptions, id: \.self) { Text(PageSummaryLanguage.displayName($0)).tag($0) }
      }
      .pickerStyle(.menu)
      VStack(alignment: .leading, spacing: 4) {
        Text("Instructions (optional)").font(.callout)
        TextEditor(text: $instruction)
          .font(.body)
          .frame(height: 72)
          .overlay(Rectangle().stroke(Flat.border, lineWidth: 1))
        Text("Added to the request, for example \"Focus on the figures\" or \"Keep it to three bullets\".")
          .font(.caption).foregroundStyle(.secondary)
      }
      Group {
        switch validation {
        case .success(let count):
          Text(count == 0 ? "Nothing to summarize."
               : "Calls \(vendorDescription) for \(count == 1 ? "1 page" : "\(count) pages"), one at a time in page order. "
               + "Pages without OCR text are OCRed first; existing summaries of the chosen pages are replaced.")
        case .failure(let error):
          Label(error.message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        }
      }
      .font(.callout)
      .fixedSize(horizontal: false, vertical: true)
      HStack {
        Spacer()
        Button("Cancel", role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("Summarize") { commit() }
          .keyboardShortcut(.defaultAction)
          .disabled(!canRun)
      }
    }
    .padding(20)
    .frame(width: 440)
    .onAppear {
      pagesText = String(currentPage)
      language = defaultLanguage
    }
  }

  private var languageOptions: [String] {
    PageSummaryLanguage.options.contains(defaultLanguage) ? PageSummaryLanguage.options : PageSummaryLanguage.options + [defaultLanguage]
  }

  private var range: OCRRange { choice.range(pagesText: pagesText) }

  private var validation: Result<Int, StriaError> {
    pageRangeValidation(range, pageCount: row.pageCount, remainingCount: missingCount)
  }

  private var canRun: Bool {
    if case .success(let count) = validation { return count > 0 }
    return false
  }

  private func commit() {
    guard canRun else { return }
    let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    run(range, trimmed.isEmpty ? nil : trimmed, language)
    dismiss()
  }
}
