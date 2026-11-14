import SwiftUI
import StriaCore
import UniformTypeIdentifiers

struct MobileRootView: View {
  @Bindable var model: MobileModel
  @Environment(\.horizontalSizeClass) private var sizeClass

  var body: some View {
    Group {
      if sizeClass == .regular {
        NavigationSplitView {
          MobileLibraryView(model: model)
        } detail: {
          NavigationStack { detail }
        }
      } else {
        NavigationStack {
          MobileLibraryView(model: model)
            .navigationDestination(isPresented: $model.showingReader) { detail }
        }
      }
    }
    .sheet(isPresented: $model.showingSettings) {
      MobileSettingsView(settings: model.settings, sync: model.sync, showingVendors: model.showingVendors)
    }
    .sheet(isPresented: Binding(get: { model.search.isShowingResults && (sizeClass == .regular || !model.showingAgent) }, set: { if !$0 { model.search.close() } })) {
      MobileSearchResults(model: model)
    }
    .alert("Stria", isPresented: Binding(get: { model.library.alert != nil }, set: { if !$0 { model.library.alert = nil } })) {
      Button("OK", role: .cancel) { model.library.alert = nil }
    } message: { Text(model.library.alert ?? "") }
    .onChange(of: model.showingReader) { _, showing in
      if !showing { Task { await model.closeReader() } }
    }
  }

  @ViewBuilder private var detail: some View {
    if let reader = model.reader, let agent = model.agent {
      MobileReaderView(model: model, reader: reader, agent: agent)
        .id(reader.documentId)
    } else {
      ContentUnavailableView("Select a PDF", systemImage: "doc.richtext", description: Text("Import a PDF to start reading."))
    }
  }
}

struct MobileLibraryView: View {
  @Bindable var model: MobileModel
  @State private var importing = false
  @State private var removing: LibraryRow?

  var body: some View {
    List {
      if model.sync.isSyncing {
        HStack { ProgressView(); Text("Syncing with iCloud Drive") }.font(.caption)
      } else if let error = model.sync.lastError {
        Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
      }
      if model.library.isImporting { ProgressView("Importing PDF…") }
      ForEach(model.library.rows) { row in
        Button { Task { await model.open(documentId: row.id) } } label: {
          HStack(spacing: 12) {
            PageThumbnail(image: model.library.thumbnails[row.id])
            VStack(alignment: .leading, spacing: 6) {
              Text(row.title).font(.headline).foregroundStyle(.primary)
              Text("\(row.pageCount) pages").font(.caption).foregroundStyle(.secondary)
              HStack {
                Label("OCR \(row.ocr.done)/\(row.pageCount)", systemImage: "text.viewfinder")
                Label("Summary \(row.summaries?.done ?? 0)/\(row.pageCount)", systemImage: "text.alignleft")
              }
              .font(.caption2).foregroundStyle(.secondary)
              if row.isBusy { ProgressView() }
            }
          }
        }
        .task(id: row.importStatus) { await model.library.loadThumbnail(documentId: row.id) }
        .swipeActions {
          Button("Remove", role: .destructive) { removing = row }.tint(.red)
        }
      }
    }
    .listStyle(.plain)
    .overlay {
      if model.library.rows.isEmpty && !model.library.isImporting {
        ContentUnavailableView("Your PDF Library", systemImage: "books.vertical",
                               description: Text("Tap + to import PDFs from Files."))
      }
    }
    .navigationTitle("Stria")
    .searchable(text: Binding(get: { model.search.query }, set: { model.search.query = $0 }), prompt: "Search OCR across PDFs")
    .onSubmit(of: .search) { Task { await model.search.search(for: model.search.query) } }
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        Button { model.settings.load(); model.showingSettings = true } label: { Image(systemName: "gearshape") }
          .accessibilityLabel("Settings")
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button { importing = true } label: { Image(systemName: "plus") }.accessibilityLabel("Import PDFs")
      }
    }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
      switch result {
      case .success(let urls): Task { await model.importFiles(urls) }
      case .failure(let error): model.library.alert = error.localizedDescription
      }
    }
    .confirmationDialog("Remove \(removing?.title ?? "PDF") from your library?",
                        isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
      Button("Remove PDF", role: .destructive) {
        guard let row = removing else { return }
        Task {
          if model.reader?.documentId == row.id { await model.closeReader() }
          await model.library.remove(documentId: row.id)
        }
        removing = nil
      }
    }
  }
}

struct PageThumbnail: View {
  let image: CGImage?

  var body: some View {
    Group {
      if let image {
        Image(decorative: image, scale: 1).resizable().scaledToFit()
      } else {
        Image(systemName: "doc.richtext").font(.title).foregroundStyle(.secondary)
      }
    }
    .frame(width: 54, height: 72)
    .background(Flat.assistantBubble)
    .overlay(Rectangle().stroke(Flat.border, lineWidth: 1))
    .accessibilityHidden(true)
  }
}

struct MobileSearchResults: View {
  let model: MobileModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List(model.search.results.indices, id: \.self) { index in
        let hit = model.search.results[index]
        Button {
          dismiss()
          model.search.close()
          model.showingAgent = false
          Task { await model.open(documentId: hit.docId, page: hit.page) }
        } label: {
          HStack(alignment: .top) {
            PageThumbnail(image: model.search.thumbnails[SearchViewModel.thumbnailKey(docId: hit.docId, page: hit.page)])
            VStack(alignment: .leading) {
              Text("\(hit.title) · p. \(hit.page)").font(.headline)
              Text(highlighted(hit)).lineLimit(5)
            }
          }
        }
        .task { await model.search.loadThumbnail(docId: hit.docId, page: hit.page) }
      }
      .listStyle(.plain)
      .overlay {
        if let error = model.search.error {
          ContentUnavailableView("Search Failed", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if model.search.results.isEmpty {
          ContentUnavailableView.search(text: model.search.resultsQuery)
        }
      }
      .navigationTitle("OCR Search")
      .toolbar { Button("Done") { dismiss(); model.search.close() } }
    }
  }

  private func highlighted(_ hit: SearchResultItem) -> AttributedString {
    let segments = hit.context.isEmpty ? SearchContextBuilder.segments(fromBracketedSnippet: hit.snippet) : hit.context
    var result = AttributedString()
    for segment in segments {
      var part = AttributedString(segment.text)
      if segment.isHit { part.backgroundColor = .yellow; part.foregroundColor = .black }
      result += part
    }
    return result
  }
}
