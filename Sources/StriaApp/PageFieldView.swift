import SwiftUI
import StriaCore

/// The toolbar `n of N` field. It keeps its own text while focused, so a
/// scroll-driven page change never overwrites what the user is typing.
struct PageFieldView: View {
  @Bindable var reader: ReaderViewModel
  var compact = false
  @State private var text = ""
  @FocusState private var isFocused: Bool

  var body: some View {
    HStack(spacing: 6) {
      if !compact {
        Button { reader.previousPage() } label: { Image(systemName: "chevron.left") }
          .disabled(reader.currentPage <= 1)
          .help("Previous page (Cmd-Opt-Up)")
          .accessibilityLabel("Previous page")
      }
      TextField("Page", text: $text)
        .frame(width: compact ? 32 : 48)
        .multilineTextAlignment(.trailing)
        .textFieldStyle(.roundedBorder)
        .focused($isFocused)
        .onSubmit {
          reader.pageFieldText = text
          reader.commitPageField()
          text = reader.pageFieldText
          isFocused = false
        }
        .accessibilityLabel("Page number")
        .help("Type a page number and press Return (Cmd-Opt-G opens Go to Page)")
      Text(compact ? "/ \(reader.pageCount)" : "of \(reader.pageCount)").foregroundStyle(.secondary)
        .accessibilityLabel("Total pages")
      if !compact {
        Button { reader.nextPage() } label: { Image(systemName: "chevron.right") }
          .disabled(reader.currentPage >= reader.pageCount)
          .help("Next page (Cmd-Opt-Down)")
          .accessibilityLabel("Next page")
      }
    }
    .accessibilityElement(children: .contain)
    .onAppear { text = String(reader.currentPage) }
    .onChange(of: reader.currentPage) { _, page in
      if !isFocused { text = String(page) }
    }
    .onChange(of: isFocused) { _, focused in
      if !focused { text = String(reader.currentPage) }
    }
  }
}
