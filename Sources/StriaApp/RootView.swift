import SwiftUI
import StriaCore
import UniformTypeIdentifiers

struct RootView: View {
  @Bindable var model: AppModel
  @State private var isImporting = false

  var body: some View {
    Group {
      switch model.route {
      case .library:
        LibraryView(model: model)
      case .reader:
        if let reader = model.reader, let agent = model.agent {
          ReaderView(model: model, reader: reader, agent: agent)
        } else {
          ProgressView("Opening document…")
        }
      }
    }
    .fileImporter(isPresented: $isImporting, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
      switch result {
      case .success(let urls):
        beginImport(urls)
      case .failure(let error):
        model.library.alert = error.localizedDescription
      }
    }
    .focusedSceneValue(\.striaImport, { isImporting = true })
    .focusedSceneValue(\.striaLibrary, { Task { await model.showLibrary() } })
    .task {
      await model.library.refresh()
      // Development aid for STRIA_SNAPSHOT_DIR runs: open the most recent PDF.
      if ProcessInfo.processInfo.environment["STRIA_SNAPSHOT_OPEN"] != nil, let first = model.library.rows.first {
        await model.open(documentId: first.id)
      }
    }
  }

  private func beginImport(_ urls: [URL]) {
    let scopedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
    let unscopedURLs = urls.filter { !scopedURLs.contains($0) }
    model.library.importFiles(scopedURLs + unscopedURLs)
    Task {
      await model.library.waitForImports()
      scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
    }
  }
}
