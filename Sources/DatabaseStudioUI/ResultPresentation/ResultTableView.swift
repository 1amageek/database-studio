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
                if state.sortableColumns.contains(index) {
                    TableColumn(state.columns[index], sortUsing: ResultSortComparator(column: index)) { row in
                        cell(row, column: index)
                    }.width(min: 90, ideal: 160, max: 600)
                }
                if !state.sortableColumns.contains(index) {
                    TableColumn(state.columns[index]) { row in
                        cell(row, column: index)
                    }.width(min: 90, ideal: 160, max: 600)
                }
            }
        }
        .tableStyle(.inset)
        .accessibilityIdentifier("result.table")
        .help("Column headers sort loaded rows. SQL-specific structured and temporal columns use server ordering through Data Options.")
    }

    private func cell(_ row: ResultPageRow, column: Int) -> some View {
        Text(ResultValueFormat.text(row.values[column]))
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: ResultValueFormat.isNumeric(row.values[column]) ? .trailing : .leading)
            .lineLimit(1)
            .accessibilityIdentifier("result.cell.\(row.id).\(column)")
    }
}
