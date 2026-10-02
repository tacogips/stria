import SwiftUI
import StriaCore

/// Every shortcut lives here, once. Toolbar buttons call the same actions
/// without their own `.keyboardShortcut`, so a key press never fires twice.
struct StriaCommands: Commands {
  @FocusedValue(\.striaReader) private var reader
  @FocusedValue(\.striaPageSheet) private var pageSheet
  @FocusedValue(\.striaAgentVisibility) private var agentVisibility
  @FocusedValue(\.striaLibrary) private var libraryAction
  @FocusedValue(\.striaImport) private var importAction
  @FocusedValue(\.striaAgent) private var agent
  @FocusedValue(\.striaShortcutHelp) private var shortcutHelp
  @AppStorage(Appearance.storageKey) private var appearance = Appearance.default

  var body: some Commands {
    CommandMenu("Go") {
      Button("Go to Page…") {
        pageSheet?.wrappedValue = true
      }
      .keyboardShortcut("g", modifiers: [.command, .option])
      .disabled(reader == nil)

      Button("Next Page") { reader?.nextPage() }
        .keyboardShortcut(.downArrow, modifiers: [.command, .option])
        .disabled(reader == nil)
      Button("Previous Page") { reader?.previousPage() }
        .keyboardShortcut(.upArrow, modifiers: [.command, .option])
        .disabled(reader == nil)
    }

    CommandGroup(after: .sidebar) {
      Button("Show/Hide Agent") {
        if let agentVisibility { agentVisibility.wrappedValue.toggle() }
      }
      .keyboardShortcut("0", modifiers: [.command, .option])
      .disabled(agentVisibility == nil)

      Button("Library") { libraryAction?() }
        .keyboardShortcut("l", modifiers: [.command, .shift])
        .disabled(reader == nil)

      Divider()
      Picker("Appearance", selection: $appearance) {
        ForEach(Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
      }
      Button("Toggle Light/Dark") { appearance = appearance.toggled }
        .keyboardShortcut("d", modifiers: [.command, .shift])

      Divider()
      Button("Zoom In") { reader?.requestZoom(.zoomIn) }
        .keyboardShortcut("+", modifiers: .command)
        .disabled(reader == nil)
      Button("Zoom Out") { reader?.requestZoom(.zoomOut) }
        .keyboardShortcut("-", modifiers: .command)
        .disabled(reader == nil)
      Button("Actual Size") { reader?.requestZoom(.actualSize) }
        .keyboardShortcut("0", modifiers: .command)
        .disabled(reader == nil)
      Button("Zoom to Fit") { reader?.requestZoom(.fitWidth) }
        .keyboardShortcut("9", modifiers: .command)
        .disabled(reader == nil)
    }

    CommandMenu("Agent") {
      Button("New Chat") { agent?.newChat() }
        .keyboardShortcut("n", modifiers: [.command, .shift])
        .disabled(agent == nil)
      Button("Cancel Question") { agent?.cancel() }
        .keyboardShortcut(".", modifiers: .command)
        .disabled(agent?.inFlight != true)
    }

    CommandGroup(replacing: .help) {
      Button("Keyboard Shortcuts") { shortcutHelp?.wrappedValue = true }
        .keyboardShortcut("/", modifiers: .command)
        .disabled(shortcutHelp == nil)
    }

    CommandGroup(replacing: .newItem) {
      Button("Import PDF…") { importAction?() }
        .keyboardShortcut("o", modifiers: .command)
    }
  }
}
