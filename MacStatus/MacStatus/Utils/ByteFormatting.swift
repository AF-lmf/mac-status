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

func formatMemoryPressure(_ level: MemoryPressureLevel, usedPercent: Double?) -> String {
    let usageText = formatMemoryUsagePercent(usedPercent)

    switch level {
    case .normal:
        return "M OK \(usageText)"
    case .warning:
        return "M WARN \(usageText)"
    case .critical:
        return "M CRIT \(usageText)"
    case .unknown:
        guard usedPercent != nil else { return "M --" }
        return "M -- \(usageText)"
    }
}

private func formatMemoryUsagePercent(_ usedPercent: Double?) -> String {
    guard let usedPercent else { return "--%" }
    return String(format: "%.0f%%", usedPercent)
}
