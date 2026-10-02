import SwiftUI
import StriaCore
import UniformTypeIdentifiers

struct LibraryView: View {
  @Bindable var model: AppModel
  @FocusedValue(\.striaImport) private var importAction
  @State private var selection: String?
  @State private var pendingRemoval: LibraryRow?
  @State private var hoveredID: String?

  var body: some View {
    VStack(spacing: 0) {
      if !model.library.ocrConfigured || !model.library.agentConfigured {
        SetupBanner(ocrConfigured: model.library.ocrConfigured, agentConfigured: model.library.agentConfigured)
          .id(model.configRevision)
      }
      if model.library.isSearching {
        searchResults
      } else {
        documentList
      }
    }
    .searchable(text: searchQuery, placement: .toolbar, prompt: "Search OCR text in all PDFs")
    .onSubmit(of: .search) { Task { await model.library.submitSearch() } }
    .onChange(of: model.library.searchQuery) { _, query in
      if query.isEmpty { model.library.clearSearch() }
    }
  }

  private var searchQuery: Binding<String> {
    Binding(get: { model.library.searchQuery }, set: { model.library.searchQuery = $0 })
  }

  /// OCR hits across the library; a click opens the document at that page.
  private var searchResults: some View {
    Group {
      if let error = model.library.searchError {
        ContentUnavailableView("Search Failed", systemImage: "exclamationmark.triangle", description: Text(error))
      } else if model.library.searchResults.isEmpty {
        ContentUnavailableView.search(text: model.library.searchQuery)
      } else {
        List(model.library.searchResults.indices, id: \.self) { index in
          let hit = model.library.searchResults[index]
          Button {
            Task { await model.open(documentId: hit.docId, page: hit.page) }
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              HStack {
                Text(hit.title).font(.headline)
                Text("p. \(hit.page)").foregroundStyle(.secondary)
              }
              Text(hit.snippet).lineLimit(2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .padding(.vertical, 2)
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
      }
    }
  }

  private var documentList: some View {
    List(selection: $selection) {
      ForEach(model.library.rows) { row in
        LibraryRowView(row: row)
          .tag(row.id)
          .contentShape(Rectangle())
          .listRowBackground(
            hoveredID == row.id && selection != row.id
              ? Flat.hover
              : Color.clear
          )
          .onHover { hovering in hoveredID = hovering ? row.id : (hoveredID == row.id ? nil : hoveredID) }
          .onTapGesture(count: 2) { open(row.id) }
          .contextMenu {
            Button("Open") { open(row.id) }
            Divider()
            Button("Run OCR") { Task { await model.library.runOCR(documentId: row.id, retryFailed: false) } }
            Button("Retry Failed OCR") { Task { await model.library.runOCR(documentId: row.id, retryFailed: true) } }
            Divider()
            Button("Remove…", role: .destructive) { pendingRemoval = row }
          }
      }
    }
    .listStyle(.inset(alternatesRowBackgrounds: true))
    .overlay {
      if model.library.rows.isEmpty {
        ContentUnavailableView {
          Label("Your Library Is Empty", systemImage: "books.vertical")
        } description: {
          Text("Import a PDF to start reading. You can also drop PDF files here.")
        } actions: {
          Button("Import PDF…") { importAction?() }
        }
      }
    }
    .navigationTitle("Library")
    .onKeyPress(.return) {
      guard let selection else { return .ignored }
      open(selection)
      return .handled
    }
    .onDeleteCommand {
      guard let selection, let row = model.library.rows.first(where: { $0.id == selection }) else { return }
      pendingRemoval = row
    }
    .dropDestination(for: URL.self) { urls, _ in
      importDropped(urls)
      return !urls.isEmpty
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button { importAction?() } label: { Label("Import", systemImage: "square.and.arrow.down") }
          .help("Import PDF files (Cmd-O)")
      }
      ToolbarItem(placement: .primaryAction) {
        Button {
          guard let selection else { return }
          Task { await model.library.runOCR(documentId: selection, retryFailed: true) }
        } label: {
          Label("Run OCR", systemImage: "text.viewfinder")
        }
        .disabled(selection == nil || !model.library.ocrConfigured)
        .help(model.library.ocrConfigured ? "OCR the pending and failed pages of the selected document" : "Choose an OCR vendor in Settings first")
      }
    }
    .alert("Error", isPresented: Binding(
      get: { model.library.alert != nil },
      set: { if !$0 { model.library.alert = nil } }
    )) {
      Button("OK", role: .cancel) { model.library.alert = nil }
    } message: {
      Text(model.library.alert ?? "")
    }
    .onChange(of: model.library.selectedID) { _, id in selection = id }
    .confirmationDialog(
      "Remove \"\(pendingRemoval?.title ?? "")\"?",
      isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
      presenting: pendingRemoval
    ) { row in
      Button("Remove", role: .destructive) { Task { await model.library.remove(documentId: row.id) } }
      Button("Cancel", role: .cancel) {}
    } message: { _ in
      Text("This deletes the stored copy, page images, OCR text and chat history for this document. The file you imported is not touched.")
    }
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
    HStack(spacing: 10) {
      Image(systemName: "doc.richtext")
        .font(.title2)
        .foregroundStyle(.secondary)
        .frame(width: 28)
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(row.title).font(.headline)
          Spacer()
          if let opened = row.lastOpenedAt {
            Text("Opened \(opened, style: .relative) ago").font(.caption).foregroundStyle(.tertiary)
          }
          Text("\(row.pageCount) pages").foregroundStyle(.secondary)
        }
        Text(statusText).font(.caption).foregroundStyle(.secondary)
      }
      if row.isBusy {
        ProgressView().controlSize(.small)
      }
    }
    .padding(.vertical, 6)
    .accessibilityElement(children: .combine)
  }

  private var statusText: String {
    if row.importStatus == .rendering { return "Rendering \(row.rendered)/\(row.pageCount)" }
    if row.unavailableReason == "not configured" { return "OCR not run: choose a vendor in Settings, then Run OCR (\(row.ocr.pending) pages)" }
    if let reason = row.unavailableReason { return "OCR unavailable: \(reason)" }
    if row.ocr.failed > 0 { return "OCR \(row.ocr.done)/\(row.pageCount), \(row.ocr.failed) failed" }
    if row.ocr.pending > 0 { return "OCR \(row.ocr.done)/\(row.pageCount)" }
    return "Ready · OCR \(row.ocr.done)/\(row.pageCount)"
  }
}

/// Shown until both vendors are chosen; opens the Settings window.
private struct SetupBanner: View {
  let ocrConfigured: Bool
  let agentConfigured: Bool

  private var message: String {
    switch (ocrConfigured, agentConfigured) {
    case (false, false): "Choose an OCR vendor and an agent vendor to enable text search and questions."
    case (false, true): "Choose an OCR vendor to make imported pages searchable."
    default: "Choose an agent vendor to ask questions about pages."
    }
  }

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "gearshape").foregroundStyle(.secondary)
      Text(message).font(.callout)
      Spacer()
      SettingsLink { Text("Open Settings…") }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(Flat.banner)
    Divider()
  }
}
