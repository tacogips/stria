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
  @Environment(\.horizontalSizeClass) private var sizeClass
  @State private var contents = false
  @State private var goToPage = false
  @State private var ocr = false

  var body: some View {
    HStack(spacing: 0) {
      VStack(spacing: 0) {
        MobilePDFView(reader: reader)
        Divider()
        Button("\(reader.currentPage) / \(reader.pageCount)") { goToPage = true }
          .monospacedDigit().padding(10).accessibilityLabel("Go to page, \(reader.currentPage) of \(reader.pageCount)")
      }
      if sizeClass == .regular, model.showingAgent {
        Divider()
        MobileAgentView(model: model, reader: reader, agent: agent)
          .frame(width: 340)
      }
    }
    .background(Flat.panel)
    .navigationTitle(reader.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button { contents = true } label: { Image(systemName: "list.bullet") }.accessibilityLabel("Contents")
        Button { ocr = true } label: { Image(systemName: "text.viewfinder") }.accessibilityLabel("Run OCR")
        Button { model.showingAgent.toggle() } label: { Image(systemName: "bubble.left.and.bubble.right") }.accessibilityLabel("Show or hide agent")
      }
    }
    .sheet(isPresented: $contents) { MobileContentsView(reader: reader) }
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
    .sheet(isPresented: Binding(get: { sizeClass != .regular && model.showingAgent }, set: { model.showingAgent = $0 })) {
      NavigationStack {
        MobileAgentView(model: model, reader: reader, agent: agent)
          .navigationTitle("Agent").navigationBarTitleDisplayMode(.inline)
          .toolbar { Button("Done") { model.showingAgent = false } }
      }
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
    }
    .onDisappear { agent.cancelDictation() }
    .onChange(of: reader.currentPage) { _, _ in agent.scheduleHistoryReload() }
  }
}

struct MobileContentsView: View {
  let reader: ReaderViewModel
  @Environment(\.dismiss) private var dismiss
  @State private var thumbnails = false

  var body: some View {
    NavigationStack {
      VStack {
        Picker("Contents", selection: $thumbnails) {
          Text("Outline").tag(false)
          Text("Pages").tag(true)
        }.pickerStyle(.segmented).padding(.horizontal)
        if thumbnails {
          ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) {
              ForEach(1...max(reader.pageCount, 1), id: \.self) { page in
                Button { navigate(page) } label: {
                  VStack {
                    if let image = reader.pdfDocument?.page(at: page - 1)?.thumbnail(of: CGSize(width: 100, height: 140), for: .cropBox) {
                      Image(uiImage: image).resizable().scaledToFit().frame(height: 140)
                    }
                    Text("Page \(page)")
                  }
                }
                .accessibilityLabel("Open page \(page)")
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
      .navigationTitle("Contents")
      .toolbar { Button("Done") { dismiss() } }
    }
  }

  private func navigate(_ page: Int) { reader.goToPage(page); dismiss() }
}
