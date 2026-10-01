import Foundation
import AgentGateway

enum PromptPart: Equatable, Sendable {
  case text(String)
  case image(URL)
}

enum GatewayPromptParts {
  static func rendered(_ parts: [PromptPart], for vendor: GatewayVendor) -> [PromptPart] {
    guard vendor.isCLI else { return parts }
    return parts.map { part in
      switch part {
      case .text:
        return part
      case let .image(url):
        return .text("Page image file: \(url.path)\nOpen and read this PNG file with your file-reading tool before answering. Use what it shows as the page image this request refers to.")
      }
    }
  }

  static func ocrParts(_ request: OCRRequest) -> [PromptPart] {
    [.text(request.prompt), .image(request.pngPath)]
  }

  static func agentParts(_ request: AgentRequest) -> [PromptPart] {
    var parts = [PromptPart]()
    if !request.history.isEmpty {
      let turns = request.history.map { "\($0.role.rawValue.capitalized): \($0.content)" }.joined(separator: "\n")
      parts.append(.text("Previous conversation:\n" + turns))
    }
    for page in request.contextPages {
      let text = page.ocrText ?? "OCR text not available"
      parts.append(.text("Document \"\(page.title)\" (\(page.docId)) page \(page.page)\n" + text))
      parts.append(.image(page.pngPath))
    }
    parts.append(.text(request.question))
    return parts
  }
}
