import SwiftUI

enum GraphClusterPalette {
    static func color(_ cluster: Int) -> Color {
        let colors: [Color] = [.blue, .teal, .orange, .purple, .green, .pink, .indigo, .brown]
        return colors[cluster % colors.count]
    }
}
