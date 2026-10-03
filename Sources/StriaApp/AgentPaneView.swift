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
      IconSegmentedControl(selection: $tab, segments: [
        IconSegment(value: Tab.chat, symbol: "bubble.left.and.bubble.right", help: "Chat: ask about this PDF"),
        IconSegment(value: Tab.history, symbol: "clock.arrow.circlepath", help: "History: earlier questions and answers")
      ])
      .frame(maxWidth: .infinity, alignment: .leading)
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
        Button { agent.newChat() } label: { Label("New Chat", systemImage: "square.and.pencil") }
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

  /// Vendor menu and model picker, shown at the composer's bottom right.
  /// API vendors without a usable key are disabled with the reason.
  private var modelSelector: some View {
    HStack(spacing: 6) {
      Menu {
        ForEach(AgentPaneViewModel.vendorOptions, id: \.self) { vendor in
          let availability = agent.availability(of: vendor)
          Button {
            Task { await agent.select(vendor: vendor) }
          } label: {
            switch availability {
            case .ready: Text(SettingsViewModel.displayName(for: vendor))
            case .needsCredentialName: Text("\(SettingsViewModel.displayName(for: vendor)) (no API key variable in Settings)")
            case .missingKey(let name): Text("\(SettingsViewModel.displayName(for: vendor)) (\(name) not set)")
            }
          }
          .disabled(!availability.isReady)
        }
      } label: {
        Text(agent.selectedVendor.map { SettingsViewModel.displayName(for: $0) } ?? "Choose vendor…")
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      .help("Vendor that answers the question")
      if let vendor = agent.selectedVendor {
        Picker("Model", selection: Binding(
          get: { agent.selectedModel ?? "" },
          set: { model in Task { await agent.select(model: model) } }
        )) {
          ForEach(agent.modelOptions(for: vendor), id: \.self) { Text($0).tag($0) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .help("Model for this vendor")
      }
    }
    .font(.caption)
  }

  /// Shown above the composer when the selection cannot be used.
  @ViewBuilder private var selectionWarning: some View {
    if let vendor = agent.selectedVendor, !agent.availability(of: vendor).isReady {
      HStack(spacing: 8) {
        Label(warningText(for: agent.availability(of: vendor)), systemImage: "exclamationmark.triangle")
          .foregroundStyle(.orange)
        SettingsLink { Text("Open Settings…") }
      }
      .font(.callout)
      .padding(.horizontal)
      .padding(.top, 6)
    } else if agent.selectedVendor == nil {
      Text("Choose a vendor and model at the bottom right of the box below.")
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.top, 6)
    }
  }

  private func warningText(for availability: VendorAvailability) -> String {
    switch availability {
    case .ready: ""
    case .needsCredentialName: "This vendor has no API key variable configured."
    case .missingKey(let name): "Environment variable \(name) is not set; relaunch Stria with it or pick another vendor."
    }
  }

  private var scopePicker: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        IconSegmentedControl(selection: $agent.scope, segments: [
          IconSegment(value: AgentScope.page, symbol: "doc", help: "This page: the agent sees the page you are on"),
          IconSegment(value: AgentScope.nearby, symbol: "doc.on.doc", help: "Nearby pages: this page and its neighbours"),
          IconSegment(value: AgentScope.document, symbol: "books.vertical", help: "Whole PDF: the most relevant pages of the document")
        ])
        Spacer()
      }
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

  /// A wide, tall input box: the text on top, and along its bottom edge the
  /// vendor / model selector and the send (arrow) or cancel button at the
  /// right. Return inserts a new line; Cmd-Return sends.
  private var composer: some View {
    VStack(spacing: 0) {
      selectionWarning
        .id(configRevision)
      VStack(spacing: 0) {
        ZStack(alignment: .topLeading) {
          TextEditor(text: $agent.input)
            .font(.body)
            .scrollContentBackground(.hidden)
            .focused($inputFocused)
            .frame(minHeight: 96, maxHeight: 240)
            .fixedSize(horizontal: false, vertical: true)
          if agent.input.isEmpty {
            Text("Ask about this PDF…")
              .foregroundStyle(.tertiary)
              .padding(.top, 1)
              .padding(.leading, 5)
              .allowsHitTesting(false)
          }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        HStack(spacing: 8) {
          Spacer()
          modelSelector
            .id(configRevision)
          if agent.inFlight {
            Button { agent.cancel() } label: {
              Image(systemName: "stop.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
            .help("Stop waiting for this answer (Cmd-.)")
            .accessibilityLabel("Cancel")
          } else {
            Button { agent.submit() } label: {
              Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(sendDisabled ? Color.secondary : Flat.userBubble)
            .disabled(sendDisabled)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Send the question (Cmd-Return); i focuses this box")
            .accessibilityLabel("Send")
          }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
      }
      .background(Flat.assistantBubble, in: RoundedRectangle(cornerRadius: Flat.bubbleRadius))
      .overlay(RoundedRectangle(cornerRadius: Flat.bubbleRadius)
        .stroke(inputFocused ? Flat.userBubble : Flat.border, lineWidth: inputFocused ? 1.5 : 1))
      .padding(.horizontal, 10)
      .padding(.vertical, 10)
    }
  }

  private var sendDisabled: Bool {
    agent.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !agent.canSend
  }

  private var history: some View {
    VStack(alignment: .leading, spacing: 4) {
      IconSegmentedControl(selection: $agent.historyMode, segments: [
        IconSegment(value: HistoryMode.page, symbol: "doc", help: "History for this page"),
        IconSegment(value: HistoryMode.document, symbol: "books.vertical", help: "History for this whole PDF")
      ])
      .frame(maxWidth: .infinity, alignment: .leading)
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
                Text(RelativeAge.string(from: message.createdAt)).font(.caption2).foregroundStyle(.tertiary)
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
          .foregroundStyle(.secondary)
        Text(Self.attributedContent(message.content, documentId: documentId))
          .textSelection(.enabled)
          .foregroundStyle(message.status == .error ? Color.red : Color.primary)
          .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == Self.citationScheme, let page = Int(url.host() ?? "") else { return .systemAction }
            onCitation(page)
            return .handled
          })
      }
      .padding(10)
      .background(Flat.assistantBubble, in: RoundedRectangle(cornerRadius: Flat.bubbleRadius))
      .overlay(RoundedRectangle(cornerRadius: Flat.bubbleRadius)
        .stroke(isUser ? Flat.userBubble : Flat.border, lineWidth: isUser ? 1.5 : 1))
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
      .background(Flat.assistantBubble, in: RoundedRectangle(cornerRadius: Flat.bubbleRadius))
      .overlay(RoundedRectangle(cornerRadius: Flat.bubbleRadius).stroke(Flat.border, lineWidth: 1))
      Spacer(minLength: 40)
    }
    .padding(.horizontal)
  }
}
