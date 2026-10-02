import AppKit
import SwiftUI

/// Flat, solid colours with no corner radius or translucency. Every fill is
/// an opaque system colour, so it stays readable in light and dark mode.
enum Flat {
  static let userBubble = Color.accentColor
  static let userBubbleText = Color.white
  static let assistantBubble = Color(nsColor: .controlBackgroundColor)
  static let panel = Color(nsColor: .windowBackgroundColor)
  static let banner = Color(nsColor: .controlBackgroundColor)
  static let hover = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
  static let selected = Color(nsColor: .selectedContentBackgroundColor)
  static let border = Color(nsColor: .separatorColor)
}

/// A square text field with a solid 1-point border.
struct FlatTextFieldStyle: TextFieldStyle {
  // The protocol requirement is spelled with the underscore.
  // swiftlint:disable:next identifier_name
  func _body(configuration: TextField<Self._Label>) -> some View {
    configuration
      .textFieldStyle(.plain)
      .padding(6)
      .background(Flat.assistantBubble)
      .overlay(Rectangle().stroke(Flat.border, lineWidth: 1))
  }
}
