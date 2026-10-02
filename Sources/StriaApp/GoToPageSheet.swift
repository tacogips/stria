import SwiftUI
import StriaCore

struct GoToPageSheet: View {
  @Bindable var reader: ReaderViewModel
  @Binding var isPresented: Bool
  @State private var text = ""
  @FocusState private var isFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Go to Page").font(.headline)
      HStack {
        TextField("Page number", text: $text)
          .textFieldStyle(.roundedBorder)
          .focused($isFocused)
          .onSubmit(commit)
        Text("of \(reader.pageCount)").foregroundStyle(.secondary)
      }
      HStack {
        Spacer()
        Button("Cancel", role: .cancel) { isPresented = false }
          .keyboardShortcut(.cancelAction)
        Button("Go") { commit() }
          .keyboardShortcut(.defaultAction)
          .disabled(Int(text.trimmingCharacters(in: .whitespaces)) == nil)
      }
    }
    .padding(20)
    .frame(width: 320)
    .onAppear {
      text = String(reader.currentPage)
      isFocused = true
    }
  }

  private func commit() {
    guard let page = Int(text.trimmingCharacters(in: .whitespaces)) else { return }
    reader.goToPage(page)
    isPresented = false
  }
}
