import Foundation
@testable import StriaCore
import Testing

struct OCRReplyCheckTests {
  @Test func rejectsEmptyRepliesAfterCleaning() {
    #expect(GatewayOCRReplyCheck.rejectionReason(for: "") == GatewayOCRReplyCheck.emptyReason)
    #expect(GatewayOCRReplyCheck.rejectionReason(for: "  \n\t ") == GatewayOCRReplyCheck.emptyReason)
    #expect(GatewayOCRReplyCheck.rejectionReason(for: "```\n```") == GatewayOCRReplyCheck.emptyReason)
  }

  @Test func rejectsEnglishAndJapaneseNoImageReplies() {
    #expect(
      GatewayOCRReplyCheck.rejectionReason(
        for: "I don\u{2019}t see an image attached to your message, so there's nothing for me to transcribe."
      ) == GatewayOCRReplyCheck.noImageReason
    )
    #expect(GatewayOCRReplyCheck.rejectionReason(for: "I DO NOT SEE ANY IMAGE in your message.") == GatewayOCRReplyCheck.noImageReason)
    #expect(GatewayOCRReplyCheck.rejectionReason(for: "画像が添付されていません。もう一度送ってください。") == GatewayOCRReplyCheck.noImageReason)
    #expect(GatewayOCRReplyCheck.rejectionReason(for: "画像が見当たりません") == GatewayOCRReplyCheck.noImageReason)
  }

  @Test func acceptsPageTextAndLongRepliesContainingThePhrase() {
    #expect(GatewayOCRReplyCheck.rejectionReason(for: "Chapter 1\nIntroduction\n第1章 はじめに") == nil)
    let longReply = "no image attached" + String(repeating: "page text ", count: 80)
    #expect(longReply.count > 600)
    #expect(GatewayOCRReplyCheck.rejectionReason(for: longReply) == nil)
  }

  @Test func rejectedReplyIsRecordedAsFailedByCoordinator() async throws {
    try await withTestDataRoot { paths in
      let fake = FakeOCRService()
      let (library, source) = try await makeImportFixture(paths: paths, pageTexts: ["a"], ocr: fake)
      let imported = try await importFixture(library, source: source)
      let reason = try #require(GatewayOCRReplyCheck.rejectionReason(for: "I don't see an image attached."))
      await fake.setDefault(.failure(.failed(reason)))

      let summary = try await library.runOCR(documentId: imported.document.id, selection: .pending)
      let page = try #require(try await library.store.pageInfo(documentId: imported.document.id, page: 1))
      let runs = try await library.store.agentRuns(documentId: imported.document.id)

      #expect(summary.failed == 1)
      #expect(summary.done == 0)
      #expect(page.ocrStatus == .failed)
      #expect(page.ocrError == reason)
      #expect(runs.count == 1)
      #expect(runs.first?.status == .failed)
    }
  }
}
