import AppKit
import SwiftUI
import StriaCore
import UniformTypeIdentifiers

/// A document waiting for the user to confirm an OCR run.
struct PendingOCR: Identifiable {
  enum Kind { case remaining, allPages }
  let row: LibraryRow
  let kind: Kind
  var id: String { row.id + (kind == .allPages ? "-all" : "-remaining") }
}

struct LibraryView: View {
  @Bindable var model: AppModel
  @FocusedValue(\.striaImport) private var importAction
  @State private var selection: String?
  @State private var pendingRemoval: LibraryRow?
  /// A document waiting for the user to confirm an OCR run.
  @State private var pendingOCR: PendingOCR?

  @State private var hoveredID: String?
  @AppStorage(LibraryViewMode.storageKey) private var viewMode = LibraryViewMode.list
  @State private var keys = LocalKeyMonitor()

  var body: some View {
    withDialogs
  }

  private var content: some View {
    VStack(spacing: 0) {
      if !model.library.ocrConfigured {
        SetupBanner()
          .id(model.configRevision)
      }
      if model.search.isShowingResults {
        SearchResultsView(search: model.search) { hit in Task { await model.openSearchResult(hit) } }
      } else if model.library.rows.isEmpty {
        emptyLibrary
      } else if viewMode == .card {
        documentCards
      } else {
        documentList
      }
    }
    .sheet(isPresented: Bindable(model.search).isPromptPresented) {
      SearchPrompt(search: model.search)
    }
    .focusedSceneValue(\.striaSearch, { model.search.present() })
    .onAppear { keys.install(handleKey) }
    .onDisappear { keys.remove() }
  }

  private var withNavigation: some View {
    content
    .navigationTitle("Library")
    .navigationSubtitle(subtitle)
    .focusedSceneValue(\.striaLibraryViewMode, $viewMode)
    .focusedSceneValue(\.striaRunOCR, { runOCRForSelection() })
  }

  private var subtitle: String {
    let count = model.library.rows.count
    return count == 1 ? "1 PDF" : "\(count) PDFs"
  }

