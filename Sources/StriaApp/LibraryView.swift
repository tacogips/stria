import SwiftUI
import StriaCore
import UniformTypeIdentifiers

struct LibraryView: View {
  @Bindable var model: AppModel
  @FocusedValue(\.striaImport) private var importAction
  @State private var selection: String?

  var body: some View {
    List(selection: $selection) {
      if model.library.rows.isEmpty {
        ContentUnavailableView {
          Label("Your Library Is Empty", systemImage: "books.vertical")
        } description: {
          Text("Import a PDF to start reading. You can also drop PDF files here.")
        } actions: {
          Button("Import PDF…") { importAction?() }
            .keyboardShortcut("o", modifiers: .command)
        }
      } else {
        ForEach(model.library.rows) { row in
          LibraryRowView(row: row)
            .tag(row.id)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { open(row.id) }
            .contextMenu {
              Button("Open") { open(row.id) }
              Divider()
              Button("Run OCR") { Task { await model.library.runOCR(documentId: row.id, retryFailed: false) } }
              Button("Retry Failed OCR") { Task { await model.library.runOCR(documentId: row.id, retryFailed: true) } }
            }
        }
      }
    }
    .onKeyPress(.return) {
      guard let selection else { return .ignored }
      open(selection)
      return .handled
    }
    .dropDestination(for: URL.self) { urls, _ in
      importDropped(urls)
      return !urls.isEmpty
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button { importAction?() } label: { Label("Import", systemImage: "square.and.arrow.down") }
          .keyboardShortcut("o", modifiers: .command)
      }
    }
    .alert("Import Error", isPresented: Binding(
      get: { model.library.alert != nil },
      set: { if !$0 { model.library.alert = nil } }
    )) {
      Button("OK", role: .cancel) { model.library.alert = nil }
    } message: {
      Text(model.library.alert ?? "")
    }
    .onChange(of: model.library.selectedID) { _, id in selection = id }
  }

  private func open(_ id: String) {
    model.library.selectedID = id
    Task { await model.open(documentId: id) }
  }

  private func importDropped(_ urls: [URL]) {
    let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
    model.library.importFiles(urls)
    Task {
      await model.library.waitForImports()
      scoped.forEach { $0.stopAccessingSecurityScopedResource() }
    }
  }
}

private struct LibraryRowView: View {
  let row: LibraryRow

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(row.title).font(.headline)
        Spacer()
        Text("\(row.pageCount) pages").foregroundStyle(.secondary)
      }
      Text(statusText).font(.caption).foregroundStyle(.secondary)
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
  }

  private var statusText: String {
    if row.importStatus == .rendering { return "Rendering \(row.rendered)/\(row.pageCount)" }
    if let reason = row.unavailableReason { return "OCR unavailable: \(reason)" }
    if row.ocr.failed > 0 { return "OCR \(row.ocr.done)/\(row.pageCount), \(row.ocr.failed) failed" }
    if row.ocr.pending > 0 { return "OCR \(row.ocr.done)/\(row.pageCount)" }
    return "Ready · OCR \(row.ocr.done)/\(row.pageCount)"
  }
}
