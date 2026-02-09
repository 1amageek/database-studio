import SwiftUI

/// インデックス状態バッジ
public struct IndexStateBadge: View {
    let state: String

    public init(state: String) {
        self.state = state
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbolName)
            Text(displayName)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .foregroundStyle(foregroundColor)
        .cornerRadius(4)
    }

    private var displayName: String {
        switch state {
        case "readable": return "Ready"
        case "writeOnly": return "Building"
        case "disabled": return "Disabled"
        default: return state
        }
    }

    private var symbolName: String {
        switch state {
        case "readable": return "checkmark.circle.fill"
        case "writeOnly": return "clock.fill"
        case "disabled": return "xmark.circle.fill"
        default: return "questionmark.circle"
        }
    }

    private var backgroundColor: Color {
        switch state {
        case "readable": return .green.opacity(0.15)
        case "writeOnly": return .orange.opacity(0.15)
        case "disabled": return .red.opacity(0.15)
        default: return .gray.opacity(0.15)
        }
    }

    private var foregroundColor: Color {
        switch state {
        case "readable": return .green
        case "writeOnly": return .orange
        case "disabled": return .red
        default: return .gray
        }
    }
}

// MARK: - Previews

#Preview("Index State Badges") {
    HStack(spacing: 12) {
        IndexStateBadge(state: "readable")
        IndexStateBadge(state: "writeOnly")
        IndexStateBadge(state: "disabled")
    }
    .padding()
}
