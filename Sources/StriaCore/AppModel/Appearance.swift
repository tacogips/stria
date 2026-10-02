import Foundation

/// The app-wide colour scheme choice. Light is the default; the user can
/// switch to dark or follow the system, from Settings, the View menu or
/// the `Shift+D` reader shortcut.
public enum Appearance: String, CaseIterable, Sendable {
  case light
  case dark
  case system

  public static let storageKey = "appearance"
  public static let `default` = Appearance.light

  public var title: String {
    switch self {
    case .light: "Light"
    case .dark: "Dark"
    case .system: "System"
    }
  }

  /// Light <-> dark; "system" becomes dark (the toggle always has a visible effect).
  public var toggled: Appearance {
    self == .dark ? .light : .dark
  }
}
