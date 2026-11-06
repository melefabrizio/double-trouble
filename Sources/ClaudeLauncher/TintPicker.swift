import LauncherCore
import SwiftUI

/// Color presets plus fine-tuning sliders for the launcher icon.
struct TintPicker: View {
    @Binding var tint: Tint

    /// Claude's stock orange, used to draw the swatches.
    private static let baseHue = 15.0 / 360.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(Preset.all) { preset in
                    Button {
                        withAnimation(.snappy) { tint = preset.tint }
                    } label: {
                        Circle()
                            .fill(swatch(preset.tint))
                            .frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(.black.opacity(0.12)))
                            .padding(3)
                            .overlay {
                                if preset.tint == tint {
                                    Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(Text(LocalizedStringKey(preset.name)))
                    .accessibilityLabel(Text(LocalizedStringKey(preset.name)))
                    .accessibilityAddTraits(preset.tint == tint ? .isSelected : [])
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Tonalità").foregroundStyle(.secondary)
                    Slider(value: degrees, in: -180...180)
                    Text("\(Int(degrees.wrappedValue.rounded()))°")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                }
                GridRow {
                    Text("Saturazione").foregroundStyle(.secondary)
                    Slider(value: $tint.satGain, in: 0...2)
                    Text("\(Int((tint.satGain * 100).rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                }
            }
            .font(.callout)
            .controlSize(.small)
        }
    }

    /// Hue in -180…180° so the slider is centered on the stock color.
    private var degrees: Binding<Double> {
        Binding {
            var d = tint.degrees.truncatingRemainder(dividingBy: 360)
            if d > 180 { d -= 360 }
            if d < -180 { d += 360 }
            return d
        } set: {
            tint.degrees = $0
        }
    }

    private func swatch(_ tint: Tint) -> Color {
        var hue = Self.baseHue + Double(tint.hueShift) / 256
        hue -= hue.rounded(.down)
        return Color(hue: hue, saturation: min(1, 0.68 * tint.satGain), brightness: 0.86)
    }
}
