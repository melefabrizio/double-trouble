import LauncherCore
import SwiftUI

/// "None" plus the badge palette. The text is edited separately by `BadgeTextField`.
struct BadgePicker: View {
    @Binding var badge: Badge?

    var body: some View {
        HStack(spacing: 8) {
            swatch(selected: badge == nil, help: Text("Nessuno")) {
                Circle()
                    .strokeBorder(.secondary.opacity(0.6), lineWidth: 1.5)
                    .overlay(Rectangle().fill(.secondary.opacity(0.8)).frame(width: 1.5).rotationEffect(.degrees(45)))
                    .clipShape(Circle())
            } action: {
                badge = nil
            }
            ForEach(BadgeColor.allCases) { color in
                swatch(selected: badge?.color == color, help: Text(color.name)) {
                    Circle()
                        .fill(Color(.sRGB, red: color.rgb.0, green: color.rgb.1, blue: color.rgb.2))
                        .overlay(Circle().strokeBorder(.black.opacity(0.12)))
                } action: {
                    badge = Badge(color: color, text: badge?.text ?? "")
                }
            }
        }
    }

    private func swatch(selected: Bool, help: Text, @ViewBuilder content: () -> some View,
                        action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            content()
                .frame(width: 22, height: 22)
                .padding(3)
                .overlay {
                    if selected { Circle().strokeBorder(Color.accentColor, lineWidth: 2) }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Up to three characters, uppercased as you type.
struct BadgeTextField: View {
    @Binding var badge: Badge?
    @State private var text = ""

    var body: some View {
        TextField("Testo del badge", text: $text, prompt: Text("Facoltativo"))
            .onAppear { text = badge?.text ?? "" }
            .onChange(of: badge?.text ?? "") { _, new in if new != text { text = new } }
            .onChange(of: text) { _, new in
                let normalized = Badge.normalize(new)
                if normalized != new { text = normalized }
                if badge?.text != normalized { badge?.text = normalized }
            }
    }
}

struct BadgeHint: View {
    var body: some View {
        Text("Fino a 3 lettere o numeri. Nelle icone piccole resta solo il pallino.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
