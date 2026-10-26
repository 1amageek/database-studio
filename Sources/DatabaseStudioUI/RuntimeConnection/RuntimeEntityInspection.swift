import SwiftUI
import DatabaseWire

/// Sections describing one storage entity exactly as schema.describe returned it.
struct RuntimeEntityInspection: View {
    let entity: SchemaDescribeOperation.Entity

    var body: some View {
        Section(entity.name) {
            ForEach(entity.fields, id: \.number) { field in
                DisclosureGroup(field.name) {
                    LabeledContent("Field number", value: String(field.number))
                    LabeledContent("Type", value: String(describing: field.type))
                    LabeledContent("Nullable", value: field.nullable ? "Yes" : "No")
                    if let reference = field.reference {
                        LabeledContent("Target entity", value: reference.targetEntity)
                        LabeledContent("Cardinality", value: String(describing: reference.cardinality))
                        LabeledContent("Delete rule", value: String(describing: reference.deleteRule))
                    }
                }
            }
        }
        Section("Indexes") {
            if entity.indexes.isEmpty {
                Text("No indexes declared.").foregroundStyle(.secondary)
            }
            ForEach(entity.indexes, id: \.name) { index in
                DisclosureGroup(index.name) {
                    LabeledContent("Type", value: String(describing: index.type))
                    ForEach(Array(index.fields.enumerated()), id: \.offset) { position, number in
                        LabeledContent("Field \(position + 1)", value:
                            entity.fields.first(where: { $0.number == number }).map { "#\(number) · \($0.name)" }
                                ?? "#\(number) · unresolved")
                    }
                    Text(String(reflecting: index.options))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        Section("Schema availability") {
            Text("This server response does not include identifier types, Directory/Partition definitions, or complete field constraints. Storage entity names are not SQL table names; browse data from Tables.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
