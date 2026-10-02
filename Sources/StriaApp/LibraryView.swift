import SwiftUI
import StriaCore
import UniformTypeIdentifiers

struct LibraryView: View {
  @Bindable var model: AppModel
  @FocusedValue(\.striaImport) private var importAction
  @State private var selection: String?
  @State private var pendingRemoval: LibraryRow?
  @State private var hoveredID: String?
  @AppStorage(LibraryViewMode.storageKey) private var viewMode = LibraryViewMode.list

  var body: some View {
    VStack(spacing: 0) {
      if !model.library.ocrConfigured || !model.library.agentConfigured {
        SetupBanner(ocrConfigured: model.library.ocrConfigured, agentConfigured: model.library.agentConfigured)
          .id(model.configRevision)
      }
      if model.library.isSearching {
        searchResults
      } else if viewMode == .card {
        documentCards
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

  /// A single click opens the document; the context menu holds the rest.
  private var documentList: some View {
    List(selection: $selection) {
      ForEach(model.library.rows) { row in
        LibraryRowView(row: row, thumbnail: model.library.thumbnails[row.id])
          .tag(row.id)
          .contentShape(Rectangle())
          .listRowBackground(
            hoveredID == row.id && selection != row.id
              ? Flat.hover
              : Color.clear
          )
          .onHover { hovering in hoveredID = hovering ? row.id : (hoveredID == row.id ? nil : hoveredID) }
          .onTapGesture { open(row.id) }
          .contextMenu { rowMenu(row) }
          .task(id: row.importStatus) { await model.library.loadThumbnail(documentId: row.id) }
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
    .focusedSceneValue(\.striaLibraryViewMode, $viewMode)
    .focusedSceneValue(\.striaRunOCR, { runOCRForSelection() })
    .toolbar {
      ToolbarItem(placement: .principal) {
        Picker("View", selection: $viewMode) {
          ForEach(LibraryViewMode.allCases, id: \.self) { mode in
            Label(mode.title, systemImage: mode == .list ? "list.bullet" : "square.grid.2x2").tag(mode)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("List or card view (Cmd-1 / Cmd-2)")
      }
    }
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
        Button { runOCRForSelection() } label: {
          Label("Run OCR", systemImage: "text.viewfinder")
        }
        .disabled(selection == nil || !model.library.ocrConfigured)
        .help(model.library.ocrConfigured ? "OCR the pending and failed pages of the selected document (Cmd-Shift-O)" : "Choose an OCR vendor in Settings first (Agent > Settings…)")
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

  private var documentCards: some View {
    ScrollView {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16)], spacing: 16) {
        ForEach(model.library.rows) { row in
          LibraryCardView(row: row, thumbnail: model.library.thumbnails[row.id], hovered: hoveredID == row.id)
            .onHover { hovering in hoveredID = hovering ? row.id : (hoveredID == row.id ? nil : hoveredID) }
            .onTapGesture { open(row.id) }
            .contextMenu { rowMenu(row) }
            .task(id: row.importStatus) { await model.library.loadThumbnail(documentId: row.id) }
        }
      }
      .padding(16)
    }
    .background(Flat.panel)
  }

  @ViewBuilder private func rowMenu(_ row: LibraryRow) -> some View {
    Button("Open") { open(row.id) }
    Divider()
    Button("Run OCR") { Task { await model.library.runOCR(documentId: row.id, retryFailed: false) } }
    Button("Retry Failed OCR") { Task { await model.library.runOCR(documentId: row.id, retryFailed: true) } }
    Divider()
    Button("Remove…", role: .destructive) { pendingRemoval = row }
  }

  private func runOCRForSelection() {
    guard let selection, model.library.ocrConfigured else { return }
    Task { await model.library.runOCR(documentId: selection, retryFailed: true) }
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

/// The first page as a small solid-bordered image, or a placeholder.
private struct PageThumbnail: View {
  let image: CGImage?
  let width: CGFloat
  let height: CGFloat

  var body: some View {
    Group {
      if let image {
        Image(decorative: image, scale: 1)
          .resizable()
          .aspectRatio(contentMode: .fit)
      } else {
        Rectangle().fill(Flat.assistantBubble)
          .overlay { Image(systemName: "doc.text").foregroundStyle(.secondary) }
      }
    }
    .frame(width: width, height: height)
    .background(Color.white)
    .overlay(Rectangle().stroke(Flat.border, lineWidth: 1))
  }
}

private struct LibraryRowView: View {
  let row: LibraryRow
  let thumbnail: CGImage?

  var body: some View {
    HStack(spacing: 12) {
      PageThumbnail(image: thumbnail, width: 44, height: 58)
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(row.title).font(.headline)
          Spacer()
          if let opened = row.lastOpenedAt {
            Text("Opened \(RelativeAge.string(from: opened))").font(.caption).foregroundStyle(.tertiary)
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

/// Card mode: the first page large, then the title and status.
private struct LibraryCardView: View {
  let row: LibraryRow
  let thumbnail: CGImage?
  let hovered: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      PageThumbnail(image: thumbnail, width: 164, height: 212)
        .frame(maxWidth: .infinity)
      Text(row.title).font(.headline).lineLimit(2)
      HStack {
        Text("\(row.pageCount) pages").font(.caption).foregroundStyle(.secondary)
        Spacer()
        if row.isBusy { ProgressView().controlSize(.mini) }
      }
      Text(statusText).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(hovered ? Flat.hover : Flat.assistantBubble)
    .overlay(Rectangle().stroke(Flat.border, lineWidth: 1))
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }

  private var statusText: String {
    if row.importStatus == .rendering { return "Rendering \(row.rendered)/\(row.pageCount)" }
    if row.unavailableReason == "not configured" { return "OCR not run (\(row.ocr.pending) pages)" }
    if let reason = row.unavailableReason { return "OCR unavailable: \(reason)" }
    if row.ocr.failed > 0 { return "OCR \(row.ocr.done)/\(row.pageCount), \(row.ocr.failed) failed" }
    if row.ocr.pending > 0 { return "OCR \(row.ocr.done)/\(row.pageCount)" }
    return "OCR \(row.ocr.done)/\(row.pageCount)"
  }
}