  private var withActions: some View {
    withNavigation
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
      // Native controls only: the system sizes their toolbar capsules.
      ToolbarItem(placement: .navigation) {
        Picker("View", selection: $viewMode) {
          Image(systemName: "list.bullet").tag(LibraryViewMode.list)
            .accessibilityLabel("List")
          Image(systemName: "square.grid.2x2").tag(LibraryViewMode.card)
            .accessibilityLabel("Cards")
        }
        .pickerStyle(.segmented)
        .help("List (Cmd-1) or cards (Cmd-2)")
      }
      ToolbarItemGroup(placement: .primaryAction) {
        Button { model.search.present() } label: {
          Label("Search", systemImage: "magnifyingglass")
        }
        .help("Search the OCR text of all PDFs (/ or Cmd-F)")
        Button { runOCRForSelection() } label: {
          Label("Run OCR", systemImage: "text.viewfinder")
        }
        .disabled(selection == nil || !model.library.ocrConfigured)
        .help(model.library.ocrConfigured
              ? "OCR the selected PDF (Cmd-Shift-O): remaining pages, or all pages again when it is complete. Asks first."
              : "Choose an OCR vendor in Settings first (Agent > Settings…)")
        Button { importAction?() } label: {
          Label("Import PDF", systemImage: "plus")
            .labelStyle(.titleAndIcon)
        }
        .help("Add PDF files to the library (Cmd-O); you can also drop them on the window")
      }
    }
  }

  private var withDialogs: some View {
    withActions
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
      pendingOCR.map(confirmationTitle) ?? "",
      isPresented: Binding(get: { pendingOCR != nil }, set: { if !$0 { pendingOCR = nil } }),
      presenting: pendingOCR
    ) { pending in
      Button(pending.kind == .allPages ? "Re-OCR All Pages" : "Run OCR") {
        switch pending.kind {
        case .remaining: Task { await model.library.runOCR(documentId: pending.row.id, retryFailed: true) }
        case .allPages: Task { await model.library.rerunOCRAllPages(documentId: pending.row.id) }
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: { pending in
      Text(confirmationMessage(pending))
    }
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

  /// `/` opens the search popup and Esc closes search results (single keys,
  /// paused while typing, as in the reader).
  private func handleKey(_ event: NSEvent) -> Bool {
    guard event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else { return false }
    if event.charactersIgnoringModifiers == "/" { model.search.present(); return true }
    if event.keyCode == 53, model.search.isShowingResults { model.search.close(); return true }
    return false
  }

  private var emptyLibrary: some View {
    ContentUnavailableView {
      Label("Your Library Is Empty", systemImage: "books.vertical")
    } description: {
      Text("Import a PDF to start reading. You can also drop PDF files here.")
    } actions: {
      Button("Import PDF…") { importAction?() }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

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
    Button("Run OCR on Remaining Pages…") { pendingOCR = PendingOCR(row: row, kind: .remaining) }
      .disabled(!model.library.ocrConfigured || row.ocr.pending + row.ocr.failed == 0)
    Button("Re-OCR All Pages…") { pendingOCR = PendingOCR(row: row, kind: .allPages) }
      .disabled(!model.library.ocrConfigured)
    Divider()
    Button("Remove…", role: .destructive) { pendingRemoval = row }
  }

  private func runOCRForSelection() {
    guard let selection, model.library.ocrConfigured,
          let row = model.library.rows.first(where: { $0.id == selection }) else { return }
    pendingOCR = PendingOCR(row: row, kind: row.ocr.pending + row.ocr.failed > 0 ? .remaining : .allPages)
  }

  private func confirmationTitle(_ pending: PendingOCR) -> String {
    switch pending.kind {
    case .remaining: "Run OCR on \(pending.row.ocr.pending + pending.row.ocr.failed) pages of \"\(pending.row.title)\"?"
    case .allPages: "Re-OCR all \(pending.row.pageCount) pages of \"\(pending.row.title)\"?"
    }
  }

  private func confirmationMessage(_ pending: PendingOCR) -> String {
    let vendor = model.settings.ocrVendor
    let using = "This calls \(SettingsViewModel.displayName(for: vendor)) (\(model.settings.ocrModel.isEmpty ? "no model" : model.settings.ocrModel)) once per page."
    switch pending.kind {
    case .remaining: return using + " Pages already OCRed are kept."
    case .allPages: return using + " Existing OCR text is replaced; a page that fails keeps no text until it is retried."
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
        HStack(spacing: 8) {
          if row.importStatus == .ready { OCRBadge(row: row) }
          Text(statusText).font(.caption).foregroundStyle(.secondary)
        }
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
  private let message = "Choose an OCR vendor to make imported pages searchable."

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
      if row.importStatus == .ready { OCRBadge(row: row) }
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

/// A compact OCR status badge: done, partial, not started, or failures.
struct OCRBadge: View {
  let row: LibraryRow

  var body: some View {
    Label(text, systemImage: symbol)
      .font(.caption.bold())
      .foregroundStyle(color)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .overlay(Rectangle().stroke(color, lineWidth: 1))
      .help(help)
  }

  private var text: String {
    switch row.ocrState {
    case .complete: "OCR done"
    case .partial: "OCR \(row.ocr.done)/\(row.pageCount)"
    case .notStarted: "Not OCRed"
    case .hasFailures: "OCR \(row.ocr.failed) failed"
    }
  }

  private var symbol: String {
    switch row.ocrState {
    case .complete: "checkmark.circle"
    case .partial: "circle.lefthalf.filled"
    case .notStarted: "circle.dashed"
    case .hasFailures: "exclamationmark.triangle"
    }
  }

  private var color: Color {
    switch row.ocrState {
    case .complete: .green
    case .partial: .blue
    case .notStarted: .secondary
    case .hasFailures: .orange
    }
  }

  private var help: String {
    "\(row.ocr.done) of \(row.pageCount) pages OCRed, \(row.ocr.pending) pending, \(row.ocr.failed) failed. Right-click to run or redo OCR."
  }
}
