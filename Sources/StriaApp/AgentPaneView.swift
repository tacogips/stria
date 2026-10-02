import SwiftUI
import StriaCore

/// The right pane has two tabs: Chat (scope, transcript, composer) and
/// History (past questions for this page or this PDF). Picking a history
/// entry reopens its thread in the Chat tab and jumps to its page.
struct AgentPaneView: View {
  @Bindable var agent: AgentPaneViewModel
  let reader: ReaderViewModel
  var configRevision = 0
  @State private var tab: Tab = .chat
  @FocusState private var inputFocused: Bool

  enum Tab: Hashable { case chat, history }

  var body: some View {
    VStack(spacing: 0) {
      Picker("Agent pane", selection: $tab) {
        Text("Chat").tag(Tab.chat)
        Text("History").tag(Tab.history)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .padding(.horizontal)
      .padding(.vertical, 10)
      Divider()
      tabContent
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    .onChange(of: agent.focusInputRequest) { _, _ in
      tab = .chat
      inputFocused = true
    }
    .navigationTitle("Agent")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("New Chat") { agent.newChat() }
          .disabled(agent.inFlight)
          .help("Start a new conversation (Cmd-Shift-N)")
      }
    }
  }

  @ViewBuilder private var tabContent: some View {
    VStack(spacing: 0) {
      switch tab {
      case .chat:
        scopePicker
        if !agent.vendorConfigured {
          VStack(alignment: .leading, spacing: 6) {
            Label("No agent vendor is configured.", systemImage: "gearshape")
            SettingsLink { Text("Open Settings…") }
          }
          .font(.callout)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal)
          .padding(.vertical, 8)
          .id(configRevision)
        }
        if let notice = agent.notice {
          Label(notice, systemImage: "exclamationmark.circle")
            .font(.callout)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        transcript
        composer
      case .history:
        history
      }
    }
  }

