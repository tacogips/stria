import SwiftUI
import StriaCore

/// Asks which pages to OCR before a run: the remaining pages, every page, or
/// a page list such as "1-3, 8". The sheet is the confirmation, so it names
/// the vendor and what happens to existing text.
struct OCRRunSheet: View {

  let row: LibraryRow
  /// Prefills the page list (the reader passes its current page).
  var initialPages: String?
  let vendorDescription: String
  let run: (OCRRange) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var choice: PageRangeChoice = .remaining
  @State private var pagesText = ""
  @FocusState private var pagesFocused: Bool

  private var remainingCount: Int { row.ocr.pending + row.ocr.failed }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Run OCR").font(.headline)
      Text(row.title).foregroundStyle(.secondary).lineLimit(2)
      PageRangeChoices(
        choice: $choice, pagesText: $pagesText, pagesFocused: $pagesFocused,
        remainingLabel: remainingCount == 0
          ? "Remaining pages (none: every page is OCRed)"
          : "Remaining pages (\(remainingCount) not OCRed or failed)",
        pageCount: row.pageCount, onSubmit: commit
      )

      Group {
        switch validation {
        case .success(let count):
          Text(summary(count: count))
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
        Button("Run OCR") { commit() }
          .keyboardShortcut(.defaultAction)
          .disabled(!canRun)
      }
    }
    .padding(20)
    .frame(width: 420)
    .onAppear {
      if let initialPages {
        pagesText = initialPages
        choice = .pages
        pagesFocused = true
      } else {
        choice = remainingCount > 0 ? .remaining : .all
      }
    }
  }

  private var range: OCRRange { choice.range(pagesText: pagesText) }

  private var validation: Result<Int, StriaError> {
    pageRangeValidation(range, pageCount: row.pageCount, remainingCount: remainingCount)
  }

  private var canRun: Bool {
    if case .success(let count) = validation { return count > 0 }
    return false
  }

  private func summary(count: Int) -> String {
    let pages = count == 1 ? "1 page" : "\(count) pages"
    switch choice {
    case .remaining:
      return count == 0 ? "Nothing to do." : "Calls \(vendorDescription) for \(pages). Pages already OCRed are kept."
    case .all, .pages:
      return "Calls \(vendorDescription) for \(pages). Existing OCR text on those pages is replaced;"
        + " a page that fails keeps no text until it is retried."
    }
  }

  private func commit() {
    guard canRun else { return }
    run(range)
    dismiss()
  }
}

extension SettingsViewModel {
  /// "Claude Code (claude-sonnet-5-5)" style text for OCR confirmations.
  var ocrVendorDescription: String {
    let name = SettingsViewModel.displayName(for: ocrVendor)
    guard SettingsViewModel.needsModel(ocrVendor) else { return name }
    return "\(name) (\(ocrModel.isEmpty ? "no model" : ocrModel))"
  }
}
