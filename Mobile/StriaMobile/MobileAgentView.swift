import SwiftUI
import StriaCore

struct MobileAgentView: View {
  let model: MobileModel
  let reader: ReaderViewModel
  @Bindable var agent: AgentPaneViewModel
  var compact = false
  /// When set (the lower-half pane), a small icon at the right closes the pane.
  var onClose: (() -> Void)?
  @FocusState private var inputFocused: Bool
  @State private var tab: AgentPaneTab = .chat
  @State private var settingsPresented = false
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      switch tab {
      case .chat: chat
      case .history: history
      case .summary: MobileSummaryView(model: model, reader: reader)
      }
    }
    .background(Flat.panel)
    .sheet(isPresented: $settingsPresented, onDismiss: agent.refreshCredentialStatus) {
      MobileSettingsView(settings: model.settings, sync: model.sync)
    }
    .sheet(isPresented: Binding(get: { sizeClass != .regular && model.search.isShowingResults },
                                set: { if !$0 { model.search.close() } })) {
      MobileSearchResults(model: model)
    }
    .task { await agent.reloadHistory() }
    .onChange(of: agent.focusInputRequest) { _, _ in tab = .chat; inputFocused = true }
    .onChange(of: agent.historyMode) { _, _ in Task { await agent.reloadHistory() } }
    .onChange(of: scenePhase) { _, phase in if phase == .active { agent.refreshCredentialStatus() } }
  }

  /// Tabs as an icon capsule at the top left; compose, resume and close as
  /// round icons at the right. No text labels.
  private var toolbar: some View {
    HStack(spacing: 8) {
      MobileIconSegments(selection: $tab, segments: [
        MobileIconSegment(value: AgentPaneTab.chat, symbol: "bubble.left.fill", label: "Chat"),
        MobileIconSegment(value: AgentPaneTab.history, symbol: "clock.arrow.circlepath", label: "History"),
        MobileIconSegment(value: AgentPaneTab.summary, symbol: "doc.text", label: "Summary")
      ])
      Spacer()
      MobileToolbarIcon(symbol: "arrow.uturn.backward", label: "Resume previous chat") {
        Task { if await agent.resumePreviousChat() { tab = .chat; inputFocused = true } }
      }
      .disabled(agent.inFlight)
      MobileToolbarIcon(symbol: "square.and.pencil", label: "New chat") {
        agent.newChat(); tab = .chat; inputFocused = true
      }
      .disabled(agent.inFlight)
      if let onClose {
        MobileToolbarIcon(symbol: "xmark", label: "Hide agent", action: onClose)
      }
    }
    .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
  }

  /// Shown only once a conversation exists; a new chat has no title row.
  private var showsChatTitle: Bool {
    agent.currentThread != nil || agent.transcript.contains { $0.role == .user }
  }

  private var chat: some View {
    VStack(spacing: 0) {
      if showsChatTitle {
        HStack(spacing: 6) {
          Text(agent.chatTitle).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            .lineLimit(1).truncationMode(.tail)
          if agent.isTitlingCurrentChat { ProgressView().controlSize(.mini) }
          Spacer()
          MobileToolbarIcon(symbol: "wand.and.stars", label: "Regenerate chat title", diameter: 24) {
            Task { await agent.retitle() }
          }
          .disabled(agent.threadId == nil || agent.isTitlingCurrentChat)
        }
        .padding(.horizontal, 16).padding(.bottom, 2)
      }
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 10) {
            ForEach(agent.transcript, id: \.id) { message in bubble(message) }
            if let answer = agent.streamingAnswer {
              Text(answer.isEmpty ? "Thinking…" : answer)
                .foregroundStyle(answer.isEmpty ? .secondary : .primary)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Flat.assistantBubble, in: RoundedRectangle(cornerRadius: Flat.bubbleRadius))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let notice = agent.notice {
              Text(notice).font(.footnote).foregroundStyle(Flat.coral).frame(maxWidth: .infinity, alignment: .leading)
            }
            Color.clear.frame(height: 1).id("end")
          }.padding(.horizontal, 12).padding(.vertical, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: agent.transcript.count) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
        .onChange(of: agent.streamingAnswer) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
      }
      .frame(maxHeight: agent.isNewChat ? 0 : .infinity)
      if compact {
        ScrollView { composer }
          .frame(maxHeight: agent.isNewChat ? .infinity : 300)
      } else {
        composer
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  /// User questions: ink bubbles on the right. Answers: soft cards on the
  /// left with their page citations as small capsules.
  private func bubble(_ message: ChatMessageRecord) -> some View {
    let isUser = message.role == .user
    return HStack {
      if isUser { Spacer(minLength: 48) }
      VStack(alignment: .leading, spacing: 8) {
        Text(message.content).textSelection(.enabled)
          .foregroundStyle(isUser ? Color.white : (message.status == .error ? Flat.coral : Color.primary))
        let pages = agent.citationPages(in: message)
        if !pages.isEmpty {
          HStack(spacing: 6) {
            ForEach(pages, id: \.self) { page in
              Button("p. \(page)") { reader.goToPage(page) }
                .font(.caption.weight(.medium)).foregroundStyle(Flat.ink)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Flat.ink.opacity(0.1), in: Capsule())
                .buttonStyle(.plain)
            }
          }
        }
      }
      .padding(.horizontal, 14).padding(.vertical, 10)
      .background(isUser ? Flat.ink : Flat.assistantBubble, in: RoundedRectangle(cornerRadius: Flat.bubbleRadius))
      if !isUser { Spacer(minLength: 24) }
    }
  }

  /// One large rounded card: the question on top, and along its bottom edge
  /// the model chip, the context scope icons, the microphone and send.
  private var composer: some View {
    VStack(alignment: .leading, spacing: 10) {
      ZStack(alignment: .topLeading) {
        TextEditor(text: $agent.input)
          .focused($inputFocused)
          .scrollContentBackground(.hidden)
          .frame(minHeight: compact ? 110 : 180,
                 idealHeight: compact ? (agent.isNewChat ? 250 : 150) : (agent.isNewChat ? 300 : 240),
                 maxHeight: compact ? (agent.isNewChat ? .infinity : 220) : (agent.isNewChat ? .infinity : 360))
          .accessibilityLabel("Question")
        if agent.input.isEmpty {
          Text(placeholder).foregroundStyle(.tertiary)
            .padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
        }
      }
      HStack(spacing: 8) {
        modelChip
        MobileIconSegments(selection: $agent.scope, segments: [
          MobileIconSegment(value: AgentScope.page, symbol: "doc", label: "This page"),
          MobileIconSegment(value: AgentScope.nearby, symbol: "doc.on.doc", label: "Nearby pages"),
          MobileIconSegment(value: AgentScope.document, symbol: "book", label: "Whole PDF")
        ], style: .subtle)
        .accessibilityHint(agent.scopeDescription)
        Spacer(minLength: 0)
        VoiceInputButton(agent: agent)
        sendButton
      }
    }
    .padding(12)
    .background(Flat.assistantBubble, in: RoundedRectangle(cornerRadius: Flat.cardRadius))
    .overlay(RoundedRectangle(cornerRadius: Flat.cardRadius)
      .stroke(inputFocused ? Flat.ink.opacity(0.5) : Color.clear, lineWidth: 1.5))
    .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 12)
  }

  private var placeholder: String {
    switch agent.scope {
    case .page: "Ask about this page"
    case .nearby: "Ask about these pages"
    case .document: "Ask about this PDF"
    }
  }

  /// The vendor/model menu. Settings lives inside it; a missing setup shows
  /// as a coral dot on the chip instead of a warning block.
  private var modelChip: some View {
    Menu {
      if let warning = agent.configurationWarning { Text(warning) }
      ForEach(KnownVendors.selectable(on: .iOS), id: \.self) { vendor in
        Menu(SettingsViewModel.displayName(for: vendor)) {
          ForEach(agent.modelOptions(for: vendor), id: \.self) { model in
            Button(model) { Task { await agent.select(vendor: vendor); await agent.select(model: model) } }
              .disabled(!agent.availability(of: vendor).isReady)
          }
          if !agent.availability(of: vendor).isReady { Text("Add an API key in Settings") }
        }
      }
      Divider()
      Button { model.settings.load(); settingsPresented = true } label: { Label("Settings…", systemImage: "gearshape") }
    } label: {
      HStack(spacing: 4) {
        Text(agent.selectedModel ?? "Choose model").lineLimit(1)
        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
      }
      .font(.caption.weight(.medium)).foregroundStyle(Color.primary)
      .padding(.horizontal, 10).frame(height: 32)
      .background(Color.primary.opacity(0.07), in: Capsule())
      .overlay(alignment: .topTrailing) {
        if agent.configurationWarning != nil {
          Circle().fill(Flat.coral).frame(width: 9, height: 9).offset(x: 2, y: -2)
        }
      }
    }
    .accessibilityLabel("Model")
    .accessibilityValue(agent.configurationWarning ?? agent.selectedModel ?? "None")
  }

  @ViewBuilder private var sendButton: some View {
    if agent.inFlight {
      Button { agent.cancel() } label: {
        Image(systemName: "stop.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
          .frame(width: 34, height: 34).background(Flat.coral, in: Circle())
      }
      .buttonStyle(.plain).accessibilityLabel("Cancel")
    } else {
      let disabled = !agent.canSend || agent.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      Button { agent.submit() } label: {
        Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
          .frame(width: 34, height: 34).background(disabled ? Color.secondary.opacity(0.35) : Flat.ink, in: Circle())
      }
      .buttonStyle(.plain).disabled(disabled).accessibilityLabel("Send question")
    }
  }

  private var history: some View {
    VStack {
      HStack {
        MobileIconSegments(selection: $agent.historyMode, segments: [
          MobileIconSegment(value: HistoryMode.page, symbol: "doc", label: "History for this page"),
          MobileIconSegment(value: HistoryMode.document, symbol: "book", label: "History for this PDF")
        ], style: .subtle)
        Spacer()
      }.padding(.horizontal, 12).padding(.top, 8)
      List(agent.threads, id: \.threadId) { thread in
        Button {
          Task { await agent.selectThread(thread); tab = .chat }
        } label: {
          VStack(alignment: .leading, spacing: 6) {
            Text(thread.displayTitle).font(.headline)
            if let summary = thread.summary { Text(summary).font(.callout).lineLimit(4) }
            Text(thread.firstQuestion).font(.caption).lineLimit(2)
            Text(RelativeAge.string(from: thread.updatedAt)).font(.caption2).foregroundStyle(.secondary)
          }
        }
      }.listStyle(.plain)
      .overlay {
        if agent.threads.isEmpty { ContentUnavailableView("No Conversations", systemImage: "bubble.left") }
      }
    }
  }
}

