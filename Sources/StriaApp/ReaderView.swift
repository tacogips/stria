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
      LeftPaneView(reader: reader, onBack: { Task { await model.showLibrary() } })
        .navigationSplitViewColumnWidth(min: 180, ideal: 280, max: 640)
        // Must sit on the sidebar column itself to take effect on macOS; the
        // pane header has Stria's own hide icon.
        .toolbar(removing: .sidebarToggle)
    } detail: {
      PDFKitView(reader: reader)
        .background(.background)
        .navigationTitle(reader.title)
        .overlay {
          if model.search.isShowingResults {
            SearchResultsView(search: model.search) { hit in Task { await model.openSearchResult(hit) } }
          }
        }
        .overlay(alignment: .leading) {
          if columnVisibility == .detailOnly {
            // chilla-style edge tab: the collapsed sidebar comes back with one click.
            Button { toggleSidebar() } label: {
              Image(systemName: "chevron.right")
                .font(.caption.bold())
                .frame(width: 14, height: 44)
                .background(Flat.assistantBubble)
                .overlay(Rectangle().stroke(Flat.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Show the sidebar (Ctrl-Cmd-S or Shift+L)")
          }
        }
    }
    .inspector(isPresented: $showAgent) {
      AgentPaneView(agent: agent, reader: reader, configRevision: model.configRevision)
        .inspectorColumnWidth(min: 300, ideal: 400, max: 720)
    }
    .sheet(isPresented: Bindable(model.search).isPromptPresented) {
      SearchPrompt(search: model.search)
    }
    .focusedSceneValue(\.striaSearch, { model.search.present() })
    .onChange(of: reader.currentPage) { _, _ in agent.scheduleHistoryReload() }
    .focusedSceneValue(\.striaReader, reader)
    .focusedSceneValue(\.striaAgent, agent)
    .focusedSceneValue(\.striaPageSheet, $showPageSheet)
    .focusedSceneValue(\.striaAgentVisibility, $showAgent)
    .focusedSceneValue(\.striaShortcutHelp, $showShortcutHelp)
    .focusedSceneValue(\.striaSidebar, $columnVisibility)
    .toolbar {
      ToolbarItem(placement: .navigation) {
        Button { toggleSidebar() } label: {
          Label(columnVisibility == .detailOnly ? "Show Sidebar" : "Hide Sidebar", systemImage: "sidebar.left")
        }
        .help((columnVisibility == .detailOnly ? "Show the sidebar" : "Hide the sidebar") + " (Ctrl-Cmd-S or Shift+L)")
      }
      ToolbarItem(placement: .principal) {
        PageFieldView(reader: reader)
      }
      ToolbarItem(placement: .primaryAction) {
        Button { showAgent.toggle() } label: {
          Label("Agent", systemImage: "sidebar.right")
        }
        .help((showAgent ? "Hide the agent pane" : "Show the agent pane") + " (Cmd-Opt-0 or Shift+R)")
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

  private func toggleSidebar() {
    columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
  }

  private func handle(_ shortcut: ReaderShortcut) {
    switch shortcut {
    case .backToLibrary:
      if model.search.isShowingResults { model.search.close() } else { Task { await model.showLibrary() } }
    case .search: model.search.present()
    case .toggleLeftPane: toggleSidebar()
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
