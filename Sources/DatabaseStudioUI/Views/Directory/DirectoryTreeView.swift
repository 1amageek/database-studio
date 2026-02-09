import SwiftUI
import Core

/// ディレクトリツリービュー（Entity + Indexes）
struct DirectoryTreeView: View {
    let viewModel: AppViewModel

    var body: some View {
        List(selection: Binding(
            get: { viewModel.selectedEntityName },
            set: { newValue in
                if let name = newValue {
                    viewModel.selectEntity(name)
                }
            }
        )) {
            if viewModel.isLoadingEntities {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if viewModel.entityTree.isEmpty {
                Text("エンティティがありません")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.entityTree) { node in
                    EntityTreeNodeView(node: node, viewModel: viewModel)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Browser")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await viewModel.refreshEntities()
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
    let viewModel: AppViewModel

    private var hasContent: Bool {
        !node.children.isEmpty || !node.entities.isEmpty
    }

    var body: some View {
        if hasContent {
            DisclosureGroup {
                // 子ディレクトリ
                ForEach(node.children) { child in
                    EntityTreeNodeView(node: child, viewModel: viewModel)
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
    @Previewable @State var viewModel = AppViewModel.preview(
        entityTree: PreviewData.entityTree,
        selectedEntityName: nil
    )
    DirectoryTreeView(viewModel: viewModel)
        .frame(width: 280, height: 400)
}

#Preview("Directory Tree - Empty") {
    @Previewable @State var viewModel = AppViewModel.preview(
        entityTree: []
    )
    DirectoryTreeView(viewModel: viewModel)
        .frame(width: 280, height: 400)
}
