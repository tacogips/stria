import SwiftUI
import StriaCore

struct ReaderView: View {
  @Bindable var model: AppModel
  @Bindable var reader: ReaderViewModel
  @Bindable var agent: AgentPaneViewModel
  @AppStorage("showAgentInspector") private var showAgent = true
  @State private var showPageSheet = false
  @State private var columnVisibility: NavigationSplitViewVisibility = .all

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      LeftPaneView(reader: reader)
        .navigationSplitViewColumnWidth(min: 210, ideal: 260, max: 360)
    } detail: {
      PDFKitView(reader: reader)
        .background(.background)
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
    .onChange(of: reader.currentPage) { _, _ in Task { await agent.reloadHistory() } }
    .focusedSceneValue(\.striaReader, reader)
    .focusedSceneValue(\.striaPageSheet, $showPageSheet)
    .focusedSceneValue(\.striaAgentVisibility, $showAgent)
    .toolbar {
      ToolbarItem(placement: .navigation) {
        Button {
          columnVisibility = columnVisibility == .all ? .detailOnly : .all
        } label: {
          Label("Toggle Sidebar", systemImage: "sidebar.left")
        }
        .help("Show or hide the sidebar")
      }
      ToolbarItem(placement: .navigation) {
        Button("Library") { Task { await model.showLibrary() } }
          .keyboardShortcut("l", modifiers: [.command, .shift])
      }
      ToolbarItem(placement: .principal) {
        PageFieldView(reader: reader)
      }
      ToolbarItem(placement: .primaryAction) {
        Button { showAgent.toggle() } label: {
          Label("Agent", systemImage: "sidebar.right")
        }
        .keyboardShortcut("0", modifiers: [.command, .option])
      }
    }
    .sheet(isPresented: $showPageSheet) {
      GoToPageSheet(reader: reader, isPresented: $showPageSheet)
    }
    .task { await agent.reloadHistory() }
  }
}