  private var scopePicker: some View {
    VStack(alignment: .leading, spacing: 6) {
      Picker("Scope", selection: $agent.scope) {
        Text("This page").tag(AgentScope.page)
        Text("Nearby pages").tag(AgentScope.nearby)
        Text("Whole PDF").tag(AgentScope.document)
      }
      .pickerStyle(.segmented)
      Text(agent.scopeDescription)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding()
  }

  private var transcript: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 12) {
          if agent.transcript.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
              Text("Try asking").font(.headline)
              ForEach(agent.suggestedQuestions, id: \.self) { question in
                Button(question) {
                  agent.input = question
                  agent.submit()
                }
                .buttonStyle(.link)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
          }
          ForEach(agent.transcript, id: \.id) { message in
            MessageView(message: message, documentId: reader.documentId) {
              reader.goToPage($0)
            }
            .id(message.id)
          }
          if agent.inFlight {
            StreamingAnswerView(text: agent.streamingAnswer ?? "")
              .id("streaming")
          }
        }
        .padding(.vertical, 8)
      }
      .onChange(of: agent.transcript.count) { _, _ in
        if let id = agent.transcript.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
      }
      .onChange(of: agent.streamingAnswer) { _, answer in
        if answer != nil { proxy.scrollTo("streaming", anchor: .bottom) }
      }
    }
  }

  private var composer: some View {
    HStack(alignment: .bottom, spacing: 8) {
      TextField("Ask about this PDF…", text: $agent.input, axis: .vertical)
        .lineLimit(2...6)
        .textFieldStyle(FlatTextFieldStyle())
        .focused($inputFocused)
        .onSubmit { agent.submit() }
      if agent.inFlight {
        Button("Cancel") { agent.cancel() }
          .help("Stop waiting for this answer (Cmd-.)")
      } else {
        Button("Send") { agent.submit() }
          .disabled(agent.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .keyboardShortcut(.return, modifiers: .command)
          .help("Send the question (Cmd-Return); / focuses this field")
      }
    }
    .padding()
  }

  private var history: some View {
    VStack(alignment: .leading, spacing: 4) {
      Picker("History", selection: $agent.historyMode) {
        Text("This page").tag(HistoryMode.page)
        Text("This PDF").tag(HistoryMode.document)
      }
      .pickerStyle(.segmented)
      .padding(.horizontal)
      .onChange(of: agent.historyMode) { _, _ in Task { await agent.reloadHistory() } }

      if agent.history.isEmpty {
        ContentUnavailableView("No Questions Yet", systemImage: "clock",
                               description: Text(agent.historyMode == .page ? "Nothing has been asked about this page." : "Nothing has been asked about this PDF."))
      } else {
        List(agent.history, id: \.id) { message in
          Button {
            Task { await agent.selectHistory(message) }
            tab = .chat
          } label: {
            VStack(alignment: .leading, spacing: 3) {
              HStack(spacing: 6) {
                Text(message.role == .user ? "You" : "Assistant")
                  .font(.caption.bold())
                  .foregroundStyle(.secondary)
                if let page = message.pageNumber {
                  Text("p. \(page)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(message.createdAt, style: .relative).font(.caption2).foregroundStyle(.tertiary)
              }
              Text(message.content)
                .lineLimit(3)
                .foregroundStyle(message.status == .error ? Color.red : Color.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
    }
    .padding(.top, 8)
    .task { await agent.reloadHistory() }
  }
}

/// One transcript bubble. `[<docId> p.<n>]` markers for the open document
/// are rendered inline as "p. n" links that scroll the PDF to that page;
/// markers for other documents stay as text.
private struct MessageView: View {
  let message: ChatMessageRecord
  let documentId: String
  let onCitation: (Int) -> Void

  private var isUser: Bool { message.role == .user }

  /// Chat-app layout: the user's questions sit on the right in the accent
  /// colour, the assistant's answers on the left.
  var body: some View {
    HStack(alignment: .bottom, spacing: 0) {
      if isUser { Spacer(minLength: 40) }
      VStack(alignment: .leading, spacing: 6) {
        Text(isUser ? "You" : "Assistant")
          .font(.caption.bold())
          .foregroundStyle(isUser ? Flat.userBubbleText.opacity(0.85) : Color.secondary)
        Text(Self.attributedContent(message.content, documentId: documentId))
          .textSelection(.enabled)
          .foregroundStyle(message.status == .error ? Color.red : (isUser ? Flat.userBubbleText : Color.primary))
          .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == Self.citationScheme, let page = Int(url.host() ?? "") else { return .systemAction }
            onCitation(page)
            return .handled
          })
      }
      .padding(10)
      .background(isUser ? Flat.userBubble : Flat.assistantBubble)
      .foregroundStyle(isUser ? Flat.userBubbleText : Color.primary)
      if !isUser { Spacer(minLength: 40) }
    }
    .padding(.horizontal)
  }

  private static let citationScheme = "stria-page"

  static func attributedContent(_ content: String, documentId: String) -> AttributedString {
    var result = AttributedString()
    var cursor = content.startIndex
    for marker in CitationParser.markers(in: content) {
      result += AttributedString(String(content[cursor..<marker.range.lowerBound]))
      if marker.docId == documentId, let url = URL(string: "\(citationScheme)://\(marker.page)") {
        var link = AttributedString("p. \(marker.page)")
        link.link = url
        link.foregroundColor = .accentColor
        link.underlineStyle = .single
        result += link
      } else {
        result += AttributedString(String(content[marker.range]))
      }
      cursor = marker.range.upperBound
    }
    result += AttributedString(String(content[cursor...]))
    return result
  }
}

/// The assistant bubble while an answer is still arriving.
private struct StreamingAnswerView: View {
  let text: String

  var body: some View {
    HStack(alignment: .bottom, spacing: 0) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          Text("Assistant").font(.caption.bold()).foregroundStyle(.secondary)
          ProgressView().controlSize(.mini)
        }
        if !text.isEmpty {
          Text(text).textSelection(.enabled)
        }
      }
      .padding(10)
      .background(Flat.assistantBubble)
      Spacer(minLength: 40)
    }
    .padding(.horizontal)
  }
}
