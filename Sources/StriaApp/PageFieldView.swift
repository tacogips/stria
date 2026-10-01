import SwiftUI
import StriaCore

struct PageFieldView: View {
  @Bindable var reader: ReaderViewModel

  var body: some View {
    HStack(spacing: 6) {
      Button { reader.previousPage() } label: { Image(systemName: "chevron.left") }
        .disabled(reader.currentPage <= 1)
        .help("Previous Page")
      TextField("Page", text: $reader.pageFieldText)
        .frame(width: 48)
        .multilineTextAlignment(.trailing)
        .textFieldStyle(.roundedBorder)
        .onSubmit { reader.commitPageField() }
        .accessibilityLabel("Page number")
      Text("of \(reader.pageCount)").foregroundStyle(.secondary)
      Button { reader.nextPage() } label: { Image(systemName: "chevron.right") }
        .disabled(reader.currentPage >= reader.pageCount)
        .help("Next Page")
    }
  }
}
