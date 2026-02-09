import Foundation

/// バイト配列を16進数形式でフォーマット
public struct HexFormatter {

    /// 標準的なhexdump形式でフォーマット
    public static func format(_ bytes: [UInt8], bytesPerLine: Int = 16) -> String {
        guard !bytes.isEmpty else { return "(empty)" }

        var lines: [String] = []
        var offset = 0

        while offset < bytes.count {
            let lineBytes = Array(bytes[offset..<min(offset + bytesPerLine, bytes.count)])
            let line = formatLine(lineBytes, offset: offset, bytesPerLine: bytesPerLine)
            lines.append(line)
            offset += bytesPerLine
        }

        return lines.joined(separator: "\n")
    }

    /// コンパクトな16進数形式でフォーマット（スペース区切り）
    public static func formatCompact(_ bytes: [UInt8], maxBytes: Int? = nil) -> String {
        guard !bytes.isEmpty else { return "(empty)" }

        let displayBytes: [UInt8]
        let truncated: Bool
        if let max = maxBytes, bytes.count > max {
            displayBytes = Array(bytes.prefix(max))
            truncated = true
        } else {
            displayBytes = bytes
            truncated = false
        }

        let hex = displayBytes.map { String(format: "%02x", $0) }.joined(separator: " ")
        return truncated ? "\(hex) ... (\(bytes.count) bytes total)" : hex
    }

    /// 単純な16進数文字列（スペースなし）
    public static func formatRaw(_ bytes: [UInt8]) -> String {
        guard !bytes.isEmpty else { return "" }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Private Helpers

    private static func formatLine(_ bytes: [UInt8], offset: Int, bytesPerLine: Int) -> String {
        let offsetStr = String(format: "%08x", offset)

        var hexParts: [String] = []
        for i in 0..<bytesPerLine {
            if i < bytes.count {
                hexParts.append(String(format: "%02x", bytes[i]))
            } else {
                hexParts.append("  ")
            }
        }

        let firstHalf = hexParts[0..<min(8, hexParts.count)].joined(separator: " ")
        let secondHalf = hexParts.count > 8
            ? hexParts[8..<hexParts.count].joined(separator: " ")
            : ""
        let hexStr = secondHalf.isEmpty ? firstHalf : "\(firstHalf)  \(secondHalf)"

        var asciiStr = ""
        for byte in bytes {
            if byte >= 0x20 && byte < 0x7F {
                asciiStr.append(Character(UnicodeScalar(byte)))
            } else {
                asciiStr.append(".")
            }
        }
        asciiStr = asciiStr.padding(toLength: bytesPerLine, withPad: " ", startingAt: 0)

        return "\(offsetStr)  \(hexStr)  |\(asciiStr)|"
    }
}

extension HexFormatter {
    /// バイト数を人間が読みやすい形式に変換
    public static func formatByteCount(_ count: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(count))
    }
}
