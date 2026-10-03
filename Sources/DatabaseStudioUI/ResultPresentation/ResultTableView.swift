import SwiftUI

/// Uses native row selection, scrolling, column sizing and header ordering.
struct ResultTableView: View {
    @Bindable var state: ResultPageState

    var body: some View {
        Table(state.orderedRows, selection: $state.selectedIDs, sortOrder: $state.sortOrder) {
            TableColumn("Row", sortUsing: ResultSortComparator(column: -1)) { row in
                Text("\(row.id + 1)").monospacedDigit()
            }.width(min: 45, ideal: 60, max: 85)
            TableColumnForEach(state.columns.indices.filter { state.visibleColumns.contains($0) }, id: \.self) { index in
                TableColumn(state.columns[index], sortUsing: ResultSortComparator(column: index)) { row in
                    Text(ResultValueFormat.text(row.values[index]))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: ResultValueFormat.isNumeric(row.values[index]) ? .trailing : .leading)
                        .lineLimit(1)
                        .accessibilityIdentifier("result.cell.\(row.id).\(index)")
                }.width(min: 90, ideal: 160, max: 600)
            }
        }
        .tableStyle(.inset)
        .accessibilityIdentifier("result.table")
        .help("Column headers sort loaded rows. Use Data Options to order the server query.")
    }
}
