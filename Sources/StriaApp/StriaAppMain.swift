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
  }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
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
