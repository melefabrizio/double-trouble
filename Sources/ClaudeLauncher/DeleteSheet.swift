import SwiftUI

/// Deletion guard shared by Desktop and Code. By default only the launcher /
/// command goes; removing the profile (login, history, settings) needs an
/// explicit opt-in AND typing the profile name. Everything goes to the Trash.
struct DeleteSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    /// What "only the launcher" removes, e.g. "l'app Claude Work" / "il comando claude-work".
    let launcherDescription: String?
    let profileName: String
    let profilePath: String
    let profileSize: Int64?
    let account: String?
    /// false = there is nothing but the profile to delete (orphan profile).
    let canKeepProfile: Bool
    /// Desktop launchers are apps, Code launchers are commands.
    var launcherIsCommand = false
    /// false = the profile can never be deleted from here (Claude's own default / main profile).
    var allowProfile: Bool = true
    let onDelete: (_ includingProfile: Bool) -> Void

    @State private var includeProfile = false
    @State private var typed = ""
    @FocusState private var fieldFocused: Bool

    private var deletingProfile: Bool { includeProfile || !canKeepProfile }
    private var confirmed: Bool { !deletingProfile || typed == profileName }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: deletingProfile ? "exclamationmark.triangle.fill" : "trash")
                    .font(.system(size: 30))
                    .foregroundStyle(deletingProfile ? .red : .secondary)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    if let launcherDescription, !deletingProfile {
                        Text("Nel Cestino va solo \(launcherDescription). Il profilo resta.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if canKeepProfile && allowProfile {
                Toggle("Elimina anche il profilo", isOn: $includeProfile.animation(.snappy))
                    .toggleStyle(.checkbox)
            }

            if deletingProfile {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Login, cronologia e impostazioni di questo ambiente vanno nel Cestino. Finché non svuoti il Cestino puoi recuperarli a mano.")
                        .fixedSize(horizontal: false, vertical: true)
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                        GridRow {
                            Text("Cartella").foregroundStyle(.secondary)
                            Text(profilePath).textSelection(.enabled).truncationMode(.middle).lineLimit(1)
                        }
                        if let account {
                            GridRow { Text("Account").foregroundStyle(.secondary); Text(account) }
                        }
                        if let profileSize {
                            GridRow {
                                Text("Dimensione").foregroundStyle(.secondary)
                                Text(ByteCountFormatter.string(fromByteCount: profileSize, countStyle: .file))
                            }
                        }
                    }
                    .font(.callout)
                    Text("Per confermare, scrivi **\(profileName)**:")
                        .padding(.top, 4)
                    TextField("", text: $typed, prompt: Text(profileName))
                        .textFieldStyle(.roundedBorder)
                        .monospaced()
                        .autocorrectionDisabled()
                        .focused($fieldFocused)
                        .onSubmit { if confirmed { delete() } }
                }
                .padding(12)
                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.red.opacity(0.35)))
                .onAppear { fieldFocused = true }
            }

            HStack {
                Spacer()
                Button("Annulla", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                // Never the default (Return) action when the profile is involved.
                if deletingProfile {
                    Button(!canKeepProfile ? "Elimina profilo" : launcherIsCommand ? "Elimina comando e profilo" : "Elimina app e profilo",
                           role: .destructive, action: delete)
                        .tint(.red)
                        .buttonStyle(.borderedProminent)
                        .disabled(!confirmed)
                } else {
                    Button("Elimina", role: .destructive, action: delete)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
        .onChange(of: includeProfile) { typed = "" }
    }

    private func delete() {
        guard confirmed else { return }
        onDelete(deletingProfile)
        dismiss()
    }
}
