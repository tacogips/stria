import AppKit
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
  /// The document's library row while the OCR run sheet is open.
  @State private var ocrRow: LibraryRow?
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  @State private var shortcuts = ReaderShortcutMonitor()
  @AppStorage(Appearance.storageKey) private var appearance = Appearance.default
  /// The side panes' last widths, restored the next time a reader opens.
  @AppStorage("readerLeftPaneWidth") private var leftPaneWidth = 240.0
  @AppStorage("readerAgentPaneWidth") private var agentPaneWidth = 360.0

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
            agentPane()
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
          .frame(minWidth: 180, idealWidth: leftPaneWidth, maxWidth: 400)
          .background(Flat.panel)

      }
      PDFKitView(reader: reader)
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        .background(Flat.panel)
        .background(SplitWidthKeeper(leftVisible: sidebarVisible, agentVisible: agentVisible,
                                     leftWidth: $leftPaneWidth, agentWidth: $agentPaneWidth))
        .overlay {
          if model.search.isShowingResults {
            SearchResultsView(search: model.search) { hit in Task { await model.openSearchResult(hit) } }
          }
        }
      if agentVisible {
        agentPane()
          .frame(minWidth: 300, idealWidth: agentPaneWidth, maxWidth: 600)
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
    .focusedSceneValue(\.striaReaderShortcut, { handle($0) })
    .focusedSceneValue(\.striaPageSheet, $showPageSheet)
    .focusedSceneValue(\.striaAgentVisibility, agentControl)
    .focusedSceneValue(\.striaShortcutHelp, $showShortcutHelp)
    .focusedSceneValue(\.striaSidebar, sidebarControl)
    .focusedSceneValue(\.striaRunOCR, { presentOCR() })
    .toolbar {
      if availableWidth < 540 {
        ToolbarItem(placement: .principal) {
          HStack(spacing: 10) {
            libraryButton
            sidebarButton
            PageFieldView(reader: reader, compact: true)
            ocrButton
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
        ToolbarItemGroup(placement: .primaryAction) {
          summaryIndicator
          ocrButton
          agentButton
        }
      }
    }
    .sheet(isPresented: $showPageSheet) {
      GoToPageSheet(reader: reader, isPresented: $showPageSheet)
    }
    .sheet(item: $ocrRow) { row in
      OCRRunSheet(row: row, initialPages: String(reader.currentPage),
                  vendorDescription: model.settings.ocrVendorDescription) { range in
        Task { await model.library.runOCR(documentId: row.id, range: range) }
      }
    }
    .sheet(isPresented: $showShortcutHelp) {
      ShortcutHelpSheet(isPresented: $showShortcutHelp)
    }
    .task { await agent.reloadHistory() }
    .onAppear { shortcuts.install(handle) }
    .onDisappear { shortcuts.remove() }
  }

  private func agentPane() -> AgentPaneView {
    AgentPaneView(agent: agent, reader: reader, library: model.library, configRevision: model.configRevision) { text in
      compactAgent = false
      Task { await model.search.search(for: text) }
    }
  }

  private var libraryButton: some View {
    Button { Task { await model.showLibrary() } } label: {
      Label("Library", systemImage: "chevron.backward").labelStyle(.iconOnly)
    }
    .accessibilityLabel("Back to the library")
    .help("Back to the library (Esc or Cmd-Shift-L)")
  }

  /// Shown while this PDF's summaries are being written; opens the Summary tab.
  @ViewBuilder private var summaryIndicator: some View {
    if let progress = model.library.summaryProgress[reader.documentId] {
      Button {
        revealAgent()
        agent.requestedTab = .summary
      } label: {
        HStack(spacing: 6) {
          ProgressView().controlSize(.small)
          if progress.total > 0 {
            Text("\(progress.phase == .ocr ? "OCR" : "Summary") \(min(progress.completed, progress.total))/\(progress.total)")
              .font(.caption).monospacedDigit()
          }
        }
      }
      .help("Page summaries are being written; click to show the Summary tab")
      .accessibilityLabel("Summarizing pages")
    }
  }

  private var documentRow: LibraryRow? { model.library.rows.first { $0.id == reader.documentId } }

  private func presentOCR() {
    guard model.library.ocrConfigured, let row = documentRow, !row.isBusy else { return }
    ocrRow = row
  }

  @ViewBuilder private var ocrButton: some View {
    let busy = documentRow?.isBusy == true
    Button { presentOCR() } label: {
      if busy {
        ProgressView().controlSize(.small)
      } else {
        Label("Run OCR", systemImage: "text.viewfinder").labelStyle(.iconOnly)
      }
    }
    .disabled(!model.library.ocrConfigured || busy || documentRow == nil)
    .accessibilityLabel(busy ? "OCR running" : "Run OCR")
    .help(busy ? "OCR is running on this PDF"
          : model.library.ocrConfigured
          ? "Run OCR on this page, a page range, the remaining pages or all pages (Cmd-Shift-O)"
          : "Choose an OCR vendor in Settings first (Agent > Settings…)")
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

  private func revealAgent() {
    if availableWidth < 1000 { compactAgent = true } else { showAgent = true }
  }

  private func handle(_ shortcut: ReaderShortcut) {
    switch shortcut {
    case .backToLibrary:
      if model.search.isShowingResults { model.search.close() } else { Task { await model.showLibrary() } }
    case .search: model.search.present()
    case .toggleLeftPane: toggleSidebar()
    case .toggleAgentPane: toggleAgent()
    case .focusAgentInput:
      revealAgent()
      agent.requestInputFocus()
    case .newChat:
      guard !agent.inFlight else { return }
      revealAgent()
      agent.newChat()
      agent.requestInputFocus()
    case .resumePreviousChat:
      revealAgent()
      Task { if await agent.resumePreviousChat() { agent.requestInputFocus() } }
    case .conversationStart: agent.goToConversationStart()
    case .pageDown: reader.requestScroll(.pageDown)
    case .pageUp: reader.requestScroll(.pageUp)
    case .lineDown: reader.requestScroll(.lineDown)
    case .lineUp: reader.requestScroll(.lineUp)
    case .toggleTheme: appearance = appearance.toggled
    case .help: showShortcutHelp = true
    }
  }
}

/// Keeps the side panes' widths across launches. It finds the split view
/// that hosts the reader's panes, moves its dividers to the saved widths when
/// the layout appears (or a pane is shown again), and saves a width only when
/// the user drags a divider, so window resizes and tiling never overwrite it.
private struct SplitWidthKeeper: NSViewRepresentable {
  let leftVisible: Bool
  let agentVisible: Bool
  @Binding var leftWidth: Double
  @Binding var agentWidth: Double

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> NSView {
    let view = ProbeView()
    view.onAttach = { [weak coordinator = context.coordinator] probe in coordinator?.attach(from: probe) }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    let coordinator = context.coordinator
    coordinator.leftVisible = leftVisible
    coordinator.agentVisible = agentVisible
    coordinator.saveLeft = { leftWidth = $0 }
    coordinator.saveAgent = { agentWidth = $0 }
    coordinator.savedLeft = leftWidth
    coordinator.savedAgent = agentWidth
    coordinator.applySavedWidths()
  }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
    coordinator.detach()
  }

  final class ProbeView: NSView {
    var onAttach: ((NSView) -> Void)?
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if window != nil { DispatchQueue.main.async { [weak self] in if let self { self.onAttach?(self) } } }
    }
  }

  @MainActor
  final class Coordinator {
    var leftVisible = false
    var agentVisible = false
    var saveLeft: (Double) -> Void = { _ in }
    var saveAgent: (Double) -> Void = { _ in }
    var savedLeft = 0.0
    var savedAgent = 0.0
    private weak var splitView: NSSplitView?
    private var observer: NSObjectProtocol?
    private var isRestoring = false

    func attach(from probe: NSView) {
      var view: NSView? = probe
      while let current = view, !(current is NSSplitView) { view = current.superview }
      guard let split = view as? NSSplitView, split !== splitView else { return }
      detach()
      splitView = split
      observer = NotificationCenter.default.addObserver(
        forName: NSSplitView.didResizeSubviewsNotification, object: split, queue: .main
      ) { [weak self] note in
        // User drags carry the divider index and are saved; any other
        // resize (window, tiling, a pane shown) puts the saved widths back.
        let dragged = note.userInfo?["NSSplitViewDividerIndex"] != nil
        MainActor.assumeIsolated { dragged ? self?.saveWidths() : self?.applySavedWidths() }
      }
      applySavedWidths()
    }

    func detach() {
      if let observer { NotificationCenter.default.removeObserver(observer) }
      observer = nil
      splitView = nil
    }

    /// Moves the dividers so the side panes have their saved widths and the
    /// PDF takes the rest.
    func applySavedWidths() {
      guard !isRestoring, let split = splitView, split.bounds.width > 0 else { return }
      isRestoring = true
      defer { isRestoring = false }
      let panes = split.arrangedSubviews.isEmpty ? split.subviews : split.arrangedSubviews
      let expected = 1 + (leftVisible ? 1 : 0) + (agentVisible ? 1 : 0)
      guard panes.count == expected else { return }
      if leftVisible, abs(Double(panes[0].frame.width) - savedLeft) > 1 {
        split.setPosition(CGFloat(savedLeft), ofDividerAt: 0)
      }
      if agentVisible, let last = panes.last, abs(Double(last.frame.width) - savedAgent) > 1 {
        split.setPosition(split.bounds.width - CGFloat(savedAgent) - split.dividerThickness,
                          ofDividerAt: panes.count - 2)
      }
    }

    private func saveWidths() {
      // SwiftUI moves dividers too; only a mouse drag is the user's choice.
      guard !isRestoring, let split = splitView, let event = NSApp.currentEvent,
            event.type == .leftMouseDragged || event.type == .leftMouseUp, event.window === split.window else { return }
      let panes = split.arrangedSubviews.isEmpty ? split.subviews : split.arrangedSubviews
      if leftVisible, let first = panes.first { saveLeft(Double(first.frame.width.rounded())) }
      if agentVisible, let last = panes.last, panes.count > 1 { saveAgent(Double(last.frame.width.rounded())) }
    }
  }
}
