import SwiftUI
import StriaCore

struct AgentPaneView: View {
  @Bindable var agent: AgentPaneViewModel
  let reader: ReaderViewModel

  var body: some View {
    VStack(spacing: 0) {
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
      Divider()
      history
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
        LazyVStack(alignment: .leading, spacing: 12) {
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
        .textFieldStyle(.roundedBorder)
        .onSubmit { agent.submit() }
      if agent.inFlight {
        Button("Cancel") { agent.cancel() }
          .help("Stop waiting for this answer (Cmd-.)")
      } else {
        Button("Send") { agent.submit() }
          .disabled(agent.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .keyboardShortcut(.return, modifiers: .command)
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

      List(agent.history, id: \.id) { message in
        Button {
          Task { await agent.selectHistory(message) }
        } label: {
          VStack(alignment: .leading, spacing: 3) {
            Text(message.role == .user ? message.content : "Answer: \(message.content)")
              .lineLimit(2)
            if let page = message.pageNumber {
              Text("Page \(page)").font(.caption).foregroundStyle(.secondary)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
      }
      .frame(minHeight: 100, maxHeight: 220)
    }
    .padding(.vertical, 8)
  }
}

/// One transcript bubble. `[<docId> p.<n>]` markers for the open document
/// are rendered inline as "p. n" links that scroll the PDF to that page;
/// markers for other documents stay as text.
private struct MessageView: View {
  let message: ChatMessageRecord
  let documentId: String
  let onCitation: (Int) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(message.role == .user ? "You" : "Assistant")
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
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background(message.role == .user ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: 8))
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
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Text("Assistant").font(.caption.bold()).foregroundStyle(.secondary)
        ProgressView().controlSize(.mini)
      }
      if !text.isEmpty {
        Text(text).textSelection(.enabled)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background(Color.secondary.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .padding(.horizontal)
  }
}
