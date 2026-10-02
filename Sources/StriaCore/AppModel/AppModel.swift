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

  private let striaLibrary: StriaLibrary
  private let debounce: Duration

  public init(library: StriaLibrary, debounce: Duration = .seconds(1)) {
    striaLibrary = library
    self.debounce = debounce
    self.library = LibraryViewModel(library: library)
  }

  public func open(documentId: String) async {
    // Route first: the reader screen shows its opening indicator while the
    // PDF loads; on failure the library comes back with the error.
    route = .reader(docId: documentId)
    do {
      let reader = ReaderViewModel(library: striaLibrary, documentId: documentId, debounce: debounce)
      try await reader.open()
      try await striaLibrary.markOpened(documentId: documentId)
      self.reader = reader
      agent = AgentPaneViewModel(library: striaLibrary, reader: reader)
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
