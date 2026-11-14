/// Platform policy, injectable so mobile behavior can be tested on the Mac.
public enum StriaPlatform: Equatable, Sendable {
  case macOS
  case iOS

  public static var current: StriaPlatform {
    #if os(macOS)
    .macOS
    #else
    .iOS
    #endif
  }
}
