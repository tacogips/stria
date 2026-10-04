import SwiftUI
import StriaCore

/// The agent pane's Summary tab: the current page's summary, the run in
/// progress, and a button that summarizes again with instructions.
struct PageSummaryPane: View {
  @Bindable var library: LibraryViewModel
  let reader: ReaderViewModel
  var configRevision = 0
  @State private var record: PageSummaryRecord?
  @State private var ocrStatus: OCRStatus?
  @State private var missingCount = 0
  @State private var loaded = false
  @State private var sheetRow: LibraryRow?

  private var page: Int { reader.currentPage }
  private var row: LibraryRow? { library.rows.first { $0.id == reader.documentId } }
  private var progress: PageSummaryProgress? { library.summaryProgress[reader.documentId] }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      ScrollView {
        content
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
      if let progress {
        ProgressView().controlSize(.small)
        Text(progressText(progress)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
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
      Text("This page is not OCRed yet. Run OCR first; its summary follows when \"Summarize each page after OCR\" is on.")
        .font(.callout).foregroundStyle(.secondary)
    } else if progress != nil {
      Text("Waiting for the summary…").font(.callout).foregroundStyle(.secondary)
    } else {
      VStack(alignment: .leading, spacing: 8) {
        Text("No summary for this page yet.").font(.callout).foregroundStyle(.secondary)
        Button("Summarize Pages…") { openSheet() }
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

  private func progressText(_ progress: PageSummaryProgress) -> String {
    guard let current = progress.currentPage else { return "Summarizing…" }
    return "p. \(current) (\(progress.completed + 1)/\(progress.total))"
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
    ocrStatus = await library.pageOCRStatus(documentId: reader.documentId, page: page)
    loaded = true
  }
}
