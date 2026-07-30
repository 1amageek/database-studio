import SwiftUI
import Core

/// ディレクトリツリービュー（Entity + Indexes）
struct DirectoryTreeView: View {
    let studioState: DatabaseStudioState

    var body: some View {
        List(selection: Binding(
            get: { studioState.selectedEntityName },
            set: { newValue in
                if let name = newValue {
                    studioState.selectEntity(name)
                }
            }
        )) {
            if studioState.isLoadingEntities {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if studioState.entityTree.isEmpty {
                Text("エンティティがありません")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(studioState.entityTree) { node in
                    EntityTreeNodeView(node: node, studioState: studioState)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Browser")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await studioState.refreshEntities()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("更新")
            }
        }
    }
}

/// エンティティツリーノードビュー
struct EntityTreeNodeView: View {
    let node: EntityTreeNode
    let studioState: DatabaseStudioState

    private var hasContent: Bool {
        !node.children.isEmpty || !node.entities.isEmpty
    }

    var body: some View {
        if hasContent {
            DisclosureGroup {
                // 子ディレクトリ
                ForEach(node.children) { child in
                    EntityTreeNodeView(node: child, studioState: studioState)
                }
                // エンティティ
                ForEach(node.entities, id: \.name) { entity in
                    EntityRowView(entity: entity)
                        .tag(entity.name)
                }
            } label: {
                Label(node.name, systemImage: "folder.fill")
            }
        } else {
            Label(node.name, systemImage: "folder")
        }
    }
}

/// エンティティ行ビュー
struct EntityRowView: View {
    let entity: Schema.Entity

    var body: some View {
        HStack {
            Label(entity.name, systemImage: "cube.box.fill")
            Spacer()
            Text("\(entity.fields.count) fields")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Previews

#Preview("Directory Tree") {
    @Previewable @State var studioState = DatabaseStudioState.sample(
        entityTree: StudioSampleData.entityTree,
        selectedEntityName: nil
    )
    DirectoryTreeView(studioState: studioState)
        .frame(width: 280, height: 400)
}

#Preview("Directory Tree - Empty") {
    @Previewable @State var studioState = DatabaseStudioState.sample(
        entityTree: []
    )
    DirectoryTreeView(studioState: studioState)
        .frame(width: 280, height: 400)
}
