import SwiftUI
import StriaCore

struct LeftPaneView: View {
  @Bindable var reader: ReaderViewModel
  @State private var expandedIDs: Set<String> = []

  var body: some View {
    VStack(spacing: 0) {
      Picker("Sidebar", selection: $reader.sidebarMode) {
        Text("Contents").tag(SidebarMode.contents)
        Text("Thumbnails").tag(SidebarMode.thumbnails)
        if reader.sidebarMode == .search {
          Text("Search").tag(SidebarMode.search)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .padding(.horizontal, 12)
      .padding(.vertical, 8)

      Group {
        switch reader.sidebarMode {
        case .contents:
          contents
        case .thumbnails:
          ThumbnailListView(reader: reader)
        case .search:
          searchResults
        }
      }
    }
    .navigationTitle("Contents")
  }

  @ViewBuilder private var contents: some View {
    if reader.outlineRows.isEmpty {
      ScrollViewReader { proxy in
        List(1...max(reader.pageCount, 1), id: \.self, selection: pageSelection) { page in
          Text("Page \(page)").id(page)
        }
        .listStyle(.sidebar)
        .onChange(of: reader.currentPage) { _, page in proxy.scrollTo(page) }
      }
    } else {
      ScrollViewReader { proxy in
        List(selection: outlineSelection) {
          ForEach(reader.outlineRows) { row in
            OutlineRowView(row: row, expandedIDs: $expandedIDs)
          }
        }
        .listStyle(.sidebar)
        .onAppear { revealCurrentSection(proxy) }
        .onChange(of: reader.currentOutlineNodeID) { _, _ in revealCurrentSection(proxy) }
      }
    }
  }

  /// Selecting a row navigates; the selection itself always mirrors the
  /// current section, as Preview's sidebar does.
  private var outlineSelection: Binding<String?> {
    Binding(
      get: { reader.currentOutlineNodeID },
      set: { id in
        guard let id, let page = Self.page(for: id, in: reader.outlineRows) else { return }
        reader.goToPage(page)
      }
    )
  }

  private var pageSelection: Binding<Int?> {
    Binding(get: { reader.currentPage }, set: { if let page = $0 { reader.goToPage(page) } })
  }

  private func revealCurrentSection(_ proxy: ScrollViewProxy) {
    guard let id = reader.currentOutlineNodeID else { return }
    expandedIDs.formUnion(OutlineRow.ancestorIDs(of: id))
    DispatchQueue.main.async { withAnimation { proxy.scrollTo(id, anchor: .center) } }
  }

  private static func page(for id: String, in rows: [OutlineRow]) -> Int? {
    for row in rows {
      if row.id == id { return row.page }
      if let page = page(for: id, in: row.children) { return page }
    }
    return nil
  }

  private var searchResults: some View {
    VStack(spacing: 0) {
      if let error = reader.searchError {
        ContentUnavailableView("Search Failed", systemImage: "exclamationmark.triangle", description: Text(error))
      } else if reader.searchResults.isEmpty {
        ContentUnavailableView.search(text: reader.searchQuery)
      } else {
        List(reader.searchResults.indices, id: \.self) { index in
          let result = reader.searchResults[index]
          Button {
            reader.goToPage(result.page)
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text("p. \(result.page)").font(.headline)
              Text(result.snippet).lineLimit(3).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
      if reader.pagesWithoutOCR > 0 {
        Text("\(reader.pagesWithoutOCR) pages not yet OCRed")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(8)
      }
    }
  }
}

/// A recursive outline row whose expansion state is shared, so the current
/// section's ancestors can be opened programmatically.
private struct OutlineRowView: View {
  let row: OutlineRow
  @Binding var expandedIDs: Set<String>

  var body: some View {
    if row.children.isEmpty {
      label.tag(row.id).id(row.id)
    } else {
      DisclosureGroup(isExpanded: Binding(
        get: { expandedIDs.contains(row.id) },
        set: { if $0 { expandedIDs.insert(row.id) } else { expandedIDs.remove(row.id) } }
      )) {
        ForEach(row.children) { child in
          OutlineRowView(row: child, expandedIDs: $expandedIDs)
        }
      } label: {
        label
      }
      .tag(row.id)
      .id(row.id)
    }
  }

  private var label: some View {
    Text(row.title)
      .foregroundStyle(row.page == nil ? Color.secondary : Color.primary)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
