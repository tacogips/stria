import SwiftUI
import StriaCore

struct ReaderView: View {
  @Bindable var model: AppModel
  @Bindable var reader: ReaderViewModel
  @Bindable var agent: AgentPaneViewModel
  @AppStorage("showAgentInspector") private var showAgent = true
  @State private var showPageSheet = false

  var body: some View {
    NavigationSplitView {
      LeftPaneView(reader: reader)
        .navigationSplitViewColumnWidth(min: 210, ideal: 260, max: 360)
    } detail: {
      PDFKitView(reader: reader)
        .background(.background)
        .navigationTitle(reader.title)
    }
    .inspector(isPresented: $showAgent) {
      AgentPaneView(agent: agent, reader: reader)
        .inspectorColumnWidth(min: 290, ideal: 360, max: 480)
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
    .task { await agent.reloadHistory() }
  }
}
