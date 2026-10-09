import SwiftUI
import StriaCore

struct ThumbnailListView: View {
  @Bindable var reader: ReaderViewModel

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 10) {
          ForEach(1...max(reader.pageCount, 1), id: \.self) { pageNumber in
            ReaderThumbnailRow(reader: reader, pageNumber: pageNumber)
              .id(pageNumber)
          }
        }
        .padding(8)
      }
      .onChange(of: reader.currentPage) { _, page in
        withAnimation { proxy.scrollTo(page, anchor: .center) }
      }
    }
  }
}

/// Each visible row owns its small bitmap. Offscreen rows release it, even
/// when SwiftUI retains the row's state for reuse in the lazy stack.
private struct ReaderThumbnailRow: View {
  let reader: ReaderViewModel
  let pageNumber: Int
  @State private var thumbnail: CGImage?
  @State private var isLoading = false

  var body: some View {
    Button {
      reader.goToPage(pageNumber)
    } label: {
      VStack(spacing: 4) {
        Group {
          if let thumbnail {
            Image(decorative: thumbnail, scale: 2).resizable().aspectRatio(contentMode: .fit)
          } else {
            Rectangle().fill(.quaternary).overlay {
              if isLoading { ProgressView() } else { Image(systemName: "doc") }
            }
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
    .task {
      isLoading = true
      defer { isLoading = false }
      let image = try? await reader.thumbnail(page: pageNumber)
      guard !Task.isCancelled else { return }
      thumbnail = image
    }
    .onDisappear { thumbnail = nil }
  }
}
