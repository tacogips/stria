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
          .keyboardShortcut("n", modifiers: [.command, .shift])
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
                Button(question) { Task { await agent.send(suggestion: question) } }
                  .buttonStyle(.link)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
          }
          ForEach(agent.transcript, id: \.id) { message in
            MessageView(message: message, citationPages: agent.citationPages(in: message)) {
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
        .onSubmit { Task { await agent.send() } }
      Button("Send") { Task { await agent.send() } }
        .disabled(agent.inFlight || agent.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .keyboardShortcut(.return, modifiers: .command)
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

private struct MessageView: View {
  let message: ChatMessageRecord
  let citationPages: [Int]
  let onCitation: (Int) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(message.role == .user ? "You" : "Assistant")
        .font(.caption.bold())
        .foregroundStyle(.secondary)
      Text(message.content)
        .textSelection(.enabled)
        .foregroundStyle(message.status == .error ? Color.red : Color.primary)
      if !citationPages.isEmpty {
        HStack {
          ForEach(citationPages, id: \.self) { page in
            Button("p. \(page)") { onCitation(page) }
              .buttonStyle(.bordered)
              .controlSize(.small)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background(message.role == .user ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .padding(.horizontal)
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
