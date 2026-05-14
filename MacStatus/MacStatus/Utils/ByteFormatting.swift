import Foundation

// MARK: - Compact Byte Formatting — menu bar optimized

private let byteUnits = ["B", "K", "M", "G", "T"]

private func compactBytes(_ bytes: Double) -> String {
    var value = max(bytes, 0)
    var unitIndex = 0
    while value >= 1000 && unitIndex < byteUnits.count - 1 {
        value /= 1000
        unitIndex += 1
    }

    let unit = byteUnits[unitIndex]
    if unitIndex == 0 || value >= 9.95 {
        return "\(min(Int(value.rounded()), 999))\(unit)"
    }
    return String(format: "%.1f", value) + unit
}

func formatNetworkCompact(download: Double, upload: Double) -> String {
    "↓\(compactBytes(download)) ↑\(compactBytes(upload))"
}

func formatMemoryPressure(_ level: MemoryPressureLevel) -> String {
    switch level {
    case .normal:
        return "MEM OK"
    case .warning:
        return "MEM WARN"
    case .critical:
        return "MEM CRIT"
    case .unknown:
        return "MEM --"
    }
}
