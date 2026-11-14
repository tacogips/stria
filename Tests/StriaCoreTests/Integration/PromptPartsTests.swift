import Foundation
import AgentGateway
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
      .text("<page docId=\"d1\" page=\"2\" title=\"One\">\nfirst text\n</page>"), .image(page1.pngPath),
      .text("<page docId=\"d2\" page=\"3\" title=\"Two\">\nOCR text not available\n</page>"), .image(page2.pngPath),
      .text("What?")
    ])
  }

  @Test func cliVendorsRenderOCRImageAsPathTextAtTheSameIndex() {
    let request = OCRRequest(
      docId: "d1", page: 1, pngPath: URL(fileURLWithPath: "/tmp/page.png"), prompt: "Read page",
      settings: .init(vendor: "claude-code", model: nil, apiKeyEnvironment: nil)
    )
    let parts = GatewayPromptParts.ocrParts(request)
    let imageText = "Page image file: /tmp/page.png\nOpen and read this PNG file with your file-reading tool before answering. Use what it shows as the page image this request refers to."

    for vendor in [GatewayVendor.claudeCode, .codex, .cursor] {
      let rendered = GatewayPromptParts.rendered(parts, for: vendor)
      #expect(rendered.count == parts.count)
      #expect(!rendered.contains { if case .image = $0 { true } else { false } })
      #expect(rendered[0] == .text("Read page"))
      #expect(rendered[1] == .text(imageText))
    }
  }

  @Test func cliVendorsKeepAskImagePathsAtTheirOriginalIndices() {
    let page1 = ContextPage(docId: "d1", title: "One", page: 2, ocrText: "first text", pngPath: URL(fileURLWithPath: "/tmp/1.png"))
    let page2 = ContextPage(docId: "d2", title: "Two", page: 3, ocrText: nil, pngPath: URL(fileURLWithPath: "/tmp/2.png"))
    let request = AgentRequest(
      question: "What?", systemPrompt: "system", contextPages: [page1, page2],
      history: [.init(role: .user, content: "Prior Q"), .init(role: .assistant, content: "Prior A")],
      settings: .init(vendor: "claude-code", model: nil, apiKeyEnvironment: nil)
    )
    let parts = GatewayPromptParts.agentParts(request)

    for vendor in [GatewayVendor.claudeCode, .codex, .cursor] {
      let rendered = GatewayPromptParts.rendered(parts, for: vendor)
      #expect(rendered.count == parts.count)
      #expect(!rendered.contains { if case .image = $0 { true } else { false } })
      #expect(rendered[0] == parts[0])
      #expect(rendered[1] == parts[1])
      #expect(rendered[2] == .text("Page image file: /tmp/1.png\nOpen and read this PNG file with your file-reading tool before answering. Use what it shows as the page image this request refers to."))
      #expect(rendered[3] == parts[3])
      #expect(rendered[4] == .text("Page image file: /tmp/2.png\nOpen and read this PNG file with your file-reading tool before answering. Use what it shows as the page image this request refers to."))
      #expect(rendered[5] == parts[5])
    }
  }

  @Test func apiVendorsKeepOCRAndAskPartsUnchanged() {
    let ocrRequest = OCRRequest(
      docId: "d1", page: 1, pngPath: URL(fileURLWithPath: "/tmp/page.png"), prompt: "Read page",
      settings: .init(vendor: "openai", model: "m", apiKeyEnvironment: "KEY")
    )
    let contextPage = ContextPage(docId: "d1", title: "One", page: 2, ocrText: "first text", pngPath: URL(fileURLWithPath: "/tmp/1.png"))
    let agentRequest = AgentRequest(
      question: "What?", systemPrompt: "system", contextPages: [contextPage], history: [],
      settings: .init(vendor: "openai", model: "m", apiKeyEnvironment: "KEY")
    )
    let ocrParts = GatewayPromptParts.ocrParts(ocrRequest)
    let agentParts = GatewayPromptParts.agentParts(agentRequest)

    for vendor in [GatewayVendor.openAI, .anthropic, .gemini, .openRouter, .cursorAPI] {
      #expect(GatewayPromptParts.rendered(ocrParts, for: vendor) == ocrParts)
      #expect(GatewayPromptParts.rendered(agentParts, for: vendor) == agentParts)
    }
  }
}
