import DatabaseKit
import SwiftUI

/// Inspects the canonical JSONB tree without decoding or numeric coercion.
struct ResultJSONBFieldView: View {
    let name: String
    let value: QueryJSONBNode

    var body: some View {
        switch value {
        case .array(let values):
            DisclosureGroup("\(name) · \(values.count) elements") {
                ForEach(values.indices, id: \.self) { index in
                    ResultJSONBFieldView(name: "[\(index)]", value: values[index])
                }
            }
        case .object(let fields):
            DisclosureGroup(name) {
                ForEach(fields.indices, id: \.self) { index in
                    ResultJSONBFieldView(name: fields[index].key, value: fields[index].value)
                }
            }
        default:
            LabeledContent(name) { Text(ResultValueFormat.jsonb(value)).textSelection(.enabled) }
        }
    }
}
