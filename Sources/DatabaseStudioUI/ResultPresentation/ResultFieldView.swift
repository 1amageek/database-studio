import SwiftUI
import DatabaseKit

/// Lazily reveals canonical object/array structure without a JSON round trip.
struct ResultFieldView: View {
    let name: String
    let value: DatabaseKit.QueryValue
    @State private var isExpanded = false

    var body: some View {
        switch value {
        case .primitive(.object(let object)):
            DisclosureGroup(name) {
                ForEach(object.fields, id: \.key) { field in
                    ResultFieldView(name: field.key, value: .primitive(field.value))
                }
            }
        case .primitive(.array(let values)):
            DisclosureGroup("\(name) · \(values.count) elements") {
                ForEach(values.indices, id: \.self) { index in
                    ResultFieldView(name: "[\(index)]", value: .primitive(values[index]))
                }
            }
        case .array(let value):
            DisclosureGroup("\(name) · " + ResultValueFormat.text(.array(value))) {
                ForEach(value.elements.indices, id: \.self) { index in
                    ResultFieldView(name: "Element \(index + 1)", value: value.elements[index])
                }
            }
        case .composite(let value):
            DisclosureGroup(name) {
                ForEach(value.fields.indices, id: \.self) { index in
                    ResultFieldView(name: value.type.columns[index].name, value: value.fields[index])
                }
            }
        case .json(let value):
            DisclosureGroup(name + " · JSON", isExpanded: $isExpanded) {
                if isExpanded {
                    // Original lexical bytes materialize only at the expanded text boundary.
                    Text(value.bytes.withUnsafeBytes { String(decoding: $0, as: UTF8.self) })
                        .textSelection(.enabled)
                }
            }
        case .jsonb(let value):
            ResultJSONBFieldView(name: name, value: value.root)
        default:
            LabeledContent(name) { Text(ResultValueFormat.text(value)).textSelection(.enabled) }
        }
    }
}
