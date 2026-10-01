import SwiftUI
import StriaCore

struct GoToPageSheet: View {
  @Bindable var reader: ReaderViewModel
  @Binding var isPresented: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Go to Page").font(.headline)
      HStack {
        TextField("Page number", text: $reader.pageFieldText)
          .textFieldStyle(.roundedBorder)
          .onSubmit(commit)
        Text("of \(reader.pageCount)").foregroundStyle(.secondary)
      }
      HStack {
        Spacer()
        Button("Cancel", role: .cancel) { isPresented = false }
          .keyboardShortcut(.cancelAction)
        Button("Go") { commit() }
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 320)
  }

  private func commit() {
    reader.commitPageField()
    isPresented = false
  }
}
