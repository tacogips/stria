import SwiftUI
import StriaCore

struct ReaderView: View {
  @Bindable var model: AppModel
  @Bindable var reader: ReaderViewModel
  @Bindable var agent: AgentPaneViewModel
  @AppStorage("showAgentInspector") private var showAgent = true
  @State private var compactSidebar = false
  @State private var compactAgent = false
  @State private var availableWidth: CGFloat = 1100
  @State private var showPageSheet = false
  @State private var showShortcutHelp = false
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  @State private var shortcuts = ReaderShortcutMonitor()
  @AppStorage(Appearance.storageKey) private var appearance = Appearance.default

  var body: some View {
    GeometryReader { geometry in
      readerContent
        .onAppear { availableWidth = geometry.size.width }
        .onChange(of: geometry.size.width) { _, width in availableWidth = width }
        .sheet(isPresented: $compactSidebar) {
          compactPane(title: "Contents", geometry: geometry) {
            LeftPaneView(reader: reader)
          }
        }
        .sheet(isPresented: $compactAgent) {
          compactPane(title: "Agent", geometry: geometry, scrollsWhenShort: true) {
            AgentPaneView(agent: agent, reader: reader, configRevision: model.configRevision)
          }
        }
    }
  }

  private var sidebarVisible: Bool { availableWidth >= 760 && columnVisibility != .detailOnly }
  private var agentVisible: Bool { availableWidth >= 1000 && showAgent }

  private var sidebarControl: Binding<NavigationSplitViewVisibility> {
    Binding(get: { availableWidth < 760 ? (compactSidebar ? .all : .detailOnly) : columnVisibility },
            set: { value in
              if availableWidth < 760 { compactSidebar = value != .detailOnly } else { columnVisibility = value }
            })
  }

  private var agentControl: Binding<Bool> {
    availableWidth < 1000 ? $compactAgent : $showAgent
  }

  private func compactPane<Content: View>(
    title: String,
    geometry: GeometryProxy,
    scrollsWhenShort: Bool = false,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(spacing: 0) {
      HStack {
        Text(title).font(.headline)
        Spacer()
        Button("Done") { compactSidebar = false; compactAgent = false }
          .keyboardShortcut(.cancelAction)
      }
      .padding(12)
      Divider()
      if scrollsWhenShort, geometry.size.height < 480 {
        ScrollView { content().frame(height: 420) }
      } else {
        content()
      }
    }
    .frame(width: min(400, max(280, geometry.size.width - 32)),
           height: max(180, geometry.size.height - 32))
  }

  private var readerContent: some View {
    HSplitView {
      if sidebarVisible {
        LeftPaneView(reader: reader)
          .frame(minWidth: 180, idealWidth: 240, maxWidth: 400)
          .background(Flat.panel)
      }
      PDFKitView(reader: reader)
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        .background(Flat.panel)
        .overlay {
          if model.search.isShowingResults {
            SearchResultsView(search: model.search) { hit in Task { await model.openSearchResult(hit) } }
          }
        }
      if agentVisible {
        AgentPaneView(agent: agent, reader: reader, configRevision: model.configRevision)
          .frame(minWidth: 300, idealWidth: 360, maxWidth: 600)
          .background(Flat.panel)
      }
    }
    .navigationTitle(reader.title)
    .toolbarRole(.editor)
    .sheet(isPresented: Bindable(model.search).isPromptPresented) {
      SearchPrompt(search: model.search)
    }
    .alert("Error", isPresented: Binding(
      get: { model.library.alert != nil },
      set: { if !$0 { model.library.alert = nil } }
    )) {
      Button("OK", role: .cancel) { model.library.alert = nil }
    } message: {
      Text(model.library.alert ?? "")
    }
    .focusedSceneValue(\.striaSearch, { model.search.present() })
    .onChange(of: reader.currentPage) { _, _ in agent.scheduleHistoryReload() }
    .focusedSceneValue(\.striaReader, reader)
    .focusedSceneValue(\.striaAgent, agent)
    .focusedSceneValue(\.striaPageSheet, $showPageSheet)
    .focusedSceneValue(\.striaAgentVisibility, agentControl)
    .focusedSceneValue(\.striaShortcutHelp, $showShortcutHelp)
    .focusedSceneValue(\.striaSidebar, sidebarControl)
    .toolbar {
      if availableWidth < 540 {
        ToolbarItem(placement: .principal) {
          HStack(spacing: 10) {
            libraryButton
            sidebarButton
            PageFieldView(reader: reader, compact: true)
            agentButton
          }
          .buttonStyle(.plain)
          .accessibilityElement(children: .contain)
          .fixedSize()
        }
      } else {
        ToolbarItemGroup(placement: .navigation) {
          libraryButton
          sidebarButton
        }
        ToolbarItem(placement: .principal) {
          PageFieldView(reader: reader)
        }
        ToolbarItem(placement: .primaryAction) {
          agentButton
        }
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

  private var libraryButton: some View {
    Button { Task { await model.showLibrary() } } label: {
      Label("Library", systemImage: "chevron.backward").labelStyle(.iconOnly)
    }
    .accessibilityLabel("Back to the library")
    .help("Back to the library (Esc or Cmd-Shift-L)")
  }

  private var sidebarButton: some View {
    Button { toggleSidebar() } label: {
      Label(sidebarVisible ? "Hide Sidebar" : "Show Sidebar", systemImage: "sidebar.left").labelStyle(.iconOnly)
    }
    .accessibilityLabel(sidebarVisible ? "Hide Sidebar" : "Show Sidebar")
    .help((sidebarVisible ? "Hide the sidebar" : "Show the sidebar") + " (Ctrl-Cmd-S or Shift+L)")
  }

  private var agentButton: some View {
    Button { toggleAgent() } label: {
      Label("Agent", systemImage: "sidebar.right").labelStyle(.iconOnly)
    }
    .accessibilityLabel(agentVisible ? "Hide Agent" : "Show Agent")
    .help((agentVisible ? "Hide the agent pane" : "Show the agent pane") + " (Cmd-Opt-0 or Shift+R)")
  }

  private func toggleSidebar() {
    if availableWidth < 760 { compactSidebar.toggle(); return }
    columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
  }

  private func toggleAgent() {
    if availableWidth < 1000 { compactAgent.toggle(); return }
    showAgent.toggle()
  }

  private func handle(_ shortcut: ReaderShortcut) {
    switch shortcut {
    case .backToLibrary:
      if model.search.isShowingResults { model.search.close() } else { Task { await model.showLibrary() } }
    case .search: model.search.present()
    case .toggleLeftPane: toggleSidebar()
    case .toggleAgentPane: toggleAgent()
    case .focusAgentInput:
      if availableWidth < 1000 { compactAgent = true } else { showAgent = true }
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
