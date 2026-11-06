import LauncherCore
import SwiftUI

struct InstanceDetail: View {
    @Environment(Store.self) private var store
    let record: InstanceRecord

    @State private var draftName = ""
    /// nil until the user touches the color (old launchers don't record their tint).
    @State private var draftTint: Tint?
    /// Only meaningful when `badgeEdited`: nil is a valid choice ("no badge").
    @State private var draftBadge: Badge?
    @State private var badgeEdited = false
    @State private var confirmingDelete = false
    @State private var confirmingQuit = false

    private var running: RunningState? { store.running[record.name] }
    private var isBusy: Bool { store.busy.contains(record.name) }

    private var trimmedName: String { draftName.trimmingCharacters(in: .whitespaces) }
    private var nameChanged: Bool { trimmedName != record.displayName }
    private var tintChanged: Bool { draftTint != nil && draftTint != store.currentTint(record) }
    private var currentBadge: Badge? { record.primary?.badge }
    private var badgeChanged: Bool { badgeEdited && draftBadge != currentBadge }
    private var isDirty: Bool { nameChanged || tintChanged || badgeChanged }
    private var badgeBinding: Binding<Badge?> {
        Binding(get: { badgeEdited ? draftBadge : currentBadge },
                set: { draftBadge = $0; badgeEdited = true })
    }
    private var canSave: Bool { isDirty && LauncherBuilder.isValidDisplayName(trimmedName) && !isBusy }

