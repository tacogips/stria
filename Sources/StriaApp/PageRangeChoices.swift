import SwiftUI
import StriaCore

enum PageRangeChoice: Hashable {
  case remaining, all, pages

  func range(pagesText: String) -> OCRRange {
    switch self {
    case .remaining: .remaining
    case .all: .all
    case .pages: .pages(pagesText)
    }
  }
}

/// Radio choices shared by the OCR and summary run sheets: a "remaining"
/// set, every page, or a page list such as "1-3, 8".
struct PageRangeChoices: View {
  @Binding var choice: PageRangeChoice
  @Binding var pagesText: String
  var pagesFocused: FocusState<Bool>.Binding
  let remainingLabel: String
  let pageCount: Int
  let onSubmit: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      radio(.remaining) { Text(remainingLabel) }
      radio(.all) { Text(pageCount == 1 ? "The only page" : "All \(pageCount) pages") }
      radio(.pages) {
        HStack(spacing: 8) {
          Text("Pages")
          TextField("e.g. 1-3, 8", text: $pagesText)
            .textFieldStyle(FlatTextFieldStyle())
            .frame(width: 160)
            .focused(pagesFocused)
            .onSubmit(onSubmit)
          Text("of \(pageCount)").foregroundStyle(.secondary)
        }
      }
    }
    .onChange(of: pagesFocused.wrappedValue) { _, focused in if focused { choice = .pages } }
  }

  private func radio<Label: View>(_ value: PageRangeChoice, @ViewBuilder label: () -> Label) -> some View {
    HStack(spacing: 8) {
      Button {
        choice = value
        pagesFocused.wrappedValue = value == .pages
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
}

/// The number of pages a range covers, or why its page list is invalid;
/// `remainingCount` stands for `.remaining`.
func pageRangeValidation(_ range: OCRRange, pageCount: Int, remainingCount: Int) -> Result<Int, StriaError> {
  do {
    switch try range.selection(pageCount: pageCount) {
    case .pages(let pages): return .success(pages.count)
    case .pending, .pendingAndFailed: return .success(remainingCount)
    }
  } catch {
    return .failure(error)
  }
}
