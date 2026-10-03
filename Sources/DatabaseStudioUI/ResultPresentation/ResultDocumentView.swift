import SwiftUI

/// Shows structured documents while sharing the table's original page identities.
struct ResultDocumentView: View {
    @Bindable var state: ResultPageState

    var body: some View {
        List(selection: $state.selectedIDs) {
            ForEach(state.orderedRows) { row in
                DisclosureGroup {
                    ForEach(state.columns.indices, id: \.self) { index in
                        ResultFieldView(name: state.columns[index], value: row.values[index])
                    }
                } label: {
                    Text("Row \(row.id + 1)")
                        .accessibilityIdentifier("result.document.\(row.id)")
                }.tag(row.id)
            }
        }.listStyle(.inset).accessibilityIdentifier("result.documents")
    }
}
