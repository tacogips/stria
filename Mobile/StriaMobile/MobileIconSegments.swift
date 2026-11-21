import SwiftUI

/// One icon in a `MobileIconSegments` control; `label` is the VoiceOver name.
struct MobileIconSegment<Value: Equatable> {
  let value: Value
  let symbol: String
  let label: String
}

/// A capsule of icon buttons used instead of text segmented pickers.
/// `.prominent` is the ink capsule with a coral selection (agent tabs);
/// `.subtle` is a light capsule with a raised white selection (scopes).
struct MobileIconSegments<Value: Equatable>: View {
  enum Style { case prominent, subtle }

  @Binding var selection: Value
  let segments: [MobileIconSegment<Value>]
  var style: Style = .prominent

  private var prominent: Bool { style == .prominent }
  private var size: CGSize { prominent ? CGSize(width: 40, height: 30) : CGSize(width: 32, height: 26) }

  var body: some View {
    HStack(spacing: 2) {
      ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
        let selected = segment.value == selection
        Button { selection = segment.value } label: {
          Image(systemName: segment.symbol)
            .font(.system(size: prominent ? 14 : 12, weight: selected ? .semibold : .regular))
            .frame(width: size.width, height: size.height)
            .foregroundStyle(iconColor(selected))
            .background { if selected { selectionShape } }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(segment.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
      }
    }
    .padding(3)
    .background(prominent ? Flat.ink : Color.primary.opacity(0.07), in: Capsule())
    .fixedSize()
  }

  private func iconColor(_ selected: Bool) -> Color {
    if prominent { return selected ? .white : .white.opacity(0.8) }
    return selected ? Flat.ink : .secondary
  }

  @ViewBuilder private var selectionShape: some View {
    if prominent {
      Capsule().fill(Flat.coral)
    } else {
      Capsule().fill(Flat.panel).shadow(color: .black.opacity(0.12), radius: 2, y: 1)
    }
  }
}

/// A round, softly filled icon button (compose, close, retitle).
struct MobileToolbarIcon: View {
  let symbol: String
  let label: String
  var diameter: CGFloat = 32
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: diameter * 0.44, weight: .medium))
        .foregroundStyle(Color.primary)
        .frame(width: diameter, height: diameter)
        .background(Color.primary.opacity(0.07), in: Circle())
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
  }
}
