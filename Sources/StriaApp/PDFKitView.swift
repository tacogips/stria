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
    context.coordinator.pdfView = pdfView
    context.coordinator.applyPendingRequests()
    return pdfView
  }

  func updateNSView(_ pdfView: PDFView, context: Context) {
    if pdfView.document !== reader.pdfDocument {
      pdfView.document = reader.pdfDocument
      context.coordinator.handledNavigationID = nil
    }
    context.coordinator.applyPendingRequests()
  }

  static func dismantleNSView(_ pdfView: PDFView, coordinator: Coordinator) {
    coordinator.stopObserving()
  }

  /// Applies navigation and zoom requests once per request id. Requests are
  /// held until the view is in a window with a layout, because `go(to:)` on
  /// an unlaid-out `PDFView` with `autoScales` is reset by the first layout
  /// pass, which would silently lose the last-read page restore.
  @MainActor
  final class Coordinator {
    private let reader: ReaderViewModel
    private var pageObserver: NSObjectProtocol?
    weak var pdfView: PDFView?
    var handledNavigationID: UUID?
    private var handledZoomID: UUID?
    private var retryScheduled = false

    init(reader: ReaderViewModel) { self.reader = reader }

    func applyPendingRequests() {
      let navigation = reader.navigation.flatMap { $0.id == handledNavigationID ? nil : $0 }
      let zoom = reader.zoom.flatMap { $0.id == handledZoomID ? nil : $0 }
      guard navigation != nil || zoom != nil else { return }
      guard let pdfView, pdfView.window != nil, pdfView.bounds.width > 0 else {
        scheduleRetry()
        return
      }
      if let navigation, let document = pdfView.document, let page = document.page(at: navigation.page - 1) {
        handledNavigationID = navigation.id
        pdfView.go(to: page)
      }
      if let zoom {
        handledZoomID = zoom.id
        switch zoom.kind {
        case .zoomIn: pdfView.zoomIn(nil)
        case .zoomOut: pdfView.zoomOut(nil)
        case .actualSize:
          pdfView.autoScales = false
          pdfView.scaleFactor = 1
        case .fitWidth:
          pdfView.autoScales = true
        }
      }
    }

    private func scheduleRetry() {
      guard !retryScheduled else { return }
      retryScheduled = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
        self?.retryScheduled = false
        self?.applyPendingRequests()
      }
    }

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
