import Foundation
import Observation

public enum Route: Equatable, Sendable {
  case library
  case reader(docId: String)
}

@MainActor
@Observable
public final class AppModel {
  public private(set) var route: Route = .library
  public let library: LibraryViewModel
  public private(set) var reader: ReaderViewModel?
  public private(set) var agent: AgentPaneViewModel?
  /// Bumped after Settings saves, so views that read config re-render.
  public private(set) var configRevision = 0
  public let settings: SettingsViewModel

  private let striaLibrary: StriaLibrary
  private let debounce: Duration

  public init(library: StriaLibrary, debounce: Duration = .seconds(1)) {
    striaLibrary = library
    self.debounce = debounce
    self.library = LibraryViewModel(library: library)
    settings = SettingsViewModel(library: library)
    settings.onSaved = { [weak self] in
      guard let self else { return }
      configRevision += 1
      Task { await self.library.refresh() }
    }
  }

  /// Opens a document, optionally at a page (a library search hit).
  public func open(documentId: String, page: Int? = nil) async {
    // Route first: the reader screen shows its opening indicator while the
    // PDF loads; on failure the library comes back with the error.
    route = .reader(docId: documentId)
    do {
      let reader = ReaderViewModel(library: striaLibrary, documentId: documentId, debounce: debounce)
      try await reader.open()
      try await striaLibrary.markOpened(documentId: documentId)
      if let page { reader.goToPage(page) }
      self.reader = reader
      let agent = AgentPaneViewModel(library: striaLibrary, reader: reader)
      await agent.loadSelection()
      self.agent = agent
    } catch {
      route = .library
      library.alert = (error as? StriaError)?.message ?? error.localizedDescription
    }
  }

  public func showLibrary() async {
    await reader?.close()
    reader = nil
    agent = nil
    route = .library
    await library.refresh()
  }
}
