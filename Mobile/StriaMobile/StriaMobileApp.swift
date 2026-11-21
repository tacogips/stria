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
  /// Deep ink blue: user bubbles, the send button and the tab capsule.
  static let ink = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.20, green: 0.33, blue: 0.52, alpha: 1)
      : UIColor(red: 0.08, green: 0.19, blue: 0.31, alpha: 1)
  })
  /// Coral highlight: the selected tab and the needs-setup badge.
  static let coral = Color(red: 0.95, green: 0.44, blue: 0.36)
  static let cardRadius: CGFloat = 22
  static let bubbleRadius: CGFloat = 18
}
