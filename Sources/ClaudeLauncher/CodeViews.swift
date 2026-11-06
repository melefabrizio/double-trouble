import LauncherCore
import SwiftUI

struct CodeRow: View {
    let env: CodeEnvironment

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: env.isMain ? "terminal.fill" : "terminal")
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(env.displayName).lineLimit(1)
                Group {
                    if let command = env.command {
                        Text(command).font(.caption.monospaced())
                    } else {
                        Text("Senza comando").font(.caption)
                    }
                }
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if !env.aliases.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .help("Un alias di shell usa questo profilo")
            }
        }
        .padding(.vertical, 3)
    }
}

struct CodeDetail: View {
    @Environment(CodeStore.self) private var store
    let env: CodeEnvironment

    @State private var draftName = ""
    @State private var confirmingDelete = false
    @State private var confirmingAliases = false
    @State private var confirmingAdopt = false
    @State private var copied = false

    private var isBusy: Bool { store.busy.contains(env.id) }
    private var trimmedName: String { draftName.trimmingCharacters(in: .whitespaces) }
    private var nameChanged: Bool { trimmedName != env.displayName && !trimmedName.isEmpty }

    var body: some View {
        Form {
            header
            if env.needsCommand {
                adoptSection
            } else {
                if !env.aliases.isEmpty { aliasSection }
                if !env.isMain { nameSection }
            }
            accountSection
            folderSection
            if !env.isMain {
                Section {
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Label(env.script == nil ? "Elimina profilo…" : "Elimina ambiente…", systemImage: "trash")
                    }
                    .disabled(isBusy)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(env.displayName)
        .onAppear { draftName = env.displayName }
        .task(id: env.configExists) { await store.measure(env) }
        .sheet(isPresented: $confirmingDelete) {
            DeleteSheet(
                title: env.script == nil ? String(localized: "Eliminare il profilo \"\(env.name)\"?")
                                         : String(localized: "Eliminare \"\(env.displayName)\"?"),
                launcherDescription: env.command.map { String(localized: "il comando \($0)") },
                profileName: env.name,
                profilePath: abbreviated(env.configDir.path),
                profileSize: store.sizes[env.id],
                account: accountText,
                canKeepProfile: env.script != nil,
                launcherIsCommand: true,
                allowProfile: env.configExists
            ) { includingProfile in
                Task { await store.delete(env, includingConfig: includingProfile) }
            }
        }
        .confirmationDialog("Creare il comando e disattivare l'alias?", isPresented: $confirmingAdopt,
                            titleVisibility: .visible) {
            Button("Crea comando e disattiva alias") { adopt() }
        } message: {
            Text(aliasDialogText)
        }
        .confirmationDialog("Disattivare l'alias?", isPresented: $confirmingAliases, titleVisibility: .visible) {
            Button("Disattiva alias") { Task { await store.disableAliases(env) } }
        } message: {
            Text(aliasDialogText)
        }
    }

    // MARK: Sections

    private var header: some View {
        Section {
            HStack(spacing: 18) {
                Image(systemName: env.isMain ? "terminal.fill" : "terminal")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(env.isMain ? Color.accentColor : .primary)
                    .frame(width: 84, height: 84)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 8) {
                    Text(env.displayName).font(.title.weight(.semibold))
                    if let command = env.command {
                        HStack(spacing: 8) {
                            Text(command)
                                .font(.system(.title3, design: .monospaced))
                                .textSelection(.enabled)
                            Button {
                                store.copyCommand(command)
                                copied = true
                                Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                            } label: {
                                Label(copied ? "Copiato" : "Copia", systemImage: copied ? "checkmark" : "doc.on.doc")
                                    .labelStyle(.iconOnly)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help(copied ? "Copiato" : "Copia comando")
                        }
                    } else {
                        Text("Senza comando")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if isBusy { ProgressView().controlSize(.small) }
            }
            .padding(.vertical, 6)
        }
    }

    private var aliasSection: some View {
        Section {
            ForEach(env.aliases, id: \.self) { alias in
                LabeledContent {
                    Text(alias.fileDescription).font(.caption.monospaced()).foregroundStyle(.secondary)
                } label: {
                    Label("alias \(alias.command)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            if !env.needsCommand {
                HStack {
                    Text("Nella shell l'alias prevale sul comando.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Disattiva alias…") { confirmingAliases = true }
                        .disabled(isBusy)
                }
            }
        } header: {
            Text("Alias")
        }
    }

    private var adoptSection: some View {
        Section {
            TextField("Nome", text: $draftName, prompt: Text("Lavoro"))

            LabeledContent("Comando") {
                Text(store.paths.command(for: env.name)).monospaced()
            }
            ForEach(env.aliases, id: \.self) { alias in
                LabeledContent("Sostituisce") {
                    Text("alias in \(alias.fileDescription)").monospaced().foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Configurazione")
        } footer: {
            HStack {
                Text("Il profilo resta dov'è, non serve rifare il login.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Crea comando") {
                    if env.aliases.isEmpty { adopt() } else { confirmingAdopt = true }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)
            }
        }
    }

    private var nameSection: some View {
        Section {
            TextField("Nome", text: $draftName)
                .onSubmit { if nameChanged { Task { await store.rename(env, to: trimmedName) } } }

        } header: {
            Text("Aspetto")
        } footer: {
            if nameChanged {
                HStack {
                    Text("Il comando resta \(env.command ?? "").")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Annulla") { draftName = env.displayName }
                    Button("Salva") { Task { await store.rename(env, to: trimmedName) } }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("s")
                }
            }
        }
    }

    private var accountSection: some View {
        Section("Account") {
            if let account = env.account {
                LabeledContent("Email") { Text(account.email).textSelection(.enabled) }
                if let org = account.organization, !org.isEmpty {
                    LabeledContent("Organizzazione") { Text(org) }
                }
            } else {
                LabeledContent("Stato") {
                    Text(env.command.map { "Non collegato. Avvia \($0) ed esegui /login." } ?? "Non collegato")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var folderSection: some View {
        Section("Profilo") {
            LabeledContent("Cartella") {
                HStack {
                    Text(abbreviated(env.configDir.path)).monospaced().lineLimit(1).truncationMode(.middle)
                    if env.configExists {
                        Button("Mostra") { NSWorkspace.shared.activateFileViewerSelecting([env.configDir]) }
                            .buttonStyle(.link)
                    }
                }
            }
            if let script = env.script {
                LabeledContent("Script") {
                    HStack {
                        Text(abbreviated(script.path)).monospaced().lineLimit(1).truncationMode(.middle)
                        Button("Mostra") { NSWorkspace.shared.activateFileViewerSelecting([script]) }
                            .buttonStyle(.link)
                    }
                }
            }
            LabeledContent("Spazio occupato") {
                if !env.configExists {
                    Text("Verrà creato al primo avvio").foregroundStyle(.secondary)
                } else if let size = store.sizes[env.id] {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    // MARK: Helpers

    private var accountText: String? {
        env.account.map { a in a.organization.map { "\(a.email) · \($0)" } ?? a.email }
    }

    private var aliasDialogText: String {
        let files = env.aliases.map(\.fileDescription).joined(separator: "\n")
        return String(localized: "La riga viene commentata e il file originale resta come backup.\n\(files)\n\nVale dal prossimo terminale aperto.")
    }

    private func abbreviated(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }

    private func adopt() {
        Task {
            await store.adopt(env, displayName: trimmedName.isEmpty ? env.displayName : trimmedName,
                              disableAliases: true)
        }
    }
}

struct NewCodeSheet: View {
    @Environment(CodeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var identifier = ""
    @State private var identifierEdited = false
    /// Profile to copy configuration from (env id); defaults to the main one.
    @State private var sourceID: String? = CodePaths.live.mainConfigDir.path
    @State private var working = false

    private var trimmedName: String { displayName.trimmingCharacters(in: .whitespaces) }
    private var problem: InstanceName.Problem? {
        CodeManager.validate(name: identifier, existingDirs: store.existingDirs, paths: store.paths)
    }
    private var canCreate: Bool { !trimmedName.isEmpty && problem == nil && !working }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Nome", text: $displayName, prompt: Text("Lavoro"))
                        .onChange(of: displayName) { _, new in
                            if !identifierEdited { identifier = InstanceName.slug(from: new) }
                        }
                    TextField("Identificativo", text: Binding(
                        get: { identifier }, set: { identifier = $0; identifierEdited = true }), prompt: Text("lavoro"))
                        .monospaced()
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(problem == nil || identifier.isEmpty ? Color.secondary : Color.red)
                }
                Section {
                    LabeledContent("Comando") {
                        Text(identifier.isEmpty ? "claude-…" : store.paths.command(for: identifier)).monospaced()
                    }
                    LabeledContent("Cartella") {
                        Text(identifier.isEmpty ? "~/.claude-…" : "~/.claude-\(identifier)").monospaced()
                    }
                }
                Section {
                    Picker("Copia la configurazione da", selection: $sourceID) {
                        Text("Nessuno").tag(String?.none)
                        Divider()
                        ForEach(store.environments.filter(\.configExists)) { env in
                            Text("\(env.displayName) (\(env.command ?? env.name))").tag(Optional(env.id))
                        }
                    }
                } footer: {
                    Text("settings.json, CLAUDE.md, agent, comandi e skill.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollBounceBehavior(.basedOnSize)

            Divider()
            HStack {
                if working { ProgressView().controlSize(.small) }
                Spacer()
                Button("Annulla", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Crea") {
                    working = true
                    Task {
                        let source = sourceID.flatMap { store.environment($0)?.configDir }
                        let ok = await store.create(name: identifier, displayName: trimmedName, copyConfigFrom: source)
                        working = false
                        if ok { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
            }
            .padding(16)
        }
        .frame(width: 480, height: 470)
    }

    private var hint: String {
        switch problem {
        case .none: String(localized: "Lettere minuscole, numeri e trattini. Non si può cambiare dopo.")
        case .empty: String(localized: "Serve un identificativo: lettere minuscole, numeri e trattini.")
        case .invalidCharacters: String(localized: "Usa solo lettere minuscole, numeri, - e _.")
        case .reserved: String(localized: "Questo nome è riservato.")
        case .taken: String(localized: "Esiste già una cartella o un comando con questo nome.")
        }
    }
}
