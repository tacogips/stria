import SwiftUI
import StriaCore

/// The agent pane's Summary tab: the current page's OCR tags (click one to
/// search every PDF for it), its summary, the run in progress, and a button
/// that summarizes again with instructions.
struct PageSummaryPane: View {
  @Bindable var library: LibraryViewModel
  let reader: ReaderViewModel
  var configRevision = 0
  /// Searches every PDF for a tag.
  var onTag: (String) -> Void = { _ in }
  @State private var record: PageSummaryRecord?
  @State private var ocrStatus: OCRStatus?
  @State private var tags: [String] = []
  @State private var missingCount = 0
  @State private var loaded = false
  @State private var sheetRow: LibraryRow?

  private var page: Int { reader.currentPage }
  private var row: LibraryRow? { library.rows.first { $0.id == reader.documentId } }
  private var progress: PageSummaryProgress? { library.summaryProgress[reader.documentId] }
  private var report: PageSummaryRunReport? { library.summaryReports[reader.documentId] }
  private var queued: Int { library.queuedSummaryRuns[reader.documentId] ?? 0 }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if library.summaryConfigured { runStatus }
          if !tags.isEmpty { tagList }
          content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
      }
    }
    .task(id: LoadKey(document: reader.documentId, page: page, revision: library.summaryRevision, config: configRevision,
                      ocrDone: row?.ocr.done ?? 0)) {
      await load()
    }
    .sheet(item: $sheetRow) { row in
      SummaryRunSheet(row: row, currentPage: page, missingCount: missingCount, defaultLanguage: library.summaryLanguage,
                      vendorDescription: library.summaryVendorDescription) { range, instruction, language in
        Task { await library.summarizePages(documentId: row.id, range: range, instruction: instruction, language: language) }
      }
    }
  }

  /// Reloads on page change, summary progress, Settings saves and OCR progress.
  private struct LoadKey: Equatable { let document: String; let page: Int; let revision: Int; let config: Int; let ocrDone: Int }

  private var header: some View {
    HStack(spacing: 8) {
      Text("Page \(page)").font(.headline)
      if let record, record.isStale {
        Label("Stale", systemImage: "clock.badge.exclamationmark").labelStyle(.iconOnly).foregroundStyle(.secondary)
          .help("The page was OCRed again after this summary; summarize it again to refresh it")
      }
      Spacer()
      if progress != nil { ProgressView().controlSize(.small) }
      Button { openSheet() } label: {
        Image(systemName: record == nil ? "text.badge.plus" : "arrow.clockwise")
      }
      .buttonStyle(.plain)
      .disabled(!library.summaryConfigured || row == nil)
      .help(record == nil ? "Summarize pages…" : "Summarize again, optionally with instructions…")
      .accessibilityLabel(record == nil ? "Summarize Pages" : "Summarize Again")
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
  }

  /// The document's coverage, the run in progress (with Cancel) and how
  /// the last run ended.
  @ViewBuilder private var runStatus: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let counts = row?.summaries { Text(coverageText(counts)).font(.caption).foregroundStyle(.secondary) }
      if let progress {
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text(progressTitle(progress)).font(.callout)
            Spacer()
            Button("Cancel") { library.cancelSummaries(documentId: reader.documentId) }
              .controlSize(.small)
              .help("Stop summarizing this PDF; finished pages keep their summaries")
          }
          if progress.total > 0 {
            ProgressView(value: Double(progress.completed), total: Double(progress.total))
          } else {
            ProgressView().progressViewStyle(.linear)
          }
          if queued > 0 {
            Text(queued == 1 ? "1 more run queued" : "\(queued) more runs queued").font(.caption).foregroundStyle(.secondary)
          }
        }
        .padding(8)
        .overlay(Rectangle().stroke(Flat.border, lineWidth: 1))
      } else if let report {
        Label("Last run \(RelativeAge.string(from: report.finishedAt)): \(report.text)",
              systemImage: report.isProblem ? "exclamationmark.triangle" : "checkmark.circle")
          .font(.caption)
          .foregroundStyle(report.isProblem ? Color.orange : Color.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func coverageText(_ counts: PageSummaryCounts) -> String {
    var parts = ["\(counts.done) of \(counts.total) pages summarized"]
    if counts.failed > 0 { parts.append("\(counts.failed) failed") }
    if counts.stale > 0 { parts.append("\(counts.stale) out of date") }
    if counts.notOCRed > 0 { parts.append("\(counts.notOCRed) not OCRed") }
    return "This PDF: " + parts.joined(separator: " · ")
  }

  private func progressTitle(_ progress: PageSummaryProgress) -> String {
    let count = progress.total > 0 ? " \(min(progress.completed + (progress.currentPage == nil ? 0 : 1), progress.total)) of \(progress.total)" : ""
    switch progress.phase {
    case .ocr: return "OCR before summarizing:" + count
    case .summary:
      if let page = progress.currentPage { return "Summarizing p. \(page):" + count }
      return progress.total > 0 ? "Summarizing:" + count : "Starting…"
    }
  }

  private var tagList: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Tags").font(.caption.bold()).foregroundStyle(.secondary)
      FlowLayout(spacing: 6) {
        ForEach(tags, id: \.self) { tag in
          Button { onTag(tag) } label: {
            Text(tag)
              .font(.caption)
              .lineLimit(1)
              .padding(.horizontal, 8)
              .padding(.vertical, 3)
              .overlay(Rectangle().stroke(Flat.border, lineWidth: 1))
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .help("Search every PDF for \"\(tag)\"")
        }
      }
    }
  }

  @ViewBuilder private var content: some View {
    if !library.summaryConfigured {
      VStack(alignment: .leading, spacing: 8) {
        Text("Page summaries are off.").font(.callout)
        Text("Choose a summary vendor and model under Page Summaries in Settings.")
          .font(.callout).foregroundStyle(.secondary)
        SettingsLink { Text("Open Settings…") }
      }
    } else if let record {
      summaryView(record)
    } else if !loaded {
      EmptyView()
    } else if ocrStatus != .done {
      VStack(alignment: .leading, spacing: 8) {
        Text("This page has no OCR text yet.").font(.callout).foregroundStyle(.secondary)
        if progress == nil {
          Button("OCR and Summarize This Page") { summarizeThisPage() }
            .help("Runs OCR on this page, then summarizes it")
        }
      }
    } else if progress != nil {
      Text("Waiting for the summary…").font(.callout).foregroundStyle(.secondary)
    } else {
      VStack(alignment: .leading, spacing: 8) {
        Text("No summary for this page yet.").font(.callout).foregroundStyle(.secondary)
        HStack {
          Button("Summarize This Page") { summarizeThisPage() }
          Button("Summarize Pages…") { openSheet() }
        }
      }
    }
  }

  @ViewBuilder private func summaryView(_ record: PageSummaryRecord) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      if record.status == .failed {
        Label("The last summary attempt failed: \(record.error ?? "unknown error")", systemImage: "exclamationmark.triangle")
          .font(.callout).foregroundStyle(.orange)
      }
      if let summary = record.summary {
        if summary.isEmpty {
          Text("This page has no text.").font(.callout).foregroundStyle(.secondary)
        } else {
          Text(summary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      if let instruction = record.instruction {
        Text("Instructions: \(instruction)").font(.caption).foregroundStyle(.secondary)
      }
      Text(details(record)).font(.caption2).foregroundStyle(.tertiary)
    }
  }

  private func details(_ record: PageSummaryRecord) -> String {
    let model = record.model.map { " \($0)" } ?? ""
    return "\(PageSummaryLanguage.displayName(record.language)) · \(SettingsViewModel.displayName(for: record.vendor))\(model) · "
      + RelativeAge.string(from: record.updatedAt)
  }

  private func summarizeThisPage() {
    let documentId = reader.documentId
    let page = page
    Task { await library.summarizePages(documentId: documentId, range: .pages(String(page))) }
  }

  private func openSheet() {
    guard library.summaryConfigured, let row else { return }
    Task {
      missingCount = await library.pagesNeedingSummary(documentId: row.id)
      sheetRow = row
    }
  }

  private func load() async {
    record = await library.pageSummary(documentId: reader.documentId, page: page)
    let info = await library.pageInfo(documentId: reader.documentId, page: page)
    ocrStatus = info?.ocrStatus
    tags = info?.ocrStatus == .done ? info?.ocrTags ?? [] : []
    loaded = true
  }
}
