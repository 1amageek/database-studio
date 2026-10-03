import SwiftUI
import DatabaseKit
import DatabaseWire

/// Stages source filtering, ordering and paging until an explicit Apply.
struct RuntimeDataOptions: View {
    @Environment(\.dismiss) private var dismiss
    let fields: [String]
    @State private var sortField: String
    @State private var descending: Bool
    @State private var pageLimit: Int
    @State private var filter: RuntimeRecordFilter
    let apply: (String, Bool, Int, RuntimeRecordFilter) -> Void

    init(fields: [String], sortField: String, descending: Bool, pageLimit: Int, filter: RuntimeRecordFilter,
         apply: @escaping (String, Bool, Int, RuntimeRecordFilter) -> Void) {
        self.fields = fields; self.apply = apply
        _sortField = State(initialValue: sortField)
        _descending = State(initialValue: descending)
        _pageLimit = State(initialValue: pageLimit)
        _filter = State(initialValue: filter)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server Ordering") {
                    Picker("Sort", selection: $sortField) {
                        Text("Server order").tag("")
                        ForEach(fields, id: \.self) { Text($0).tag($0) }
                    }
                    Toggle("Descending", isOn: $descending).disabled(sortField.isEmpty)
                }
                Section("Page") {
                    TextField("Page size", value: $pageLimit, format: .number)
                        .accessibilityIdentifier("runtime.data.pageLimit")
                    Text("Between 1 and \(ExecutionBudget().maximumRows) rows. Display modes use the returned page.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Server Filter") {
                    Picker("Field", selection: $filter.field) {
                        Text("No filter").tag("")
                        ForEach(fields, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Comparison", selection: $filter.comparison) {
                        ForEach(RuntimeRecordFilter.comparisons, id: \.self) { Text($0.displayName).tag($0) }
                    }.disabled(filter.field.isEmpty)
                    if filter.comparison.requiresValue {
                        Picker("Value type", selection: $filter.valueType) {
                            ForEach(RuntimeRecordFilter.ValueType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        TextField("Value", text: $filter.text)
                    }
                }
            }.formStyle(.grouped)
            .navigationTitle("Data Options")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.contentShape(Rectangle()) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { apply(sortField, descending, pageLimit, filter) }
                        .contentShape(Rectangle()).disabled(pageLimit < 1 || pageLimit > Int(ExecutionBudget().maximumRows))
                }
            }
        }.frame(width: 480, height: 440)
    }
}
