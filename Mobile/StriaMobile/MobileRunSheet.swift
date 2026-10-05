import SwiftUI
import StriaCore

/// Confirms the page range and replacement behavior before OCR or summaries.
struct MobileRunSheet: View {
  let row: LibraryRow
  let currentPage: Int
  let settings: SettingsViewModel
  let library: LibraryViewModel
  let summary: Bool
  @Environment(\.dismiss) private var dismiss
  @State private var choice = "pages"
  @State private var pages = ""
  @State private var language = PageSummaryLanguage.auto
  @State private var instruction = ""
  @State private var missing = 0

  private var range: OCRRange {
    switch choice {
    case "remaining": .remaining
    case "all": .all
    default: .pages(pages)
    }
  }

  private var validation: Result<Int, StriaError> {
    do {
      switch try range.selection(pageCount: row.pageCount) {
      case .pages(let selected): return .success(selected.count)
      case .pending, .pendingAndFailed: return .success(summary ? missing : row.ocr.pending + row.ocr.failed)
      }
    } catch { return .failure(error) }
  }

  private var canRun: Bool {
    if case .success(let count) = validation { return count > 0 && (summary ? library.summaryConfigured : library.ocrConfigured) }
    return false
  }

  var body: some View {
    NavigationStack {
      List {
        Section(row.title) {
          Picker("Pages", selection: $choice) {
            Text(summary ? "Without a current summary" : "Not OCRed or failed").tag("remaining")
            Text("All \(row.pageCount) pages").tag("all")
            Text("Page list").tag("pages")
          }
          if choice == "pages" { TextField("e.g. 1-3, 8", text: $pages) }
        }
        if summary {
          Section("Summary") {
            Picker("Language", selection: $language) {
              ForEach(settings.summaryLanguageOptions, id: \.self) { Text(PageSummaryLanguage.displayName($0)).tag($0) }
            }
            TextField("Extra instructions (optional)", text: $instruction, axis: .vertical).lineLimit(3...6)
          }
        }
        Section {
          switch validation {
          case .success(let count): Text("\(count) pages using \(vendorDescription).")
          case .failure(let error): Text(error.message).foregroundStyle(.orange)
          }
          Text(summary
               ? "Pages without OCR text are OCRed first. Chosen summaries are replaced, one page at a time."
               : "All or listed pages replace their existing OCR text. Remaining keeps pages already OCRed.")
            .font(.caption).foregroundStyle(.secondary)
          Button(summary ? "Summarize" : "Run OCR") { commit() }.disabled(!canRun)
        }
      }
      .listStyle(.plain)
      .background(Flat.panel)
      .navigationTitle(summary ? "Summarize Pages" : "Run OCR")
      .toolbar { Button("Cancel") { dismiss() } }
      .task {
        pages = String(currentPage)
        language = settings.summaryLanguage
        missing = await library.pagesNeedingSummary(documentId: row.id)
      }
    }
  }

  private var vendorDescription: String {
    summary ? library.summaryVendorDescription : SettingsViewModel.displayName(for: settings.ocrVendor) + " \(settings.ocrModel)"
  }

  private func commit() {
    guard canRun else { return }
    let selected = range
    let extra = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    Task {
      if summary {
        await library.summarizePages(documentId: row.id, range: selected, instruction: extra.isEmpty ? nil : extra, language: language)
      } else { await library.runOCR(documentId: row.id, range: selected) }
    }
    dismiss()
  }
}
