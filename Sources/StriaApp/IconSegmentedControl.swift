import SwiftUI

/// One segment: an SF Symbol and the description shown on hover.
struct IconSegment<Value: Hashable> {
  let value: Value
  let symbol: String
  let help: String
}

/// A flat segmented control of icons. Each segment is its own button, so it
/// gets its own tooltip (SwiftUI's segmented Picker cannot show one per
/// segment), and the selected segment is a solid accent square.
struct IconSegmentedControl<Value: Hashable>: View {
  @Binding var selection: Value
  let segments: [IconSegment<Value>]

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
        let selected = segment.value == selection
        Button { selection = segment.value } label: {
          Image(systemName: segment.symbol)
            .frame(width: 30, height: 22)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? Flat.userBubble : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(segment.help)
        .accessibilityLabel(segment.help)
        .accessibilityAddTraits(selected ? .isSelected : [])
        if index < segments.count - 1 {
          Rectangle().fill(Flat.border).frame(width: 1, height: 22)
        }
      }
    }
    .overlay(Rectangle().stroke(Flat.border, lineWidth: 1))
    .fixedSize()
  }
}
