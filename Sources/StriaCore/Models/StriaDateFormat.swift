import Foundation

public enum StriaDateFormat {
  private static let style = Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false).timeSeparator(.colon).timeZone(separator: .colon)
  public static func string(from date: Date) -> String { style.format(date) }
  public static func date(from string: String) -> Date? { try? style.parse(string) }
}
