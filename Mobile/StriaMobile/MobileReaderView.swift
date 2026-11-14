import PDFKit
import SwiftUI
import StriaCore

/// PDFKit owns scrolling; the core reader owns navigation and reading position.
struct MobilePDFView: UIViewRepresentable {
  let reader: ReaderViewModel

  func makeCoordinator() -> Coordinator { Coordinator(reader: reader) }

  func makeUIView(context: Context) -> PDFView {
    let view = PDFView()
    view.autoScales = true
    view.displayMode = .singlePageContinuous
    view.displayDirection = .vertical
    view.backgroundColor = .secondarySystemBackground
    context.coordinator.observe(view)
    return view
  }

  func updateUIView(_ view: PDFView, context: Context) {
    if view.document !== reader.pdfDocument {
      view.document = reader.pdfDocument
      view.autoScales = true
    }
    if let navigation = reader.navigation, context.coordinator.navigationID != navigation.id,
       let page = view.document?.page(at: navigation.page - 1) {
      context.coordinator.navigationID = navigation.id
      view.go(to: page)
    }
  }

  static func dismantleUIView(_ view: PDFView, coordinator: Coordinator) { coordinator.stop() }

  @MainActor
  final class Coordinator: NSObject {
    let reader: ReaderViewModel
    var navigationID: UUID?
    private weak var view: PDFView?

    init(reader: ReaderViewModel) { self.reader = reader }

    func observe(_ view: PDFView) {
      self.view = view
      NotificationCenter.default.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: view)
    }

    @objc private func pageChanged() {
      guard let view, let page = view.currentPage, let document = view.document else { return }
      reader.pageDidChange(to: document.index(for: page) + 1)
    }

    func stop() { NotificationCenter.default.removeObserver(self, name: .PDFViewPageChanged, object: view) }
  }
}

struct MobileReaderView: View {
  @Bindable var model: MobileModel
  @Bindable var reader: ReaderViewModel
  let agent: AgentPaneViewModel
  @State private var availableWidth: CGFloat = 0
  @State private var contentsVisible = true
  @State private var contentsSheet = false
  @State private var goToPage = false
  @State private var ocr = false

  var body: some View {
    GeometryReader { geometry in
      HStack(spacing: 0) {
        if showsContentsInline {
          MobileContentsPane(reader: reader, dismissOnSelection: false)
            .frame(width: 240)
          Divider()
        }
        VStack(spacing: 0) {
          VStack(spacing: 0) {
            MobilePDFView(reader: reader)
            Divider()
            Button("\(reader.currentPage) / \(reader.pageCount)") { goToPage = true }
              .monospacedDigit().padding(10).accessibilityLabel("Go to page, \(reader.currentPage) of \(reader.pageCount)")
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          if showsAgentBelow {
            Divider()
            VStack(spacing: 0) {
              HStack {
                Text("Agent").font(.headline)
                Text("Page \(reader.currentPage) of \(reader.pageCount)")
                  .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Button("Done") { model.showingAgent = false }
              }.padding(.horizontal, 12).padding(.vertical, 8)
              MobileAgentView(model: model, reader: reader, agent: agent, compact: true)
            }
            .frame(height: geometry.size.height / 2)
          }
        }
        if showsAgentInline {
          Divider()
          MobileAgentView(model: model, reader: reader, agent: agent)
            .frame(width: min(520, max(420, availableWidth * 0.42)))
        }
      }
      .onAppear { availableWidth = geometry.size.width }
      .onChange(of: geometry.size.width) { _, width in availableWidth = width }
    }
    .background(Flat.panel)
    .navigationTitle(reader.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button {
          if isPad && availableWidth >= 760 { contentsVisible.toggle() } else { contentsSheet = true }
        } label: { Image(systemName: "list.bullet") }.accessibilityLabel("Contents")
        Button { ocr = true } label: { Image(systemName: "text.viewfinder") }.accessibilityLabel("Run OCR")
        Button { model.showingAgent.toggle() } label: { Image(systemName: "bubble.left.and.bubble.right") }.accessibilityLabel("Show or hide agent")
      }
    }
    .sheet(isPresented: $contentsSheet) { MobileContentsView(reader: reader) }
    .sheet(isPresented: $goToPage) {
      NavigationStack {
        Form {
          TextField("Page number", text: $reader.pageFieldText).keyboardType(.numberPad)
          Button("Go to Page") { reader.commitPageField(); goToPage = false }
        }
        .navigationTitle("Go to Page")
        .toolbar { Button("Cancel") { goToPage = false } }
      }
      .presentationDetents([.medium])
    }
    .sheet(isPresented: $ocr) {
      if let row = model.library.rows.first(where: { $0.id == reader.documentId }) {
        MobileRunSheet(row: row, currentPage: reader.currentPage, settings: model.settings, library: model.library, summary: false)
      }
    }
    .onDisappear { agent.cancelDictation() }
    .onChange(of: reader.currentPage) { _, _ in agent.scheduleHistoryReload() }
  }

  private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
  private var showsContentsInline: Bool { isPad && availableWidth >= 760 && contentsVisible }
  private var showsAgentBelow: Bool { model.showingAgent && !showsAgentInline }
  private var showsAgentInline: Bool { isPad && availableWidth >= 1000 && model.showingAgent }
}

struct MobileContentsView: View {
  let reader: ReaderViewModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      MobileContentsPane(reader: reader, dismissOnSelection: true)
      .navigationTitle("Contents")
      .toolbar { Button("Done") { dismiss() } }
    }
  }
}

struct MobileContentsPane: View {
  let reader: ReaderViewModel
  let dismissOnSelection: Bool
  @Environment(\.dismiss) private var dismiss
  @State private var thumbnails = false

  var body: some View {
    VStack {
      Picker("Contents", selection: $thumbnails) {
        Text("Outline").tag(false)
        Text("Pages").tag(true)
      }.pickerStyle(.segmented).padding(.horizontal)
      if thumbnails {
        ScrollView {
          LazyVStack {
            ForEach(1...max(reader.pageCount, 1), id: \.self) { page in
              MobilePageThumbnail(reader: reader, page: page) { navigate(page) }
            }
          }.padding()
        }
      } else if reader.outlineRows.isEmpty {
        ContentUnavailableView("No Outline", systemImage: "list.bullet", description: Text("Use Pages to browse thumbnails."))
      } else {
        List {
          OutlineGroup(reader.outlineRows, children: \.optionalChildren) { row in
            Button { if let page = row.page { navigate(page) } } label: {
              HStack { Text(row.title); Spacer(); if let page = row.page { Text("\(page)").foregroundStyle(.secondary) } }
            }.disabled(row.page == nil)
          }
        }.listStyle(.plain)
      }
    }
    .background(Flat.panel)
  }

  private func navigate(_ page: Int) {
    reader.goToPage(page)
    if dismissOnSelection { dismiss() }
  }
}

private struct MobilePageThumbnail: View {
  let reader: ReaderViewModel
  let page: Int
  let navigate: () -> Void
  @State private var image: CGImage?

  var body: some View {
    Button(action: navigate) {
      VStack {
        if let image {
          Image(decorative: image, scale: 1).resizable().scaledToFit().frame(height: 140)
        } else {
          Image(systemName: "doc.richtext").frame(height: 140)
        }
        Text("Page \(page)")
      }
    }
    .accessibilityLabel("Open page \(page)")
    .task(id: page) { image = try? await reader.thumbnail(page: page) }
    .onDisappear { image = nil }
  }
}
