import SwiftUI
import StriaCore

struct ReaderView: View {
  @Bindable var model: AppModel
  @Bindable var reader: ReaderViewModel
  @Bindable var agent: AgentPaneViewModel
  @AppStorage("showAgentInspector") private var showAgent = true
  @State private var showPageSheet = false
  @State private var showShortcutHelp = false
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  @State private var shortcuts = ReaderShortcutMonitor()
  @AppStorage(Appearance.storageKey) private var appearance = Appearance.default

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      LeftPaneView(reader: reader)
        .navigationSplitViewColumnWidth(min: 180, ideal: 280, max: 640)
    } detail: {
      PDFKitView(reader: reader)
        .background(.background)
        .navigationTitle(reader.title)
    }
    .inspector(isPresented: $showAgent) {
      AgentPaneView(agent: agent, reader: reader, configRevision: model.configRevision)
        .inspectorColumnWidth(min: 300, ideal: 400, max: 720)
    }
    .searchable(text: $reader.searchQuery, placement: .toolbar, prompt: "Search OCR text")
    .onSubmit(of: .search) { Task { await reader.submitSearch(reader.searchQuery) } }
    .onChange(of: reader.searchQuery) { _, query in
      if query.isEmpty { reader.clearSearch() }
    }
    .onChange(of: reader.currentPage) { _, _ in agent.scheduleHistoryReload() }
    .focusedSceneValue(\.striaReader, reader)
    .focusedSceneValue(\.striaAgent, agent)
    .focusedSceneValue(\.striaPageSheet, $showPageSheet)
    .focusedSceneValue(\.striaAgentVisibility, $showAgent)
    .focusedSceneValue(\.striaShortcutHelp, $showShortcutHelp)
    .toolbar {
      ToolbarItem(placement: .navigation) {
        Button("Library") { Task { await model.showLibrary() } }
          .help("Back to the library (Cmd-Shift-L)")
      }
      ToolbarItem(placement: .principal) {
        PageFieldView(reader: reader)
      }
      ToolbarItem(placement: .primaryAction) {
        Button { showAgent.toggle() } label: {
          Label("Agent", systemImage: "sidebar.right")
        }
        .help("Show or hide the agent pane (Cmd-Opt-0)")
      }
    }
    .sheet(isPresented: $showPageSheet) {
      GoToPageSheet(reader: reader, isPresented: $showPageSheet)
    }
    .sheet(isPresented: $showShortcutHelp) {
      ShortcutHelpSheet(isPresented: $showShortcutHelp)
    }
    .task { await agent.reloadHistory() }
    .onAppear { shortcuts.install(handle) }
    .onDisappear { shortcuts.remove() }
  }

  private func handle(_ shortcut: ReaderShortcut) {
    switch shortcut {
    case .toggleLeftPane: columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
    case .toggleAgentPane: showAgent.toggle()
    case .focusAgentInput:
      showAgent = true
      agent.requestInputFocus()
    case .pageDown: reader.requestScroll(.pageDown)
    case .pageUp: reader.requestScroll(.pageUp)
    case .lineDown: reader.requestScroll(.lineDown)
    case .lineUp: reader.requestScroll(.lineUp)
    case .toggleTheme: appearance = appearance.toggled
    case .help: showShortcutHelp = true
    }
  }
}
