import SwiftUI
import StriaCore

struct LeftPaneView: View {
  @Bindable var reader: ReaderViewModel

  private var contentsSelection: Binding<SidebarMode> {
    Binding(
      get: { reader.sidebarMode == .thumbnails ? .thumbnails : .contents },
      set: { reader.sidebarMode = $0 }
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      Picker("Sidebar", selection: contentsSelection) {
        Text("Contents").tag(SidebarMode.contents)
        Text("Thumbnails").tag(SidebarMode.thumbnails)
      }
      .pickerStyle(.segmented)
      .padding(10)

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
    .navigationTitle(reader.title)
  }

  @ViewBuilder private var contents: some View {
    if reader.outline.isEmpty {
      List(1...max(reader.pageCount, 1), id: \.self) { page in
        Button("Page \(page)") { reader.goToPage(page) }
          .buttonStyle(.plain)
          .foregroundStyle(reader.currentPage == page ? Color.accentColor : Color.primary)
      }
    } else {
      let rows = OutlineRowNode.make(reader.outline)
      List {
        OutlineGroup(rows, children: \.optionalChildren) { node in
          outlineLabel(node)
        }
      }
    }
  }

  private var searchResults: some View {
    VStack(spacing: 0) {
      if reader.searchResults.isEmpty {
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

  @ViewBuilder private func outlineLabel(_ node: OutlineRowNode) -> some View {
    if let page = node.page {
      Button {
        reader.goToPage(page)
      } label: {
        Text(node.title)
          .frame(maxWidth: .infinity, alignment: .leading)
          .foregroundStyle(reader.currentOutlineNodeID == node.id ? Color.accentColor : Color.primary)
      }
      .buttonStyle(.plain)
    } else {
      Text(node.title)
    }
  }
}

private struct OutlineRowNode: Identifiable {
  let id: String
  let title: String
  let page: Int?
  let children: [OutlineRowNode]
  var optionalChildren: [OutlineRowNode]? { children.isEmpty ? nil : children }

  static func make(_ nodes: [OutlineNode], prefix: String = "") -> [OutlineRowNode] {
    nodes.enumerated().map { index, node in
      let id = prefix.isEmpty ? String(index) : "\(prefix).\(index)"
      return OutlineRowNode(id: id, title: node.title, page: node.page, children: make(node.children, prefix: id))
    }
  }
}
