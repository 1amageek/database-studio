import SwiftUI

/// Version History のメインビュー
struct VersionView: View {
    @State private var state: VersionViewState
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var showInspector = false

    init(document: VersionDocument) {
        _state = State(initialValue: VersionViewState(document: document))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            VersionTimelineView(state: state)
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 350)
        } detail: {
            detailContent
                .inspector(isPresented: $showInspector) {
                    inspectorContent
                        .inspectorColumnWidth(min: 250, ideal: 280, max: 350)
                }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarItems
            }
        }
        .onChange(of: state.selectedVersionID) { _, newValue in
            if newValue != nil {
                showInspector = true
            }
        }
        .onChange(of: VersionWindowState.shared.document?.versions.count) { _, _ in
            if let newDoc = VersionWindowState.shared.document {
                state.updateDocument(newDoc)
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        if let diff = state.currentDiff, let version = state.selectedVersion {
            VersionDiffView(
                diff: diff,
                displayMode: state.diffDisplayMode,
                oldVersion: state.comparisonVersion,
                newVersion: version
            )
        } else {
            ContentUnavailableView(
                "Select a Version",
                systemImage: "clock",
                description: Text("Choose a version from the timeline to view changes")
            )
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspectorContent: some View {
        if let version = state.selectedVersion {
            VersionInspectorView(
                version: version,
                diff: state.currentDiff
            )
        } else {
            ContentUnavailableView(
                "No Version Selected",
                systemImage: "clock.arrow.circlepath",
                description: Text("Select a version to see its details")
            )
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbarItems: some View {
        Text("\(state.document.versions.count) versions")
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()

        Picker("Display", selection: $state.diffDisplayMode) {
            ForEach(DiffDisplayMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 300)

        Button {
            Task {
                if let refresh = VersionWindowState.shared.refreshAction,
                   let newDoc = await refresh() {
                    state.updateDocument(newDoc)
                }
            }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .help("Refresh")
        .keyboardShortcut("r", modifiers: .command)

        // Inspector Toggle
        Button {
            showInspector.toggle()
        } label: {
            Image(systemName: "sidebar.trailing")
        }
        .help("Inspector")
        .keyboardShortcut("i", modifiers: [.option, .command])
    }
}

// MARK: - Preview

#Preview("Version History") {
    VersionView(document: VersionPreviewData.document)
        .frame(width: 1000, height: 700)
}
