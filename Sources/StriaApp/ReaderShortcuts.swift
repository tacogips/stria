import AppKit
import SwiftUI
import StriaCore

/// Single-key reader shortcuts in the style of chilla: they act while no
/// text field is being edited, and never steal typing. Command-key
/// equivalents stay on the menus (`StriaCommands`).
enum ReaderShortcut: CaseIterable {
  case backToLibrary, search, toggleLeftPane, toggleAgentPane, focusAgentInput, newChat, resumePreviousChat
  case toggleDictation, conversationStart, pageDown, pageUp, lineDown, lineUp, toggleTheme, help

  var keys: String {
    switch self {
    case .backToLibrary: "Esc"
    case .search: "/"
    case .toggleLeftPane: "Shift+L"
    case .toggleAgentPane: "Shift+R"
    case .toggleDictation: "m"
    case .focusAgentInput: "i"
    case .newChat: "n"
    case .resumePreviousChat: "r"
    case .conversationStart: "s"
    case .pageDown: "Ctrl+D"
    case .pageUp: "Ctrl+U"
    case .lineDown: "j"
    case .lineUp: "k"
    case .toggleTheme: "Shift+D"
    case .help: "?"
    }
  }

  var title: String {
    switch self {
    case .backToLibrary: "Close search results, or back to the library"
    case .search: "Search the OCR text"
    case .toggleLeftPane: "Collapse or expand the left pane"
    case .toggleAgentPane: "Collapse or expand the agent pane"
    case .toggleDictation: "Start or stop voice dictation in the agent chat"
    case .focusAgentInput: "Focus the agent chat input"
    case .newChat: "Start a new chat"
    case .resumePreviousChat: "Resume the previous chat about this PDF (repeat for older ones)"
    case .conversationStart: "Go to the page where the open chat started"
    case .pageDown: "Page the PDF down"
    case .pageUp: "Page the PDF up"
    case .lineDown: "Scroll the PDF down"
    case .lineUp: "Scroll the PDF up"
    case .toggleTheme: "Toggle light and dark mode"
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
    if event.keyCode == 53 { return .backToLibrary }  // Esc
    switch (characters, flags.contains(.shift)) {
    case ("L", true), ("l", true): return .toggleLeftPane
    case ("R", true), ("r", true): return .toggleAgentPane
    case ("D", true), ("d", true): return .toggleTheme
    case ("/", _): return .search
    case ("m", false): return .toggleDictation
    case ("i", false): return .focusAgentInput
    case ("n", false): return .newChat
    case ("r", false): return .resumePreviousChat
    case ("s", false): return .conversationStart
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
  private let menuTracking = MenuTrackingState()

  func install(_ handler: @escaping @MainActor (ReaderShortcut) -> Void, cancelDictation: @escaping @MainActor () -> Bool = { false },
               isDictating: @escaping @MainActor () -> Bool = { false }) {
    remove()
    menuTracking.start()
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self else { return event }
      if !self.menuTracking.isTracking, event.keyCode == 53, cancelDictation() { return nil }
      guard !self.menuTracking.isTracking, let shortcut = ReaderShortcut.match(event) else { return event }
      guard !Self.isEditingText() || (shortcut == .toggleDictation && isDictating()) else { return event }
      // Esc belongs to a sheet or popover while one is open.
      if shortcut == .backToLibrary, Self.sheetIsOpen() { return event }
      handler(shortcut)
      return nil
    }
  }

  func remove() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    menuTracking.stop()
  }

  /// True while a sheet (Go to Page, shortcut help, a confirmation) is up.
  private static func sheetIsOpen() -> Bool {
    guard let window = NSApp.keyWindow else { return false }
    return window.attachedSheet != nil || window.sheetParent != nil
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
    ScrollView {
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
          GridRow { Text("Ctrl-Cmd-S").font(.system(.body, design: .monospaced)); Text("Hide / show the sidebar") }
          GridRow { Text("Cmd-Opt-0").font(.system(.body, design: .monospaced)); Text("Hide / show the agent pane") }
          GridRow { Text("Cmd-Opt-G").font(.system(.body, design: .monospaced)); Text("Go to page") }
          GridRow { Text("Cmd-Opt-Up/Down").font(.system(.body, design: .monospaced)); Text("Previous / next page") }
          GridRow { Text("Cmd-+ / Cmd--").font(.system(.body, design: .monospaced)); Text("Zoom in / out") }
          GridRow { Text("Cmd-F").font(.system(.body, design: .monospaced)); Text("Search the OCR text") }
          GridRow { Text("Cmd-Shift-M").font(.system(.body, design: .monospaced)); Text("Start / stop dictation; Esc cancels") }
          GridRow { Text("Cmd-Return").font(.system(.body, design: .monospaced)); Text("Send the question") }
          GridRow { Text("Cmd-.").font(.system(.body, design: .monospaced)); Text("Cancel the question") }
          GridRow { Text("Cmd-Shift-L").font(.system(.body, design: .monospaced)); Text("Back to the library") }
          GridRow { Text("Cmd-Shift-D").font(.system(.body, design: .monospaced)); Text("Toggle light / dark (View > Appearance)") }
        }
        Text("Single-key shortcuts pause while you type. While recording, m stops and Esc cancels dictation.").font(.caption).foregroundStyle(.secondary)
        HStack { Spacer(); Button("Close") { isPresented = false }.keyboardShortcut(.cancelAction) }
      }
      .padding(16)
    }
    .frame(minWidth: 280, idealWidth: 420, maxWidth: 420, maxHeight: 460)
  }
}

/// A local key monitor for a screen: the handler returns true to consume the
/// event. Inactive while a text field has focus or a sheet is open.
@MainActor
final class LocalKeyMonitor {
  private var monitor: Any?
  private let menuTracking = MenuTrackingState()

  func install(_ handler: @escaping @MainActor (NSEvent) -> Bool) {
    remove()
    menuTracking.start()
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self else { return event }
      guard !self.menuTracking.isTracking, let window = NSApp.keyWindow, window.attachedSheet == nil, window.sheetParent == nil else { return event }
      if let responder = window.firstResponder, responder is NSTextView || responder is NSTextField { return event }
      return handler(event) ? nil : event
    }
  }

  func remove() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    menuTracking.stop()
  }
}

/// A menu owns Escape and typing while it is tracking; reader shortcuts must
/// not navigate away or open a search sheet underneath it.
@MainActor
private final class MenuTrackingState {
  private(set) var isTracking = false
  private var observers: [NSObjectProtocol] = []

  func start() {
    stop()
    let center = NotificationCenter.default
    observers = [
      center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.isTracking = true }
      },
      center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.isTracking = false }
      }
    ]
  }

  func stop() {
    observers.forEach { NotificationCenter.default.removeObserver($0) }
    observers = []
    isTracking = false
  }
}
