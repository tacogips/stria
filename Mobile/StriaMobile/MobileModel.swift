import Foundation
import Observation
import StriaCore
import UIKit

/// Owns mobile navigation and connects local changes to automatic sync.
@MainActor
@Observable
final class MobileModel {
  let library: LibraryViewModel
  let settings: SettingsViewModel
  let search: SearchViewModel
  let sync: SyncController
  private let store: StriaLibrary
  private(set) var reader: ReaderViewModel?
  private(set) var agent: AgentPaneViewModel?
  var showingReader = false
  var showingSettings = false
  var showingAgent = false
  var showingVendors = false
  private var openGeneration = 0
  private(set) var syncRevision = 0

  init(store: StriaLibrary) {
    self.store = store
    library = LibraryViewModel(library: store)
    settings = SettingsViewModel(library: store, processEnvironment: [:])
    search = SearchViewModel(library: store)
    let folder = SyncFolder(environment: [:], platform: .iOS, provider: MobileSyncFolder.resolve)
    sync = SyncController(
      options: { store.environment.config.sync },
      folder: { try folder.resolve(options: store.environment.config.sync) },
      run: { try await SyncEngine(library: store).sync(location: $0, options: $1) }
    )
    library.onLocalChange = { [weak sync] in sync?.scheduleSoon() }
    sync.onCompleted = { [weak self] in
      await self?.library.refresh()
      self?.syncRevision += 1
      await self?.agent?.reloadHistory()
    }
    settings.onSaved = { [weak self] in
      self?.sync.configurationChanged()
      Task { await self?.library.refresh() }
    }
  }

  func open(documentId: String, page: Int? = nil) async {
    openGeneration += 1
    let generation = openGeneration
    agent?.cancel()
    await reader?.close()
    reader = nil
    agent = nil
    do {
      let next = ReaderViewModel(library: store, documentId: documentId)
      try await next.open()
      guard generation == openGeneration else { await next.close(); return }
      try await store.markOpened(documentId: documentId)
      guard generation == openGeneration else { await next.close(); return }
      if let page { next.goToPage(page) }
      reader = next
      let pane = AgentPaneViewModel(library: store, reader: next, processEnvironment: [:])
      pane.onLocalChange = { [weak sync] in sync?.scheduleSoon() }
      await pane.loadSelection()
      guard generation == openGeneration else { return }
      agent = pane
      showingReader = true
      search.close()
    } catch {
      library.alert = error.localizedDescription
    }
  }

  func closeReader() async {
    openGeneration += 1
    agent?.cancel()
    await reader?.close()
    reader = nil
    agent = nil
    showingReader = false
    await library.refresh()
  }

  /// Copies selected files while the Files provider's security scope is open.
  func importFiles(_ urls: [URL]) async {
    for url in urls {
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      do {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let copy = directory.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: copy)
        library.importFiles([copy])
        await library.waitForImports()
      } catch {
        library.alert = error.localizedDescription
      }
    }
  }

  func start() async {
    await library.refresh()
    sync.setActive(true)
    #if DEBUG
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains("-StriaSampleImport") {
      do {
        if library.rows.isEmpty {
          let url = try SamplePDF.make()
          library.importFiles([url])
          await library.waitForImports()
          try? FileManager.default.removeItem(at: url)
        }
        if arguments.contains("-StriaReader") || arguments.contains("-StriaAgent"), let row = library.rows.first {
          await open(documentId: row.id)
        }
        showingAgent = arguments.contains("-StriaAgent")
        showingSettings = arguments.contains("-StriaSettings") || arguments.contains("-StriaOCRVendors")
        showingVendors = arguments.contains("-StriaOCRVendors")
      } catch { library.alert = error.localizedDescription }
    }
    #endif
  }
}

/// Device-local bookmarks are resolved anew for every coordinated sync pass.
enum MobileSyncFolder {
  static let bookmarkKey = "syncFolderBookmark"

  static func resolve() throws -> SyncFolder.Location? {
    guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
    var stale = false
    let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    if stale {
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      try save(url)
    }
    return SyncFolder.Location(url: url, securityScoped: true)
  }

  static func save(_ url: URL) throws {
    let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    UserDefaults.standard.set(data, forKey: bookmarkKey)
  }
}

#if DEBUG
/// A small local PDF for simulator smoke checks, without Files or a network.
@MainActor
private enum SamplePDF {
  static func make() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("Welcome to Stria.pdf")
    let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
    try renderer.writePDF(to: url) { context in
      for page in 1...3 {
        context.beginPage()
        let title = "Welcome to Stria\nPage \(page)"
        (title as NSString).draw(in: CGRect(x: 48, y: 64, width: 516, height: 120),
                                 withAttributes: [.font: UIFont.boldSystemFont(ofSize: 30)])
        let text = "Your library, wherever you read.\n\n"
          + "Import PDFs, navigate their pages, search OCR text, and ask questions with page citations.\n\n"
          + "Choose an API vendor in Settings and save its key in the Keychain. To sync devices, select the same Stria folder in iCloud Drive."
        (text as NSString).draw(in: CGRect(x: 48, y: 220, width: 516, height: 450),
                                withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
      }
    }
    return url
  }
}
#endif
