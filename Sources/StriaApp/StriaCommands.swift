import SwiftUI
import StriaCore

struct StriaCommands: Commands {
  @FocusedValue(\.striaReader) private var reader
  @FocusedValue(\.striaPageSheet) private var pageSheet
  @FocusedValue(\.striaAgentVisibility) private var agentVisibility
  @FocusedValue(\.striaLibrary) private var libraryAction
  @FocusedValue(\.striaImport) private var importAction

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
    }

    CommandGroup(replacing: .newItem) {
      Button("Import PDF…") { importAction?() }
        .keyboardShortcut("o", modifiers: .command)
    }
  }
}
