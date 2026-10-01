import Foundation
@testable import StriaCore
import Testing

struct PromptPartsTests {
  @Test func OCRPromptPutsTextBeforeImage() {
    let request = OCRRequest(
      docId: "d1", page: 1, pngPath: URL(fileURLWithPath: "/tmp/page.png"), prompt: "Read page",
      settings: .init(vendor: "anthropic", model: "m", apiKeyEnvironment: "KEY")
    )
    #expect(GatewayPromptParts.ocrParts(request) == [.text("Read page"), .image(request.pngPath)])
  }

  @Test func agentPromptOrdersHistoryPagesAndQuestion() {
    let page1 = ContextPage(docId: "d1", title: "One", page: 2, ocrText: "first text", pngPath: URL(fileURLWithPath: "/tmp/1.png"))
    let page2 = ContextPage(docId: "d2", title: "Two", page: 3, ocrText: nil, pngPath: URL(fileURLWithPath: "/tmp/2.png"))
    let request = AgentRequest(
      question: "What?", systemPrompt: "system", contextPages: [page1, page2],
      history: [.init(role: .user, content: "Prior Q"), .init(role: .assistant, content: "Prior A")],
      settings: .init(vendor: "anthropic", model: "m", apiKeyEnvironment: "KEY")
    )
    #expect(GatewayPromptParts.agentParts(request) == [
      .text("Previous conversation:\nUser: Prior Q\nAssistant: Prior A"),
      .text("Document \"One\" (d1) page 2\nfirst text"), .image(page1.pngPath),
      .text("Document \"Two\" (d2) page 3\nOCR text not available"), .image(page2.pngPath),
      .text("What?")
    ])
  }
}
