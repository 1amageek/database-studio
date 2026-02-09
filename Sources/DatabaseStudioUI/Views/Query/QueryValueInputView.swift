import SwiftUI

/// Input view for query values, adapts to field type
struct QueryValueInputView: View {
    @Binding var value: QueryValue
    let field: DiscoveredField?

    var body: some View {
        Group {
            switch field?.inferredType {
            case .boolean:
                Picker("", selection: Binding(
                    get: {
                        if case .boolean(let b) = value { return b }
                        return false
                    },
                    set: { value = .boolean($0) }
                )) {
                    Text("true").tag(true)
                    Text("false").tag(false)
                }
                .frame(width: 100)

            case .number:
                TextField("Value", text: Binding(
                    get: {
                        if case .number(let n) = value {
                            if n.truncatingRemainder(dividingBy: 1) == 0 {
                                return String(format: "%.0f", n)
                            }
                            return String(n)
                        }
                        if case .string(let s) = value { return s }
                        return ""
                    },
                    set: { newValue in
                        if let num = Double(newValue) {
                            value = .number(num)
                        } else {
                            value = .string(newValue)
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)

            default:
                // String input
                TextField("Value", text: Binding(
                    get: {
                        if case .string(let s) = value { return s }
                        return value.rawString
                    },
                    set: { value = .string($0) }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 150)
            }
        }
    }
}

// MARK: - Previews

#Preview("Value Input - String") {
    @Previewable @State var value: QueryValue = .string("test")
    QueryValueInputView(
        value: $value,
        field: DiscoveredField(path: "name", name: "name", inferredType: .string, sampleValues: [], depth: 0)
    )
    .padding()
}

#Preview("Value Input - Number") {
    @Previewable @State var value: QueryValue = .number(25)
    QueryValueInputView(
        value: $value,
        field: DiscoveredField(path: "age", name: "age", inferredType: .number, sampleValues: [], depth: 0)
    )
    .padding()
}

#Preview("Value Input - Boolean") {
    @Previewable @State var value: QueryValue = .boolean(true)
    QueryValueInputView(
        value: $value,
        field: DiscoveredField(path: "isActive", name: "isActive", inferredType: .boolean, sampleValues: [], depth: 0)
    )
    .padding()
}
