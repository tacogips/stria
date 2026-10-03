import AppKit
import SwiftUI
import StriaCore

@main
struct StriaReaderApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var appModel: AppModel?
  @State private var startupError: String?
  @AppStorage(Appearance.storageKey) private var appearance = Appearance.default

  init() {
    // Before any service reads the environment (Finder launches get none of
    // the shell's PATH or key variables).
    LoginEnvironment.importIfNeeded()
    do {
      let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
      let paths = StriaPaths.resolve(
        homeFlag: nil,
        environment: ProcessInfo.processInfo.environment,
        homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
        currentDirectory: currentDirectory
      )
      let config = try ConfigStore.loadOrCreate(paths: paths)
      let environment = StriaEnvironment.live(paths: paths, config: config)
      let library = try StriaLibrary.open(environment: environment)
      _appModel = State(initialValue: AppModel(library: library))
      _startupError = State(initialValue: nil)
    } catch {
      _appModel = State(initialValue: nil)
      _startupError = State(initialValue: error.localizedDescription)
    }
  }

  var body: some Scene {
    WindowGroup {
      Group {
        if let appModel {
          RootView(model: appModel)
        } else {
          StartupErrorView(message: startupError ?? "Stria could not start.")
        }
      }
      .frame(minWidth: 1100, minHeight: 700)
      .preferredColorScheme(appearance.colorScheme)
    }
    .commands {
      StriaCommands()
    }
    Settings {
      Group {
        if let appModel {
          SettingsView(settings: appModel.settings)
        } else {
          StartupErrorView(message: startupError ?? "Stria could not start.")
        }
      }
      .preferredColorScheme(appearance.colorScheme)
    }
    .windowResizability(.contentMinSize)
  }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    WindowSnapshotter.startIfRequested()
  }
}

/// Development aid: with STRIA_SNAPSHOT_DIR set, every 2 seconds each window
/// (title bar and toolbar included) is rendered to <dir>/window-<n>.png from
/// the app's own view hierarchy, which needs no screen-recording permission.
@MainActor
enum WindowSnapshotter {
  static func startIfRequested() {
    guard let directory = ProcessInfo.processInfo.environment["STRIA_SNAPSHOT_DIR"], !directory.isEmpty else { return }
    let url = URL(fileURLWithPath: directory, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
      MainActor.assumeIsolated { capture(into: url) }
    }
  }

  private static func capture(into directory: URL) {
    for (index, window) in NSApp.windows.enumerated() where window.isVisible {
      guard let view = window.contentView?.superview ?? window.contentView else { continue }
      // AppKit drawing (title bar, toolbar)...
      if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("window-\(index)-appkit.png"))
      }
      // ...and the layer tree, which is where SwiftUI content renders.
      guard let layer = view.layer else { continue }
      let scale = window.backingScaleFactor
      let width = Int(view.bounds.width * scale), height = Int(view.bounds.height * scale)
      guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
      context.scaleBy(x: scale, y: scale)
      layer.render(in: context)
      guard let image = context.makeImage() else { continue }
      let rep = NSBitmapImageRep(cgImage: image)
      try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("window-\(index).png"))
    }
  }
}

private struct StartupErrorView: View {
  let message: String

  var body: some View {
    ContentUnavailableView {
      Label("Unable to Start Stria", systemImage: "exclamationmark.triangle")
    } description: {
      Text(message)
    }
  }
}

extension Appearance {
  /// nil follows the system.
  var colorScheme: ColorScheme? {
    switch self {
    case .light: .light
    case .dark: .dark
    case .system: nil
    }
  }
}
