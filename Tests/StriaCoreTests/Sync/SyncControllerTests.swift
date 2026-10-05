import Foundation
import StriaCore
import Testing

@MainActor
private final class SyncTiming {
  var waits: [(Duration, CheckedContinuation<Void, Never>)] = []
  func sleep(_ duration: Duration) async { await withCheckedContinuation { waits.append((duration, $0)) } }
  func releaseAll() {
    let pending = waits; waits = []
    for (_, continuation) in pending { continuation.resume() }
  }
}

@MainActor
@Suite struct SyncControllerTests {
  @Test func debounceCollapsesChangesAndDisabledSyncDoesNothing() async {
    let timing = SyncTiming()
    var count = 0
    var enabled = true
    let folder = URL(fileURLWithPath: "/tmp/test-sync")
    let controller = SyncController(options: { .init(enabled: enabled) }, folder: { .init(url: folder) },
                                    run: { _, _ in count += 1; return SyncReport(folder: folder.path) },
                                    clock: { Date(timeIntervalSince1970: 1000) }, debounce: .seconds(4),
                                    sleep: { await timing.sleep($0) })
    controller.scheduleSoon()
    await Task.yield()
    controller.scheduleSoon()
    await Task.yield()
    controller.scheduleSoon()
    await Task.yield()
    #expect(count == 0)
    #expect(timing.waits.allSatisfy { $0.0 == .seconds(4) })
    timing.releaseAll()
    for _ in 0..<20 { await Task.yield() }
    #expect(count == 1 && controller.lastSyncAt == Date(timeIntervalSince1970: 1000))
    #expect(controller.lastError == nil && !controller.isSyncing)
    enabled = false
    controller.configurationChanged(); controller.scheduleSoon()
    await controller.syncNow()
    #expect(count == 1 && timing.waits.isEmpty)
  }

  @Test func requestsDuringPassCoalesceIntoOneFollowUp() async {
    var count = 0
    var release: CheckedContinuation<Void, Never>?
    let started = AsyncStream<Void>.makeStream()
    let folder = URL(fileURLWithPath: "/tmp/test-sync")
    let controller = SyncController(options: { .init(enabled: true) }, folder: { .init(url: folder) }, run: { _, _ in
      count += 1
      if count == 1 {
        await withCheckedContinuation { continuation in
          release = continuation
          started.continuation.yield(())
          started.continuation.finish()
        }
      }
      return SyncReport(folder: folder.path)
    })
    let task = Task { await controller.syncNow() }
    for await _ in started.stream { break }
    #expect(controller.isSyncing && count == 1)
    await controller.syncNow(); await controller.syncNow()
    controller.scheduleSoon(); controller.scheduleSoon()
    release?.resume()
    await task.value
    #expect(count == 2 && !controller.isSyncing)
  }

  @Test func activityTimerUsesConfiguredIntervalAndStopsInBackground() async {
    let timing = SyncTiming()
    var count = 0
    let folder = URL(fileURLWithPath: "/tmp/test-sync")
    let controller = SyncController(options: { .init(enabled: true, intervalMinutes: 7) }, folder: { .init(url: folder) },
                                    run: { _, _ in count += 1; return SyncReport(folder: folder.path) },
                                    sleep: { await timing.sleep($0) })
    controller.setActive(true)
    for _ in 0..<20 { await Task.yield() }
    #expect(count == 1 && timing.waits.first?.0 == .seconds(420))
    timing.releaseAll()
    for _ in 0..<20 { await Task.yield() }
    #expect(count == 2)
    controller.setActive(false)
    timing.releaseAll()
    for _ in 0..<20 { await Task.yield() }
    #expect(count == 2 && timing.waits.isEmpty)
  }

  @Test func unavailableFolderSetsClearError() async {
    let controller = SyncController(options: { .init(enabled: true) },
                                    folder: { throw StriaError.serviceUnavailable("iCloud Drive is not available") },
                                    run: { _, _ in Issue.record("Unexpected pass"); return SyncReport(folder: "") })
    await controller.syncNow()
    #expect(controller.lastError == "iCloud Drive is not available")
    #expect(controller.folderDescription == "iCloud Drive is not available")
    #expect(controller.lastSyncAt == nil && !controller.isSyncing)
  }
}
