import SwiftUI
import StriaCore

struct LeftPaneView: View {
  @Bindable var reader: ReaderViewModel
  @State private var expandedIDs: Set<String> = []

  var body: some View {
    VStack(spacing: 0) {
      IconSegmentedControl(selection: $reader.sidebarMode, segments: sidebarSegments)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)

      Group {
        switch reader.sidebarMode {
        case .contents:
          contents
        case .thumbnails:
          ThumbnailListView(reader: reader)
        }
      }
    }
  }

  private let sidebarSegments = [
    IconSegment(value: SidebarMode.contents, symbol: "list.bullet.indent", help: "Contents: the PDF's table of contents"),
    IconSegment(value: SidebarMode.thumbnails, symbol: "square.grid.2x2", help: "Thumbnails: small images of every page")
  ]

  @ViewBuilder private var contents: some View {
    if reader.outlineRows.isEmpty {
      ScrollViewReader { proxy in
        List(1...max(reader.pageCount, 1), id: \.self, selection: pageSelection) { page in
          Text("Page \(page)").id(page)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .onChange(of: reader.currentPage) { _, page in proxy.scrollTo(page) }
      }
    } else {
      ScrollViewReader { proxy in
        List(selection: outlineSelection) {
          ForEach(reader.outlineRows) { row in
            OutlineRowView(row: row, expandedIDs: $expandedIDs)
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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
