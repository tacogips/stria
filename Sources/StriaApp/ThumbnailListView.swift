import AppKit
import PDFKit
import SwiftUI
import StriaCore

struct ThumbnailListView: View {
  @Bindable var reader: ReaderViewModel
  @State private var thumbnails: [Int: NSImage] = [:]

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 10) {
          ForEach(1...max(reader.pageCount, 1), id: \.self) { pageNumber in
            Button {
              reader.goToPage(pageNumber)
            } label: {
              VStack(spacing: 4) {
                Group {
                  if let image = thumbnails[pageNumber] {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                  } else {
                    Rectangle().fill(.quaternary).overlay { ProgressView() }
                  }
                }
                .frame(width: 120, height: 160)
                Text("Page \(pageNumber)").font(.caption)
              }
              .padding(6)
              .background(reader.currentPage == pageNumber ? Flat.selected : .clear)
              .foregroundStyle(reader.currentPage == pageNumber ? Color.white : Color.primary)
            }
            .buttonStyle(.plain)
            .id(pageNumber)
            .task { await loadThumbnail(pageNumber) }
          }
        }
        .padding(8)
      }
      .onChange(of: reader.currentPage) { _, page in
        withAnimation { proxy.scrollTo(page, anchor: .center) }
      }
    }
  }

  /// Renders off the main actor: PDFKit page drawing is thread-safe, and a
  /// scanned page can take long enough to stutter the sidebar otherwise.
  private func loadThumbnail(_ pageNumber: Int) async {
    guard thumbnails[pageNumber] == nil,
          let page = reader.pdfDocument?.page(at: pageNumber - 1) else { return }
    nonisolated(unsafe) let unsafePage = page
    let rendered = await Task.detached(priority: .utility) {
      nonisolated(unsafe) let image = unsafePage.thumbnail(of: CGSize(width: 120, height: 160), for: .cropBox)
      return image
    }.value
    guard !Task.isCancelled else { return }
    thumbnails[pageNumber] = rendered
  }
}
