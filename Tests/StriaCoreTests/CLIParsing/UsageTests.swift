import StriaCore
import Testing

@Suite struct UsageTests {
  @Test func pageTopicListsBothCommands() {
    let text = Usage.text(for: "page")
    #expect(text.contains("page image"))
    #expect(text.contains("page text"))
  }

  @Test func configTopicListsGetAndSet() {
    let text = Usage.text(for: "config")
    #expect(text.contains("config get"))
    #expect(text.contains("config set"))
  }

  @Test func unknownTopicReturnsGeneralUsage() {
    #expect(Usage.text(for: "nope") == Usage.general)
  }

  @Test func generalUsageListsShortHelpOption() {
    #expect(Usage.general.contains("-h"))
  }
}
