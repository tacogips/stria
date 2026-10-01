import Foundation

enum GatewayOCRReplyCheck {
  static let emptyReason = "OCR reply was empty; the page image may not have reached the model"
  static let noImageReason = "OCR reply says no page image was received; the agent did not read the page image"

  private static let englishPhrases = [
    "don't see an image", "don't see any image", "do not see an image", "do not see any image",
    "no image attached", "no image was attached", "no image has been attached", "image wasn't attached",
    "image was not attached", "no image was provided", "no image provided", "no image was received",
    "didn't receive an image", "did not receive an image", "haven't received an image",
    "have not received an image", "can't see the image", "cannot see the image", "unable to see the image"
  ]

  private static let japanesePhrases = [
    "画像が添付されていません", "画像が添付されていない", "画像が見当たりません", "画像が見当たらない",
    "画像が届いていません", "画像を受け取っていません", "画像が確認できません"
  ]

  static func rejectionReason(for reply: String) -> String? {
    let cleaned = OCRTextPostProcessor.clean(reply)
    guard !cleaned.isEmpty else { return emptyReason }

    let normalized = cleaned.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
    guard normalized.count <= 600 else { return nil }
    return (englishPhrases + japanesePhrases).contains(where: normalized.contains) ? noImageReason : nil
  }
}
