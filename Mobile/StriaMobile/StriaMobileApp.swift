import SwiftUI
import StriaCore

@main
struct StriaMobileApp: App {
  @State private var model: MobileModel?
  @State private var startupError: String?
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage(Appearance.storageKey) private var appearance = Appearance.default

  init() {
    do {
      let paths = StriaPaths(root: StriaPaths.defaultRoot(platform: .iOS))
      let config = try ConfigStore.loadOrCreate(paths: paths)
      let environment = StriaEnvironment.live(paths: paths, config: config, environment: [:], platform: .iOS)
      let store = try StriaLibrary.open(environment: environment)
      _model = State(initialValue: MobileModel(store: store))
    } catch {
      _startupError = State(initialValue: error.localizedDescription)
    }
  }

  var body: some Scene {
    WindowGroup {
      Group {
        if let model {
          MobileRootView(model: model)
            .task { await model.start() }
            .onChange(of: scenePhase) { _, phase in model.sync.setActive(phase == .active) }
            .onOpenURL { url in Task { await model.importFiles([url]) } }
        } else {
          ContentUnavailableView("Unable to Start Stria", systemImage: "exclamationmark.triangle",
                                 description: Text(startupError ?? "Could not open the library."))
        }
      }
      .preferredColorScheme(appearance.colorScheme)
      .tint(.accentColor)
    }
  }
}

extension Appearance {
  var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}

/// Opaque system fills and square borders match the Mac app's flat style.
enum Flat {
  static let panel = Color(uiColor: .systemBackground)
  static let assistantBubble = Color(uiColor: .secondarySystemBackground)
  static let border = Color(uiColor: .separator)
}
