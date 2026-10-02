import AppKit
import PDFKit
import SwiftUI
import StriaCore

struct PDFKitView: NSViewRepresentable {
  @Bindable var reader: ReaderViewModel

  func makeCoordinator() -> Coordinator { Coordinator(reader: reader) }

  func makeNSView(context: Context) -> PDFView {
    let pdfView = PDFView()
    pdfView.displayMode = .singlePageContinuous
    pdfView.displayDirection = .vertical
    pdfView.autoScales = true
    context.coordinator.observePageChanges(of: pdfView)
    pdfView.document = reader.pdfDocument
    navigate(pdfView, coordinator: context.coordinator)
    return pdfView
  }

  func updateNSView(_ pdfView: PDFView, context: Context) {
    pdfView.displayMode = .singlePageContinuous
    pdfView.displayDirection = .vertical
    pdfView.autoScales = true
    if pdfView.document !== reader.pdfDocument {
      pdfView.document = reader.pdfDocument
      context.coordinator.handledNavigationID = nil
    }
    navigate(pdfView, coordinator: context.coordinator)
  }

  static func dismantleNSView(_ pdfView: PDFView, coordinator: Coordinator) {
    coordinator.stopObserving()
  }

  /// Applies the view model's navigation request once per request id. The
  /// coordinator remembers the handled id, so no observable state is mutated
  /// during a SwiftUI update.
  private func navigate(_ pdfView: PDFView, coordinator: Coordinator) {
    guard let navigation = reader.navigation, navigation.id != coordinator.handledNavigationID,
          let document = pdfView.document,
          let page = document.page(at: navigation.page - 1) else { return }
    coordinator.handledNavigationID = navigation.id
    pdfView.go(to: page)
  }

  @MainActor
  final class Coordinator {
    private let reader: ReaderViewModel
    private var pageObserver: NSObjectProtocol?
    var handledNavigationID: UUID?

    init(reader: ReaderViewModel) { self.reader = reader }

    func observePageChanges(of pdfView: PDFView) {
      pageObserver = NotificationCenter.default.addObserver(
        forName: .PDFViewPageChanged,
        object: pdfView,
        queue: .main
      ) { [weak self, weak pdfView] _ in
        Task { @MainActor in
          guard let self, let pdfView,
                let document = pdfView.document,
                let page = pdfView.currentPage else { return }
          let index = document.index(for: page)
          if index != NSNotFound { self.reader.pageDidChange(to: index + 1) }
        }
      }
    }

    func stopObserving() {
      guard let pageObserver else { return }
      NotificationCenter.default.removeObserver(pageObserver)
      self.pageObserver = nil
    }
  }
}