struct MobileSummaryView: View {
  let model: MobileModel
  let reader: ReaderViewModel
  @State private var record: PageSummaryRecord?
  @State private var tags: [String] = []
  @State private var runSheet = false
  private var row: LibraryRow? { model.library.rows.first { $0.id == reader.documentId } }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        Text("Page \(reader.currentPage)").font(.headline)
        if let counts = row?.summaries {
          Text("Coverage: \(counts.done)/\(counts.total) current · \(counts.stale) stale · \(counts.failed) failed")
            .font(.caption).foregroundStyle(.secondary)
        }
        if let progress = model.library.summaryProgress[reader.documentId] {
          Text(progress.phase == .ocr ? "Running OCR first" : "Summarizing")
          ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1)))
          Text("\(progress.completed) / \(progress.total)").font(.caption)
          Button("Cancel") { model.library.cancelSummaries(documentId: reader.documentId) }
        }
        if let report = model.library.summaryReports[reader.documentId] { Text(report.text).font(.caption) }
        if !tags.isEmpty {
          Text("Tags").font(.caption.bold())
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], alignment: .leading) {
            ForEach(tags, id: \.self) { tag in
              Button(tag) {
                Task { await model.search.search(for: tag) }
              }.font(.caption).padding(6).overlay(Rectangle().stroke(Flat.border))
            }
          }
        }
        if let record {
          if record.isStale { Label("OCR changed since this summary", systemImage: "exclamationmark.triangle").font(.caption) }
          if let error = record.error { Text(error).foregroundStyle(.orange) }
          Text(record.summary ?? "No summary text.").textSelection(.enabled)
          Text("\(PageSummaryLanguage.displayName(record.language)) · \(RelativeAge.string(from: record.updatedAt))")
            .font(.caption).foregroundStyle(.secondary)
        } else {
          Text(model.library.summaryConfigured ? "No summary for this page yet. Pages without OCR text are OCRed first." : "Choose a summary vendor and model in Settings.")
            .foregroundStyle(.secondary)
        }
        Button("Summarize Pages…") { runSheet = true }.disabled(!model.library.summaryConfigured)
      }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
    }
    .task(id: "\(reader.currentPage)-\(model.library.summaryRevision)-\(model.syncRevision)") {
      record = await model.library.pageSummary(documentId: reader.documentId, page: reader.currentPage)
      tags = await model.library.pageInfo(documentId: reader.documentId, page: reader.currentPage)?.ocrTags ?? []
    }
    .sheet(isPresented: $runSheet) {
      if let row {
        MobileRunSheet(row: row, currentPage: reader.currentPage, settings: model.settings, library: model.library, summary: true)
      }
    }
  }
}
