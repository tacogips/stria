import SwiftUI
import StriaCore

private struct ReaderFocusedKey: FocusedValueKey { typealias Value = ReaderViewModel }
private struct PageSheetFocusedKey: FocusedValueKey { typealias Value = Binding<Bool> }
private struct AgentVisibilityFocusedKey: FocusedValueKey { typealias Value = Binding<Bool> }
private struct LibraryActionFocusedKey: FocusedValueKey { typealias Value = () -> Void }
private struct ImportActionFocusedKey: FocusedValueKey { typealias Value = () -> Void }
private struct AgentFocusedKey: FocusedValueKey { typealias Value = AgentPaneViewModel }
private struct ShortcutHelpFocusedKey: FocusedValueKey { typealias Value = Binding<Bool> }

extension FocusedValues {
  var striaReader: ReaderViewModel? {
    get { self[ReaderFocusedKey.self] }
    set { self[ReaderFocusedKey.self] = newValue }
  }

  var striaPageSheet: Binding<Bool>? {
    get { self[PageSheetFocusedKey.self] }
    set { self[PageSheetFocusedKey.self] = newValue }
  }

  var striaAgentVisibility: Binding<Bool>? {
    get { self[AgentVisibilityFocusedKey.self] }
    set { self[AgentVisibilityFocusedKey.self] = newValue }
  }

  var striaLibrary: (() -> Void)? {
    get { self[LibraryActionFocusedKey.self] }
    set { self[LibraryActionFocusedKey.self] = newValue }
  }

  var striaImport: (() -> Void)? {
    get { self[ImportActionFocusedKey.self] }
    set { self[ImportActionFocusedKey.self] = newValue }
  }

  var striaAgent: AgentPaneViewModel? {
    get { self[AgentFocusedKey.self] }
    set { self[AgentFocusedKey.self] = newValue }
  }

  var striaShortcutHelp: Binding<Bool>? {
    get { self[ShortcutHelpFocusedKey.self] }
    set { self[ShortcutHelpFocusedKey.self] = newValue }
  }
}
