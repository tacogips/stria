import Foundation

/// Coarse "how long ago" text, computed once when a view renders (it never
/// ticks): "just now", "5 min ago", "3 hours ago", "2 days ago", then a date.
public enum RelativeAge {
  public static func string(from date: Date, now: Date = Date()) -> String {
    let seconds = max(0, now.timeIntervalSince(date))
    if seconds < 60 { return "just now" }
    let minutes = Int(seconds / 60)
    if minutes < 60 { return "\(minutes) min ago" }
    let hours = minutes / 60
    if hours < 24 { return hours == 1 ? "1 hour ago" : "\(hours) hours ago" }
    let days = hours / 24
    if days < 30 { return days == 1 ? "1 day ago" : "\(days) days ago" }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }
}