    var body: some View {
        Form {
            header
            if record.isOrphan {
                orphanSection
            } else {
                appearanceSection
                installSection
            }
            profileSection
            Section {
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label(record.isOrphan ? "Elimina profilo…" : "Elimina ambiente…", systemImage: "trash")
                }
                .disabled(running != nil || isBusy || (record.isOrphan && record.isDefault))
            } footer: {
                if running != nil {
                    Text("Esci da Claude prima di eliminare l'ambiente.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(record.displayName)
        .onAppear(perform: resetDraft)
        .task(id: record.profileExists) { await store.measure(record) }
        .sheet(isPresented: $confirmingDelete) {
            DeleteSheet(
                title: deleteTitle,
                launcherDescription: record.isOrphan ? nil : String(localized: "l'app \"Claude \(record.displayName)\""),
                profileName: record.name,
                profilePath: abbreviated(record.profileURL.path),
                profileSize: store.sizes[record.name],
                account: nil,
                // The default profile belongs to Claude itself: only its launcher can go.
                canKeepProfile: !record.isOrphan,
                allowProfile: !record.isDefault && record.profileExists
            ) { includingProfile in
                Task { await store.delete(record, includingProfile: includingProfile) }
            }
        }
        .confirmationDialog("Uscire forzatamente da \(record.displayName)?", isPresented: $confirmingQuit,
                            titleVisibility: .visible) {
            Button("Uscita forzata", role: .destructive) { Task { await store.forceQuit(record) } }
        } message: {
            Text("Il processo viene terminato e le risposte in corso si perdono. Per uscire normalmente usa ⌘Q in Claude.")
        }
    }

    // MARK: - Header

    private var header: some View {
        Section {
            HStack(alignment: .center, spacing: 20) {
                VStack(spacing: 6) {
                    Group {
                        if tintChanged || badgeChanged {
                            Image(nsImage: IconRenderer.shared.image(for: draftTint ?? store.currentTint(record),
                                                                     badge: badgeBinding.wrappedValue))
                                .resizable()
                                .frame(width: 112, height: 112)
                        } else {
                            LauncherIcon(launcher: record.primary, size: 112)
                        }
                    }
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                    .draggableApp(isDirty ? nil : record.primary?.url)
                    .help(record.isOrphan ? "" : "Trascina nel Dock o nella cartella Applicazioni")

                    if !record.isOrphan {
                        Text(isDirty ? "Salva per aggiornare l'icona" : "Trascina nel Dock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(record.isOrphan ? record.name : "Claude \(record.displayName)")
                        .font(.title.weight(.semibold))
                        .lineLimit(1)
                    statusLabel
                    HStack {
                        Button {
                            store.launch(record)
                        } label: {
                            Text("Apri")
                                .frame(minWidth: 60)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        if running != nil {
                            Button("Uscita forzata…") { confirmingQuit = true }
                                .controlSize(.large)
                        }
                        if isBusy { ProgressView().controlSize(.small).padding(.leading, 4) }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder private var statusLabel: some View {
        if let running {
            Label("In esecuzione", systemImage: "circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        } else {
            Label("Non in esecuzione", systemImage: "circle")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        Section {
            TextField("Nome", text: $draftName, prompt: Text("Lavoro"))
                .onSubmit { if canSave { save() } }

            LabeledContent("Colore") {
                TintPicker(tint: Binding(
                    get: { draftTint ?? store.currentTint(record) },
                    set: { draftTint = $0 }))
            }

            LabeledContent("Badge") {
                BadgePicker(badge: badgeBinding)
            }
            if badgeBinding.wrappedValue != nil {
                BadgeTextField(badge: badgeBinding)
            }
        } header: {
            Text("Aspetto")
        } footer: {
            HStack {
                if nameChanged {
                    Text("L'app verrà rinominata in \"Claude \(trimmedName).app\".")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isDirty {
                    Button("Annulla", action: resetDraft)
                    Button("Salva modifiche", action: save)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSave)
                        .keyboardShortcut("s")
                }
            }
        }
    }

    private var installSection: some View {
        Section("Installazione") {
            if let primary = record.primary {
                LabeledContent("Posizione") {
                    HStack {
                        Text(locationText(primary.location))
                        Button("Mostra") { NSWorkspace.shared.activateFileViewerSelecting([primary.url]) }
                            .buttonStyle(.link)
                    }
                }
            }
            if !record.isInstalled {
                LabeledContent {
                    Button("Installa in Applicazioni") { Task { await store.install(record) } }
                        .disabled(isBusy || isDirty)
                } label: {
                    Text("Applicazioni")
                    Text("Oppure trascina l'icona.")
                }
            }
        }
    }

    private var orphanSection: some View {
        Section {
            LabeledContent {
                Button("Crea app…") {
                    store.adoptingProfile = record.name
                    store.showingNewSheet = true
                }
            } label: {
                Text("Nessuna app")
                Text("Il profilo contiene ancora account e chat.")
            }
        }
    }

    private var profileSection: some View {
        Section("Profilo") {
            LabeledContent("Identificativo") {
                Text(record.name).monospaced().textSelection(.enabled)
            }
            LabeledContent("Cartella") {
                HStack {
                    Text(abbreviated(record.profileURL.path))
                        .truncationMode(.middle)
                        .lineLimit(1)
                        .textSelection(.enabled)
                    if record.profileExists {
                        Button("Mostra") { NSWorkspace.shared.activateFileViewerSelecting([record.profileURL]) }
                            .buttonStyle(.link)
                    }
                }
            }
            LabeledContent("Spazio occupato") {
                HStack {
                    if !record.profileExists {
                        Text("Verrà creato al primo avvio").foregroundStyle(.secondary)
                    } else if let size = store.sizes[record.name] {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    if record.profileExists {
                        Menu("Libera spazio") {
                            Button("Svuota la cache") {
                                Task { await store.freeSpace(record, folders: ProfileTools.cacheFolders) }
                            }
                            Button("Rimuovi la macchina virtuale di Cowork (vm_bundles)") {
                                Task { await store.freeSpace(record, folders: [ProfileTools.vmBundles]) }
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .disabled(running != nil || isBusy)
                        .help(running != nil ? "Esci da Claude per liberare spazio" :
                              "Cache e macchina virtuale si riscaricano da sole quando servono")
                    }
                }
            }
        }
    }

    // MARK: - Delete

    private var deleteTitle: String {
        record.isOrphan ? String(localized: "Eliminare il profilo \"\(record.name)\"?")
                        : String(localized: "Eliminare \"Claude \(record.displayName)\"?")
    }

    // MARK: - Helpers

    private func resetDraft() {
        draftName = record.displayName
        draftTint = nil
        draftBadge = nil
        badgeEdited = false
    }

    private func save() {
        let spec = LauncherSpec(instance: record.name, displayName: trimmedName,
                                tint: draftTint ?? store.currentTint(record),
                                badge: badgeBinding.wrappedValue)
        Task {
            await store.apply(spec, to: record)
            // The view is re-identified by name, so it keeps its state: re-sync the draft.
            if let updated = store.record(record.name) {
                draftName = updated.displayName
            }
            draftTint = nil
            draftBadge = nil
            badgeEdited = false
        }
    }

    private func locationText(_ location: LauncherLocation) -> String {
        switch location {
        case .applications: String(localized: "Applicazioni")
        case .userApplications: String(localized: "~/Applicazioni")
        case .staging: String(localized: "Non installato")
        }
    }

    private func abbreviated(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
