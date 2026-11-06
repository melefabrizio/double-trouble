import LauncherCore
import SwiftUI

struct NewInstanceSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Set when creating a launcher for a profile that already exists.
    let adopting: String?

    @State private var displayName = ""
    @State private var identifier = ""
    @State private var identifierEdited = false
    @State private var tint = Preset.all[5].tint // blue: the most common "second account"
    @State private var badge: Badge?
    @State private var copyLogin = false
    @State private var working = false

    private var trimmedName: String { displayName.trimmingCharacters(in: .whitespaces) }
    private var effectiveID: String { adopting ?? identifier }

    private var idProblem: InstanceName.Problem? {
        adopting != nil ? nil : InstanceName.validate(identifier, existing: store.existingNames)
    }

    private var nameProblem: String? {
        guard !trimmedName.isEmpty else { return nil }
        if !LauncherBuilder.isValidDisplayName(trimmedName) { return String(localized: "Il nome non può contenere \"/\" o \":\".") }
        let bundle = "Claude \(trimmedName).app"
        if store.records.flatMap(\.launchers).contains(where: { $0.url.lastPathComponent == bundle })
            || FileManager.default.fileExists(atPath: store.paths.applications.appendingPathComponent(bundle).path) {
            return String(localized: "Esiste già un'app chiamata \"\(bundle)\".")
        }
        return nil
    }

    private var canCreate: Bool {
        !trimmedName.isEmpty && nameProblem == nil && idProblem == nil && !working
            && !(copyLogin && store.defaultClaudeRunning)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(nsImage: IconRenderer.shared.image(for: tint, badge: badge))
                                .resizable()
                                .frame(width: 96, height: 96)
                                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                            Text(trimmedName.isEmpty ? "Claude …" : "Claude \(trimmedName)")
                                .font(.headline)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    TextField("Nome", text: $displayName, prompt: Text("Lavoro"))
                        .onChange(of: displayName) { _, new in
                            if !identifierEdited && adopting == nil { identifier = InstanceName.slug(from: new) }
                        }
                    if let nameProblem {
                        Text(nameProblem).font(.caption).foregroundStyle(.red)
                    }
                    if let adopting {
                        LabeledContent("Profilo") { Text(adopting).monospaced() }
                    } else {
                        TextField("Identificativo", text: Binding(
                            get: { identifier },
                            set: { identifier = $0; identifierEdited = true }), prompt: Text("lavoro"))
                            .monospaced()
                        Text(idHint)
                            .font(.caption)
                            .foregroundStyle(idProblem == nil || identifier.isEmpty ? Color.secondary : Color.red)
                    }
                }

                Section("Colore") {
                    TintPicker(tint: $tint)
                }

                Section("Badge") {
                    BadgePicker(badge: $badge)
                    if badge != nil {
                        BadgeTextField(badge: $badge)
                        BadgeHint()
                    }
                }

                if adopting == nil {
                    Section {
                        Toggle(isOn: $copyLogin) {
                            Text("Copia il profilo di Claude")
                            Text("Copia login, impostazioni e server MCP, senza cache e VM.")
                        }
                        if copyLogin && store.defaultClaudeRunning {
                            Label("Esci da Claude (⌘Q) prima di creare l'ambiente.",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollBounceBehavior(.basedOnSize)

            Divider()
            HStack {
                if working {
                    ProgressView().controlSize(.small)
                    Text(copyLogin ? "Copia del profilo…" : "Creazione dell'app…")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Annulla", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(working)
                Button("Crea") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
            .padding(16)
        }
        .frame(width: 480, height: adopting == nil ? 720 : 600)
        .onAppear {
            if let adopting {
                displayName = adopting.prefix(1).uppercased() + adopting.dropFirst()
            }
        }
    }

    private var idHint: String {
        switch idProblem {
        case .none:
            let folder = identifier.isEmpty ? "…" : identifier
            return String(localized: "Nome della cartella del profilo: ~/.claude-instances/\(folder). Non si può cambiare dopo.")
        case .empty: return String(localized: "Serve un identificativo: lettere minuscole, numeri e trattini.")
        case .invalidCharacters: return String(localized: "Usa solo lettere minuscole, numeri, - e _.")
        case .reserved: return String(localized: "\"default\" è il profilo di Claude stesso: scegli un altro nome.")
        case .taken: return String(localized: "Esiste già un profilo con questo identificativo.")
        }
    }

    private func create() {
        working = true
        let spec = LauncherSpec(instance: effectiveID, displayName: trimmedName, tint: tint, badge: badge)
        Task {
            let ok = await store.create(spec, copyLogin: copyLogin && adopting == nil)
            working = false
            if ok { dismiss() }
        }
    }
}
