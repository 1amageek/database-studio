import SwiftUI
import DatabaseKit

/// Lazily reveals canonical object/array structure without a JSON round trip.
struct ResultFieldView: View {
    let name: String
    let value: FieldValue

    var body: some View {
        switch value {
        case .object(let object):
            DisclosureGroup(name) {
                ForEach(object.fields, id: \.key) { field in
                    ResultFieldView(name: field.key, value: field.value)
                }
            }
        case .array(let values):
            DisclosureGroup("\(name) · \(values.count) elements") {
                ForEach(values.indices, id: \.self) { index in
                    ResultFieldView(name: "[\(index)]", value: values[index])
                }
            }
        default:
            LabeledContent(name) { Text(ResultValueFormat.text(value)).textSelection(.enabled) }
        }
    }
}
