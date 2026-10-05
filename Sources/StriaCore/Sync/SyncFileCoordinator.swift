import Foundation

/// Injectable coordination boundary. A pass never bypasses the production
/// coordinator; deterministic tests can supply a local filesystem adapter.
public protocol SyncFileCoordinating: Sendable {
  func coordinate(_ url: URL, writing: Bool, accessor: (URL) throws -> Void) throws
}

public struct SystemSyncFileCoordinator: SyncFileCoordinating {
  public init() {}

  public func coordinate(_ url: URL, writing: Bool, accessor: (URL) throws -> Void) throws {
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var accessorError: Error?
    let access: (URL) -> Void = { coordinated in
      do { try accessor(coordinated) } catch { accessorError = error }
    }
    if writing {
      coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError, byAccessor: access)
    } else {
      coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError, byAccessor: access)
    }
    if let coordinationError { throw coordinationError }
    if let accessorError { throw accessorError }
  }
}
