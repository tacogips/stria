import SwiftUI
import StriaCore

/// Asks which pages to OCR before a run: the remaining pages, every page, or
/// a page list such as "1-3, 8". The sheet is the confirmation, so it names
/// the vendor and what happens to existing text.
struct OCRRunSheet: View {
  enum Choice: Hashable { case remaining, all, pages }

  let row: LibraryRow
  /// Prefills the page list (the reader passes its current page).
  var initialPages: String?
  let vendorDescription: String
  let run: (OCRRange) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var choice: Choice = .remaining
  @State private var pagesText = ""
  @FocusState private var pagesFocused: Bool

  private var remainingCount: Int { row.ocr.pending + row.ocr.failed }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Run OCR").font(.headline)
      Text(row.title).foregroundStyle(.secondary).lineLimit(2)
      VStack(alignment: .leading, spacing: 8) {
        radio(.remaining) {
          Text(remainingCount == 0
               ? "Remaining pages (none: every page is OCRed)"
               : "Remaining pages (\(remainingCount) not OCRed or failed)")
        }
        radio(.all) { Text(row.pageCount == 1 ? "The only page" : "All \(row.pageCount) pages") }
        radio(.pages) {
          HStack(spacing: 8) {
            Text("Pages")
            TextField("e.g. 1-3, 8", text: $pagesText)
              .textFieldStyle(FlatTextFieldStyle())
              .frame(width: 160)
              .focused($pagesFocused)
              .onSubmit(commit)
            Text("of \(row.pageCount)").foregroundStyle(.secondary)
          }
        }
      }
      .onChange(of: pagesFocused) { _, focused in if focused { choice = .pages } }

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

  private func radio<Label: View>(_ value: Choice, @ViewBuilder label: () -> Label) -> some View {
    HStack(spacing: 8) {
      Button {
        choice = value
        pagesFocused = value == .pages
      } label: {
        Image(systemName: choice == value ? "largecircle.fill.circle" : "circle")
          .foregroundStyle(choice == value ? Color.accentColor : Color.secondary)
      }
      .buttonStyle(.plain)
      .accessibilityAddTraits(choice == value ? [.isSelected] : [])
      label()
        .contentShape(Rectangle())
        .onTapGesture { choice = value }
    }
  }

  private var range: OCRRange {
    switch choice {
    case .remaining: .remaining
    case .all: .all
    case .pages: .pages(pagesText)
    }
  }

  /// The number of pages the run covers, or why the page list is invalid.
  private var validation: Result<Int, StriaError> {
    do {
      switch try range.selection(pageCount: row.pageCount) {
      case .pages(let pages): return .success(pages.count)
      case .pending, .pendingAndFailed: return .success(remainingCount)
      }
    } catch {
      return .failure(error)
    }
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
