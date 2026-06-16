import Foundation

// MARK: - Compact Byte Formatting — menu bar optimized

/// Namespace for byte formatting utilities.
/// All methods are static — the enum has no cases and cannot be instantiated.
enum ByteFormatting {
    private static let units = ["B", "K", "M", "G", "T"]

    /// Format a byte count or rate into a compact string (e.g. "23B", "1.2K", "99M").
    /// Used in both the menu bar title and the popover detail panel.
    static func format(_ bytes: Double) -> String {
        var value = max(bytes, 0)
        var unitIndex = 0
        while value >= 1000 && unitIndex < units.count - 1 {
            value /= 1000
            unitIndex += 1
        }

        let unit = units[unitIndex]
        if unitIndex == 0 || value >= 9.95 {
            return "\(min(Int(value.rounded()), 999))\(unit)"
        }

        let decimalText = String(format: "%.1f", value)
        if decimalText.hasSuffix(".0") {
            return String(decimalText.dropLast(2)) + unit
        }
        return decimalText + unit
    }

    /// Format download/upload pair for network display.
    static func formatNetwork(download: Double, upload: Double) -> String {
        "↓\(format(download)) ↑\(format(upload))"
    }

    /// Format a single rate value with /s suffix.
    static func formatRate(_ bytesPerSec: Double) -> String {
        "\(format(bytesPerSec))/s"
    }
}

// MARK: - Legacy Global Functions (for backward compatibility)

func formatNetworkCompact(download: Double, upload: Double) -> String {
    ByteFormatting.formatNetwork(download: download, upload: upload)
}

func formatNetworkRateCompact(_ bytesPerSec: Double) -> String {
    ByteFormatting.formatRate(bytesPerSec)
}

func formatMemoryPressure(_ level: MemoryPressureLevel, usedPercent: Double?) -> String {
    let usageText: String
    if let usedPercent {
        usageText = String(format: "%.0f", usedPercent)
    } else {
        usageText = "--"
    }

    switch level {
    case .normal, .warning, .critical:
        return "M\(usageText)"
    case .unknown:
        guard usedPercent != nil else { return "M--" }
        return "M\(usageText)"
    }
}
