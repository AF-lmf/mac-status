import Foundation

// MARK: - Compact Byte Formatting — menu bar optimized

private let byteUnits = ["B", "K", "M", "G", "T"]

private func compactBytes(_ bytes: Double) -> String {
    var value = bytes
    var unitIndex = 0
    while value >= 1000 && unitIndex < byteUnits.count - 1 {
        value /= 1000
        unitIndex += 1
    }
    if unitIndex == 0 {
        return "\(Int(value))\(byteUnits[unitIndex])"
    }
    return String(format: "%.1f", value) + byteUnits[unitIndex]
}

func formatNetworkCompact(download: Double, upload: Double) -> String {
    "↓\(compactBytes(download)) ↑\(compactBytes(upload))"
}

func formatMemoryCompact(used: Double, total: Double) -> String {
    "MEM \(compactBytes(used))/\(compactBytes(total))"
}
