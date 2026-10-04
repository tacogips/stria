import AppKit
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
  @State private var sendKey = ControlMSendMonitor()

  enum Tab: Hashable { case chat, history }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        IconSegmentedControl(selection: $tab, segments: [
          IconSegment(value: Tab.chat, symbol: "bubble.left.and.bubble.right", help: "Chat: ask about this PDF"),
          IconSegment(value: Tab.history, symbol: "clock.arrow.circlepath", help: "History: earlier questions and answers")
        ])
        Divider().frame(height: 22)
        Button { agent.newChat(); agent.requestInputFocus() } label: {
          Image(systemName: "square.and.pencil")
        }
        .buttonStyle(.plain)
        .disabled(agent.inFlight)
        .help("Start a new conversation (n or Cmd-Shift-N)")
        .accessibilityLabel("New Chat")
        Button {
          Task { if await agent.resumePreviousChat() { agent.requestInputFocus() } }
        } label: {
          Image(systemName: "arrow.uturn.backward.circle")
        }
        .buttonStyle(.plain)
        .disabled(agent.inFlight)
        .help("Resume the previous chat about this PDF; repeat for older ones (r or Cmd-Shift-R)")
        .accessibilityLabel("Resume Previous Chat")
        Spacer(minLength: 0)
        if let page = agent.conversationStartPage {
          Button { agent.goToConversationStart() } label: {
            Label("p.\(page)", systemImage: "flag")
              .labelStyle(.titleAndIcon)
              .font(.caption)
          }
          .buttonStyle(.plain)
          .help("Go to page \(page), where this chat started (s or Cmd-Shift-J)")
          .accessibilityLabel("Go to Chat Start Page")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal)
      .padding(.vertical, 8)
      Divider()
      tabContent
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    .onAppear {
      if agent.focusInputRequest > 0 { tab = .chat; inputFocused = true }
    }
    .onAppear { sendKey.install { inputFocused && !sendDisabled ? (agent.submit(), true).1 : false } }
    .onDisappear { sendKey.remove() }
    .onChange(of: agent.focusInputRequest) { _, _ in
      tab = .chat
      inputFocused = true
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

  /// Vendor and model controls stacked along the composer's bottom edge.
  /// API vendors without a usable key are disabled with the reason.
  private var modelSelector: some View {
    VStack(alignment: .leading, spacing: 4) {
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
      .lineLimit(1)
      .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("Model for this vendor")
      }
    }
    .font(.caption)
  }

  /// Shown above the composer when the selection cannot be used.
  @ViewBuilder private var selectionWarning: some View {
    if let vendor = agent.selectedVendor, !agent.availability(of: vendor).isReady {
      VStack(alignment: .leading, spacing: 6) {
        Label(warningText(for: agent.availability(of: vendor)), systemImage: "exclamationmark.triangle")
          .foregroundStyle(.orange)
        SettingsLink { Text("Open Settings…") }
      }
      .font(.callout)
      .padding(.horizontal)
      .padding(.top, 6)
    } else if agent.selectedVendor == nil {
      Text("Choose a vendor and model below.")
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
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  private var transcript: some View {
    ScrollViewReader { proxy in
      ScrollView {
        // Eager layout avoids a macOS sheet sizing loop when reopening long answers.
        VStack(spacing: 12) {
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
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onChange(of: agent.transcript.count) { _, _ in
        if let id = agent.transcript.last?.id { proxy.scrollTo(id, anchor: .bottom) }
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
            .frame(height: 96)
            .accessibilityLabel("Question")
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
            .help("Send the question (Cmd-Return or Ctrl-M); i or Cmd-L focuses this box")
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

      if agent.threads.isEmpty {
        ContentUnavailableView("No Conversations Yet", systemImage: "clock",
                               description: Text(agent.historyMode == .page ? "Nothing has been asked about this page." : "Nothing has been asked about this PDF."))
      } else {
        List(agent.threads) { thread in
          Button {
            Task { await agent.selectThread(thread) }
            tab = .chat
          } label: {
            ThreadRow(thread: thread, isSummarizing: agent.summarizingThreadIDs.contains(thread.threadId))
          }
          .buttonStyle(.plain)
          .contextMenu {
            Button(thread.summary == nil ? "Summarize" : "Summarize Again") {
              Task { await agent.summarize(threadId: thread.threadId) }
            }
            .disabled(agent.summarizingThreadIDs.contains(thread.threadId) || agent.selection == nil)
          }
        }
        .listStyle(.plain)
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
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
          .foregroundStyle(message.status == .error ? Color.red : Color.primary)
          .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == Self.citationScheme, let page = Int(url.host() ?? "") else { return .systemAction }
            onCitation(page)
            return .handled
          })
      }
      .frame(maxWidth: .infinity, alignment: .leading)
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
          Text(text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
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

/// A conversation in the History tab: its summary, then the question that
/// started it, the page, the number of messages and when it last changed.
private struct ThreadRow: View {
  let thread: ThreadOverview
  let isSummarizing: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        if let page = thread.pageNumber {
          Text("p. \(page)").font(.caption.bold()).foregroundStyle(.secondary)
        }
        Text("\(thread.messageCount) messages").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Text(RelativeAge.string(from: thread.updatedAt)).font(.caption2).foregroundStyle(.tertiary)
      }
      summary
      Text(thread.firstQuestion)
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .help("First question: \(thread.firstQuestion)")
    }
    .padding(.vertical, 4)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }

  @ViewBuilder private var summary: some View {
    if let text = thread.summary {
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(text).lineLimit(4)
        if isSummarizing {
          ProgressView().controlSize(.mini)
        } else if !thread.isSummaryCurrent {
          Image(systemName: "clock.badge.exclamationmark").font(.caption).foregroundStyle(.secondary)
            .help("Newer messages are not in this summary yet; right-click > Summarize Again")
        }
      }
    } else if isSummarizing {
      HStack(spacing: 6) {
        ProgressView().controlSize(.mini)
        Text("Summarizing…").foregroundStyle(.secondary)
      }
    } else {
      Text("No summary yet (right-click > Summarize)").font(.callout).foregroundStyle(.tertiary)
    }
  }
}

/// Ctrl-M sends the chat message (terminal habit: Ctrl-M is Return). The
/// handler decides, so it only fires while the chat input has focus.
@MainActor
final class ControlMSendMonitor {
  private var monitor: Any?

  func install(_ handler: @escaping @MainActor () -> Bool) {
    remove()
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      guard flags == .control, event.charactersIgnoringModifiers?.lowercased() == "m" else { return event }
      return handler() ? nil : event
    }
  }

  func remove() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
  }
}
