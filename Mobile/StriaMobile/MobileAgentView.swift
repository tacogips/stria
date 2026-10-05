import SwiftUI
import StriaCore

struct MobileAgentView: View {
  let model: MobileModel
  let reader: ReaderViewModel
  @Bindable var agent: AgentPaneViewModel
  @FocusState private var inputFocused: Bool
  @State private var tab: AgentPaneTab = .chat
  @State private var settingsPresented = false
  @Environment(\.horizontalSizeClass) private var sizeClass

  var body: some View {
    VStack(spacing: 0) {
      Picker("Agent tab", selection: $tab) {
        Text("Chat").tag(AgentPaneTab.chat)
        Text("History").tag(AgentPaneTab.history)
        Text("Summary").tag(AgentPaneTab.summary)
      }.pickerStyle(.segmented).padding(12)
      Divider()
      switch tab {
      case .chat: chat
      case .history: history
      case .summary: MobileSummaryView(model: model, reader: reader)
      }
    }
    .background(Flat.panel)
    .sheet(isPresented: $settingsPresented) {
      MobileSettingsView(settings: model.settings, sync: model.sync)
    }
    .sheet(isPresented: Binding(get: { sizeClass != .regular && model.search.isShowingResults },
                                set: { if !$0 { model.search.close() } })) {
      MobileSearchResults(model: model)
    }
    .task { await agent.reloadHistory() }
    .onChange(of: agent.focusInputRequest) { _, _ in tab = .chat; inputFocused = true }
    .onChange(of: agent.historyMode) { _, _ in Task { await agent.reloadHistory() } }
  }

  private var chat: some View {
    VStack(spacing: 0) {
      HStack {
        Text(agent.chatTitle).font(.headline).lineLimit(2)
        Spacer()
        if agent.isTitlingCurrentChat { ProgressView() }
        Button { Task { await agent.retitle() } } label: { Image(systemName: "arrow.clockwise") }
          .disabled(agent.threadId == nil || agent.isTitlingCurrentChat)
          .accessibilityLabel("Regenerate chat title")
        Button { agent.newChat() } label: { Image(systemName: "square.and.pencil") }
          .disabled(agent.inFlight).accessibilityLabel("New chat")
      }.padding(12)
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
            if agent.transcript.isEmpty {
              Text("Ask about this PDF. Add an API key in Settings to get started.")
                .foregroundStyle(.secondary).padding(.vertical)
            }
            ForEach(agent.transcript, id: \.id) { message in
              VStack(alignment: .leading, spacing: 8) {
                Text(message.role == .user ? "You" : "Stria").font(.caption.bold())
                Text(message.content).textSelection(.enabled)
                HStack {
                  ForEach(agent.citationPages(in: message), id: \.self) { page in
                    Button("p. \(page)") { reader.goToPage(page) }.font(.caption)
                  }
                }
              }
              .padding(12).frame(maxWidth: .infinity, alignment: .leading)
              .foregroundStyle(message.role == .user ? Color.white : Color.primary)
              .background(message.role == .user ? Color.accentColor : Flat.assistantBubble)
            }
            if let answer = agent.streamingAnswer { Text(answer.isEmpty ? "Thinking…" : answer).padding(12) }
            if let notice = agent.notice { Text(notice).font(.callout).foregroundStyle(.orange) }
            Color.clear.frame(height: 1).id("end")
          }.padding(12)
        }
        .onChange(of: agent.transcript.count) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
        .onChange(of: agent.streamingAnswer) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
      }
      Divider()
      composer
    }
  }

  private var composer: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Menu {
          ForEach(KnownVendors.selectable(on: .iOS), id: \.self) { vendor in
            Menu(SettingsViewModel.displayName(for: vendor)) {
              ForEach(agent.modelOptions(for: vendor), id: \.self) { model in
                Button(model) { Task { await agent.select(vendor: vendor); await agent.select(model: model) } }
                  .disabled(!agent.availability(of: vendor).isReady)
              }
              if !agent.availability(of: vendor).isReady { Text("Add an API key in Settings") }
            }
          }
        } label: {
          Label(agent.selectedModel ?? "Choose vendor / model", systemImage: "cpu").font(.caption)
        }
        Spacer()
        Button { model.settings.load(); settingsPresented = true } label: { Image(systemName: "gearshape") }
          .accessibilityLabel("Agent settings")
      }
      if let vendor = agent.selectedVendor, !KnownVendors.isAvailableOnThisPlatform(vendor, platform: .iOS) {
        Text(KnownVendors.platformUnavailableReason).font(.caption).foregroundStyle(.orange)
      }
      Picker("Context", selection: $agent.scope) {
        Text("Page").tag(AgentScope.page)
        Text("Nearby").tag(AgentScope.nearby)
        Text("PDF").tag(AgentScope.document)
      }.pickerStyle(.segmented)
      Text(agent.scopeDescription).font(.caption).foregroundStyle(.secondary)
      HStack(alignment: .bottom) {
        TextField("Ask a question", text: $agent.input, axis: .vertical)
          .focused($inputFocused)
          .lineLimit(1...5).padding(8).overlay(Rectangle().stroke(Flat.border))
        VoiceInputButton(agent: agent)
        if agent.inFlight {
          Button("Cancel") { agent.cancel() }
        } else {
          Button { agent.submit() } label: { Image(systemName: "arrow.up") }
            .accessibilityLabel("Send question")
            .disabled(!agent.canSend || agent.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }.padding(12)
  }

  private var history: some View {
    VStack {
      Picker("History scope", selection: $agent.historyMode) {
        Text("This page").tag(HistoryMode.page)
        Text("This PDF").tag(HistoryMode.document)
      }.pickerStyle(.segmented).padding(12)
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
