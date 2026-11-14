import AppKit
import SwiftUI
import StriaCore

/// The search popup (menu Edit > Search OCR Text…, Cmd-F, or `/`).
struct SearchPrompt: View {
  @Bindable var search: SearchViewModel
  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField("Search OCR text", text: $search.query)
          .textFieldStyle(.plain)
          .font(.title3)
          .focused($focused)
          .onSubmit { Task { await search.submit() } }
      }
      .padding(8)
      .overlay(RoundedRectangle(cornerRadius: Flat.bubbleRadius).stroke(Flat.userBubble, lineWidth: 1.5))
      HStack {
        if search.currentDocumentId != nil {
          IconSegmentedControl(selection: $search.scope, segments: [
            IconSegment(value: SearchScope.currentDocument, symbol: "doc", help: "Search this PDF"),
            IconSegment(value: SearchScope.allDocuments, symbol: "books.vertical", help: "Search all PDFs in the library")
          ])
          Text(search.scope == .currentDocument ? (search.currentDocumentTitle ?? "This PDF") : "All PDFs")
            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer()
        Button("Cancel", role: .cancel) { search.isPromptPresented = false }
          .keyboardShortcut(.cancelAction)
        Button("Search") { Task { await search.submit() } }
          .keyboardShortcut(.defaultAction)
          .disabled(search.query.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
    .padding(16)
    .frame(minWidth: 280, idealWidth: 480, maxWidth: 520)
    .onAppear { focused = true }
  }
}

/// Search results in the center pane: the query on top, then one row per
/// page with its thumbnail and the text around the hit, the hit highlighted.
/// Esc or the back icon returns to the previous screen.
struct SearchResultsView: View {
  @Bindable var search: SearchViewModel
  let onOpen: (SearchResultItem) -> Void

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      content
    }
    .background(Flat.panel)
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Button { search.close() } label: {
        Image(systemName: "chevron.backward").font(.title3)
      }
      .buttonStyle(.plain)
      .help("Back (Esc)")
      .accessibilityLabel("Back")
      VStack(alignment: .leading, spacing: 2) {
        Text("\u{201C}\(search.resultsQuery)\u{201D}").font(.title2.bold()).lineLimit(1)
        Text(summary).font(.callout).foregroundStyle(.secondary)
      }
      Spacer()
      Button { search.present() } label: { Image(systemName: "magnifyingglass") }
        .buttonStyle(.plain)
        .help("New search (/ or Cmd-F)")
        .accessibilityLabel("New search")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }

  private var summary: String {
    let place = search.resultsScope == .currentDocument ? "in \(search.currentDocumentTitle ?? "this PDF")" : "in all PDFs"
    let count = search.results.count
    let more = count == SearchViewModel.resultLimit ? "+" : ""
    return "\(count)\(more) \(count == 1 ? "page" : "pages") \(place)"
  }

  @ViewBuilder private var content: some View {
    if let error = search.error {
      ContentUnavailableView("Search Failed", systemImage: "exclamationmark.triangle", description: Text(error))
    } else if search.results.isEmpty {
      ContentUnavailableView.search(text: search.resultsQuery)
    } else {
      List(search.results.indices, id: \.self) { index in
        let hit = search.results[index]
        SearchResultRow(hit: hit, showTitle: search.resultsScope == .allDocuments,
                        thumbnail: search.thumbnails[SearchViewModel.thumbnailKey(docId: hit.docId, page: hit.page)])
          .contentShape(Rectangle())
          .onTapGesture { onOpen(hit) }
          .task { await search.loadThumbnail(docId: hit.docId, page: hit.page) }
      }
      .listStyle(.inset)
    }
  }
}

private struct SearchResultRow: View {
  let hit: SearchResultItem
  let showTitle: Bool
  let thumbnail: CGImage?

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Group {
        if let thumbnail {
          Image(decorative: thumbnail, scale: 1).resizable().aspectRatio(contentMode: .fit)
        } else {
          Rectangle().fill(Flat.assistantBubble)
        }
      }
      .frame(width: 60, height: 78)
      .background(Color.white)
      .overlay(Rectangle().stroke(Flat.border, lineWidth: 1))
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          if showTitle { Text(hit.title).font(.headline).lineLimit(1) }
          Text("p. \(hit.page)").font(showTitle ? .callout : .headline).foregroundStyle(showTitle ? .secondary : .primary)
        }
        Text(Self.highlighted(hit))
          .font(.callout)
          .lineLimit(4)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 4)
    .help("Open page \(hit.page)")
  }

  /// Context text with every hit in the find-highlight colour.
  static func highlighted(_ hit: SearchResultItem) -> AttributedString {
    let segments = hit.context.isEmpty ? SearchContextBuilder.segments(fromBracketedSnippet: hit.snippet) : hit.context
    var result = AttributedString()
    for segment in segments {
      var run = AttributedString(segment.text)
      if segment.isHit {
        run.backgroundColor = Color(nsColor: .findHighlightColor)
        run.foregroundColor = .black
        run.font = .callout.bold()
      } else {
        run.foregroundColor = .secondary
      }
      result += run
    }
    return result
  }
}
