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
  @FocusedValue(\.striaSidebar) private var sidebar
  @FocusedValue(\.striaSearch) private var search
  @FocusedValue(\.striaLibraryViewMode) private var libraryViewMode
  @FocusedValue(\.striaRunOCR) private var runOCR
  @FocusedValue(\.striaReaderShortcut) private var readerShortcut
  @AppStorage(Appearance.storageKey) private var appearance = Appearance.default
  @Environment(\.openSettings) private var openSettings

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
      Button("Show/Hide Sidebar") { sidebar?.wrappedValue = sidebar?.wrappedValue == .detailOnly ? .all : .detailOnly }
        .keyboardShortcut("s", modifiers: [.command, .control])
        .disabled(sidebar == nil)

      Button("Show/Hide Agent") {
        if let agentVisibility { agentVisibility.wrappedValue.toggle() }
      }
      .keyboardShortcut("0", modifiers: [.command, .option])
      .disabled(agentVisibility == nil)

      Button("Library") { libraryAction?() }
        .keyboardShortcut("l", modifiers: [.command, .shift])
        .disabled(reader == nil)

      Divider()
      Button("Library as List") { libraryViewMode?.wrappedValue = .list }
        .keyboardShortcut("1", modifiers: .command)
        .disabled(libraryViewMode == nil)
      Button("Library as Cards") { libraryViewMode?.wrappedValue = .card }
        .keyboardShortcut("2", modifiers: .command)
        .disabled(libraryViewMode == nil)

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
      Button("Settings…") { openSettings() }
        .keyboardShortcut(",", modifiers: [.command, .shift])
      Divider()
      Button(agent?.dictationState.isRecording == true ? "Stop Dictation" : "Start Dictation") { readerShortcut?(.toggleDictation) }
        .keyboardShortcut("m", modifiers: [.command, .shift])
        .disabled(readerShortcut == nil || agent?.inFlight == true || (agent?.dictationState.isActive == true && agent?.dictationState.isRecording != true))
      Button("Focus Chat Input") { readerShortcut?(.focusAgentInput) }
        .keyboardShortcut("l", modifiers: .command)
        .disabled(readerShortcut == nil)
      Button("New Chat") { readerShortcut?(.newChat) }
        .keyboardShortcut("n", modifiers: [.command, .shift])
        .disabled(readerShortcut == nil || agent?.inFlight == true)
      Button("Resume Previous Chat") { readerShortcut?(.resumePreviousChat) }
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .disabled(readerShortcut == nil || agent?.inFlight == true)
      Button("Go to Chat Start Page") { readerShortcut?(.conversationStart) }
        .keyboardShortcut("j", modifiers: [.command, .shift])
        .disabled(readerShortcut == nil || agent?.conversationStartPage == nil)
      Button("Cancel Question") { agent?.cancel() }
        .keyboardShortcut(".", modifiers: .command)
        .disabled(agent?.inFlight != true)
    }

    CommandGroup(after: .textEditing) {
      Button("Search OCR Text…") { search?() }
        .keyboardShortcut("f", modifiers: .command)
        .disabled(search == nil)
    }

    CommandGroup(replacing: .help) {
      Button("Keyboard Shortcuts") { shortcutHelp?.wrappedValue = true }
        .keyboardShortcut("/", modifiers: .command)
        .disabled(shortcutHelp == nil)
    }

    CommandGroup(replacing: .newItem) {
      Button("Import PDF…") { importAction?() }
        .keyboardShortcut("o", modifiers: .command)
      Button("Run OCR…") { runOCR?() }
        .keyboardShortcut("o", modifiers: [.command, .shift])
        .disabled(runOCR == nil)
    }
  }
}
