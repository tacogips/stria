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
              .background(reader.currentPage == pageNumber ? Color.accentColor.opacity(0.18) : .clear)
              .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .id(pageNumber)
            .task { loadThumbnail(pageNumber) }
          }
        }
        .padding(8)
      }
      .onChange(of: reader.currentPage) { _, page in
        withAnimation { proxy.scrollTo(page, anchor: .center) }
      }
    }
  }

  private func loadThumbnail(_ pageNumber: Int) {
    guard thumbnails[pageNumber] == nil,
          let page = reader.pdfDocument?.page(at: pageNumber - 1) else { return }
    thumbnails[pageNumber] = page.thumbnail(of: CGSize(width: 120, height: 160), for: .cropBox)
  }
}
