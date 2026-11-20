import SwiftUI

/// One segment: an SF Symbol and the description shown on hover.
struct IconSegment<Value: Hashable> {
  let value: Value
  let symbol: String
  let help: String
}

/// Metrics for regular and compact icon segments.
enum IconSegmentedControlSize {
  case regular, compact

  var segmentWidth: CGFloat { self == .regular ? 30 : 24 }
  var segmentHeight: CGFloat { self == .regular ? 22 : 18 }
  var symbolFont: Font? { self == .regular ? nil : .system(size: 11) }
}

/// A flat segmented control of icons. Each segment is its own button, so it
/// gets its own tooltip (SwiftUI's segmented Picker cannot show one per
/// segment), and the selected segment is a solid accent square.
struct IconSegmentedControl<Value: Hashable>: View {
  @Binding var selection: Value
  let segments: [IconSegment<Value>]
  var size: IconSegmentedControlSize = .regular

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
        let selected = segment.value == selection
        Button { selection = segment.value } label: {
          Image(systemName: segment.symbol)
            .font(size.symbolFont)
            .frame(width: size.segmentWidth, height: size.segmentHeight)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? Flat.userBubble : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(segment.help)
        .accessibilityLabel(segment.help)
        .accessibilityAddTraits(selected ? .isSelected : [])
        if index < segments.count - 1 {
          Rectangle().fill(Flat.border).frame(width: 1, height: size.segmentHeight)
        }
      }
    }
    .overlay(Rectangle().stroke(Flat.border, lineWidth: 1))
    .fixedSize()
  }
}
