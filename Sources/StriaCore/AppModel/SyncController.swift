import Foundation
import Observation

@MainActor
@Observable
public final class SyncController {
  public private(set) var isSyncing = false
  public private(set) var lastSyncAt: Date?
  public private(set) var lastReport: SyncReport?
  public private(set) var lastError: String?
  public private(set) var folderDescription = "iCloud Drive is not available"
  public var onCompleted: (() async -> Void)?
  public var isEnabled: Bool { options().enabled }

  private let options: () -> SyncConfig
  private let resolveFolder: () throws -> SyncFolder.Location
  private let run: (SyncFolder.Location, SyncConfig) async throws -> SyncReport
  private let clock: () -> Date
  private let sleep: (Duration) async throws -> Void
  private let debounce: Duration
  @ObservationIgnored nonisolated(unsafe) private var debounceTask: Task<Void, Never>?
  @ObservationIgnored nonisolated(unsafe) private var periodicTask: Task<Void, Never>?
  private var followUp = false
  private var active = false

  public convenience init(library: StriaLibrary, debounce: Duration = .seconds(3)) {
    self.init(options: { library.environment.config.sync },
              folder: { try library.environment.syncFolder.resolve(options: library.environment.config.sync) },
              run: { try await SyncEngine(library: library).sync(location: $0, options: $1) },
              clock: library.environment.clock, debounce: debounce)
  }

  /// Inject timing and the pass for deterministic scheduling tests.
  public init(options: @escaping () -> SyncConfig, folder: @escaping () throws -> SyncFolder.Location,
              run: @escaping (SyncFolder.Location, SyncConfig) async throws -> SyncReport,
              clock: @escaping () -> Date = { Date() }, debounce: Duration = .seconds(3),
              sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
    self.options = options; resolveFolder = folder; self.run = run; self.clock = clock
    self.debounce = debounce; self.sleep = sleep
    refreshFolderDescription()
  }

  public func refreshFolderDescription() {
    do { folderDescription = try resolveFolder().url.path } catch { folderDescription = (error as? StriaError)?.message ?? error.localizedDescription }
  }

  public func syncNow() async {
    guard isEnabled else { return }
    debounceTask?.cancel(); debounceTask = nil
    if isSyncing { followUp = true; return }
    isSyncing = true
    defer { isSyncing = false }
    repeat {
      followUp = false
      do {
        let location = try resolveFolder()
        folderDescription = location.url.path
        let report = try await run(location, options())
        lastReport = report; lastSyncAt = clock(); lastError = report.errors.first
        await onCompleted?()
      } catch {
        lastError = (error as? StriaError)?.message ?? error.localizedDescription
        refreshFolderDescription()
      }
    } while followUp && isEnabled && !Task.isCancelled
  }

  public func scheduleSoon() {
    guard isEnabled else { return }
    if isSyncing { followUp = true; return }
    debounceTask?.cancel()
    debounceTask = Task { [weak self, sleep, debounce] in
      do { try await sleep(debounce) } catch { return }
      guard !Task.isCancelled else { return }
      await self?.syncNow()
    }
  }

  /// Called at launch and on scene activity changes. Background scenes stop
  /// their timer; explicit sync remains available.
  public func setActive(_ value: Bool) {
    active = value
    restartTimer()
    if value, isEnabled { Task { [weak self] in await self?.syncNow() } }
  }

  public func configurationChanged() {
    refreshFolderDescription()
    restartTimer()
    if isEnabled { scheduleSoon() } else { debounceTask?.cancel(); followUp = false }
  }

  private func restartTimer() {
    periodicTask?.cancel(); periodicTask = nil
    guard active, isEnabled else { return }
    let interval = Duration.seconds(options().intervalMinutes * 60)
    periodicTask = Task { [weak self, sleep] in
      while !Task.isCancelled {
        do { try await sleep(interval) } catch { return }
        guard !Task.isCancelled else { return }
        await self?.syncNow()
        if self == nil { return }
      }
    }
  }

  deinit { debounceTask?.cancel(); periodicTask?.cancel() }
}
