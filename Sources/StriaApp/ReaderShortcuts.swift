import AppKit
import SwiftUI
import StriaCore

/// Single-key reader shortcuts in the style of chilla: they act while no
/// text field is being edited, and never steal typing. Command-key
/// equivalents stay on the menus (`StriaCommands`).
enum ReaderShortcut: CaseIterable {
  case toggleLeftPane, toggleAgentPane, focusAgentInput, pageDown, pageUp, lineDown, lineUp, help

  var keys: String {
    switch self {
    case .toggleLeftPane: "Shift+L"
    case .toggleAgentPane: "Shift+R"
    case .focusAgentInput: "/"
    case .pageDown: "Ctrl+D"
    case .pageUp: "Ctrl+U"
    case .lineDown: "j"
    case .lineUp: "k"
    case .help: "?"
    }
  }

  var title: String {
    switch self {
    case .toggleLeftPane: "Collapse or expand the left pane"
    case .toggleAgentPane: "Collapse or expand the agent pane"
    case .focusAgentInput: "Focus the agent chat input"
    case .pageDown: "Page the PDF down"
    case .pageUp: "Page the PDF up"
    case .lineDown: "Scroll the PDF down"
    case .lineUp: "Scroll the PDF up"
    case .help: "Show this list"
    }
  }

  /// Maps a key event to a shortcut; nil when the event is not one.
  static func match(_ event: NSEvent) -> ReaderShortcut? {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard !flags.contains(.command), !flags.contains(.option) else { return nil }
    let characters = event.charactersIgnoringModifiers ?? ""
    if flags.contains(.control) {
      switch characters.lowercased() {
      case "d": return .pageDown
      case "u": return .pageUp
      default: return nil
      }
    }
    switch (characters, flags.contains(.shift)) {
    case ("L", true), ("l", true): return .toggleLeftPane
    case ("R", true), ("r", true): return .toggleAgentPane
    case ("/", _): return .focusAgentInput
    case ("?", _): return .help
    case ("j", false): return .lineDown
    case ("k", false): return .lineUp
    default: return nil
    }
  }
}

/// Installs a local key monitor while the reader is on screen.
@MainActor
final class ReaderShortcutMonitor {
  private var monitor: Any?

  func install(_ handler: @escaping @MainActor (ReaderShortcut) -> Void) {
    remove()
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      guard !Self.isEditingText(), let shortcut = ReaderShortcut.match(event) else { return event }
      handler(shortcut)
      return nil
    }
  }

  func remove() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
  }

  /// True while a text field or text view has keyboard focus.
  private static func isEditingText() -> Bool {
    guard let responder = NSApp.keyWindow?.firstResponder else { return false }
    return responder is NSTextView || responder is NSTextField
  }
}

struct ShortcutHelpSheet: View {
  @Binding var isPresented: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Keyboard Shortcuts").font(.headline)
      Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
        ForEach(ReaderShortcut.allCases, id: \.self) { shortcut in
          GridRow {
            Text(shortcut.keys).font(.system(.body, design: .monospaced)).frame(width: 70, alignment: .leading)
            Text(shortcut.title)
          }
        }
        Divider().gridCellColumns(2)
        GridRow { Text("Cmd-Opt-G").font(.system(.body, design: .monospaced)); Text("Go to page") }
        GridRow { Text("Cmd-Opt-Up/Down").font(.system(.body, design: .monospaced)); Text("Previous / next page") }
        GridRow { Text("Cmd-+ / Cmd--").font(.system(.body, design: .monospaced)); Text("Zoom in / out") }
        GridRow { Text("Cmd-Return").font(.system(.body, design: .monospaced)); Text("Send the question") }
        GridRow { Text("Cmd-.").font(.system(.body, design: .monospaced)); Text("Cancel the question") }
        GridRow { Text("Cmd-Shift-L").font(.system(.body, design: .monospaced)); Text("Back to the library") }
      }
      Text("Single-key shortcuts pause while you type in a text field.").font(.caption).foregroundStyle(.secondary)
      HStack { Spacer(); Button("Close") { isPresented = false }.keyboardShortcut(.cancelAction) }
    }
    .padding(20)
    .frame(width: 420)
  }
}
