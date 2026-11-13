import LauncherCore
import SwiftUI

/// One selection for the whole sidebar: Desktop and Code items live side by side.
enum SidebarItem: Hashable {
    case desktop(String)
    case code(String)
}

struct ContentView: View {
    @Environment(Store.self) private var store
    @Environment(CodeStore.self) private var codeStore
    @State private var selection: SidebarItem?
    @AppStorage("desktopExpanded") private var desktopExpanded = true
    @AppStorage("codeExpanded") private var codeExpanded = true

    private var hasDesktop: Bool { store.claudeInstalled }
    private var hasCode: Bool { codeStore.isInstalled }

    var body: some View {
        @Bindable var store = store
        @Bindable var codeStore = codeStore
        NavigationSplitView {
            List(selection: $selection) {
                if hasDesktop {
                    Section("Claude Desktop", isExpanded: $desktopExpanded) {
                        ForEach(store.records) { record in
                            SidebarRow(record: record).tag(SidebarItem.desktop(record.name))
                        }
                    }
                }
                if hasCode {
                    Section("Claude Code", isExpanded: $codeExpanded) {
                        ForEach(codeStore.environments) { env in
                            CodeRow(env: env).tag(SidebarItem.code(env.id))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { addButton }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newEnvironment)) { note in
            if let kind = note.object as? EnvironmentKind { newEnvironment(kind: kind) }
        }
        // A store asks for an item to be selected (right after creating it).
        .onChange(of: store.selection) { _, name in
            if let name { selection = .desktop(name); store.selection = nil }
        }
        .onChange(of: codeStore.selection) { _, id in
            if let id { selection = .code(id); codeStore.selection = nil }
        }
        .onChange(of: store.records) { ensureValidSelection() }
        .onChange(of: codeStore.environments) { ensureValidSelection() }
        .onAppear(perform: ensureValidSelection)
        .sheet(isPresented: $store.showingNewSheet) {
            NewInstanceSheet(adopting: store.adoptingProfile)
        }
        .sheet(isPresented: $codeStore.showingNewSheet) {
            NewCodeSheet()
        }
        .alert(item: $store.error) { error in
            Alert(title: Text(error.title), message: Text(error.message))
        }
        .alert(item: $codeStore.error) { error in
            Alert(title: Text(error.title), message: Text(error.message))
        }
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        switch selection {
        case .desktop(let name):
            if let record = store.record(name) {
                InstanceDetail(record: record).id(record.name)
            }
        case .code(let id):
            if let env = codeStore.environment(id) {
                CodeDetail(env: env).id(env.id)
            }
        case nil:
            if !hasDesktop && !hasCode {
                ContentUnavailableView {
                    Label("Claude non è installato", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Installa Claude Desktop o Claude Code.")
                } actions: {
                    Link("Scarica Claude", destination: URL(string: "https://claude.ai/download")!)
                }
            } else {
                ContentUnavailableView {
                    Label("Nessun ambiente", systemImage: "square.stack.3d.up")
                } description: {
                    Text("Un ambiente è Claude con un account separato.")
                } actions: {
                    addButton.buttonStyle(.borderedProminent)
                }
            }
        }
    }

    // MARK: New environment

    private typealias Kind = EnvironmentKind

    @ViewBuilder private var addButton: some View {
        if hasDesktop && hasCode {
            Menu {
                Button("Ambiente Claude Desktop…") { newEnvironment(kind: .desktop) }
                Button("Ambiente Claude Code…") { newEnvironment(kind: .code) }
            } label: {
                Label("Nuovo ambiente", systemImage: "plus")
            }
            // No chevron: in the macOS 26 glass toolbar it reads as clutter, and both
            // commands are also in the File menu, so the menu stays discoverable.
            .menuIndicator(.hidden)
            .help("Nuovo ambiente")
        } else {
            Button { newEnvironment(kind: hasDesktop ? .desktop : .code) } label: {
                Label("Nuovo ambiente", systemImage: "plus")
            }
            .help("Nuovo ambiente (⌘N)")
            .disabled(!hasDesktop && !hasCode)
        }
    }

    private func newEnvironment(kind: Kind) {
        switch kind {
        case .desktop:
            guard hasDesktop else { return }
            store.adoptingProfile = nil
            store.showingNewSheet = true
        case .code:
            guard hasCode else { return }
            codeStore.showingNewSheet = true
        }
    }

    private func ensureValidSelection() {
        switch selection {
        case .desktop(let name) where store.record(name) != nil: return
        case .code(let id) where codeStore.environment(id) != nil: return
        default: break
        }
        if let first = store.records.first, hasDesktop {
            selection = .desktop(first.name)
        } else if let first = codeStore.environments.first, hasCode {
            selection = .code(first.id)
        } else {
            selection = nil
        }
    }
}

struct SidebarRow: View {
    @Environment(Store.self) private var store
    let record: InstanceRecord

    var body: some View {
        HStack(spacing: 10) {
            LauncherIcon(launcher: record.primary, size: 32)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(record.displayName)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if store.running[record.name] != nil {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                    .help("In esecuzione")
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Apri") { store.launch(record) }
            if let url = record.primary?.url {
                Button("Mostra nel Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        }
    }

    private var subtitle: String {
        if store.running[record.name] != nil { return String(localized: "In esecuzione") }
        if record.isOrphan { return String(localized: "Senza app") }
        if !record.isInstalled { return String(localized: "Non installato") }
        return record.name
    }
}
