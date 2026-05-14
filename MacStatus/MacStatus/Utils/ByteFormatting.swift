import Foundation

// MARK: - Byte Formatting Utilities
// Free functions — no singleton, no state, safe to call from any context
// (Reader background queue or @MainActor StatusBarManager).

/// Format bytes-per-second for network rate display (1000-byte units,
/// matching the KB/s / MB/s convention users expect for network speed).
///
/// - Parameter bytesPerSec: Raw bytes-per-second rate.
/// - Returns: Formatted string like `"512 KB/s"`, `"2.1 MB/s"`, or `"0 KB/s"`.
func formatNetworkRate(_ bytesPerSec: Double) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file       // 1000-byte units
    formatter.allowsNonnumericFormatting = false
    return formatter.string(fromByteCount: Int64(bytesPerSec)) + "/s"
}

/// Format bytes for memory display (1024-byte units, matching the
/// GiB / MiB convention).
///
/// - Parameter bytes: Raw byte count.
/// - Returns: Formatted string like `"8.2 GB"`, `"16 GB"`, or `"0 bytes"`.
func formatMemoryBytes(_ bytes: Double) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .memory     // 1024-byte units
    formatter.allowsNonnumericFormatting = false
    return formatter.string(fromByteCount: Int64(bytes))
}

/// Compact network rate format — `"↓2.1M ↑512K"`.
///
/// Strips the trailing `/s` suffix from the download and upload components
/// so the arrow symbols carry the visual weight. (D-01)
///
/// - Parameters:
///   - download: Download bytes-per-second rate.
///   - upload: Upload bytes-per-second rate.
/// - Returns: Formatted string like `"↓2.1M ↑512K"`.
func formatNetworkCompact(download: Double, upload: Double) -> String {
    let dl = formatNetworkRate(download)
        .replacingOccurrences(of: "/s", with: "")
        .replacingOccurrences(of: " ", with: "")
    let ul = formatNetworkRate(upload)
        .replacingOccurrences(of: "/s", with: "")
        .replacingOccurrences(of: " ", with: "")
    return "↓\(dl) ↑\(ul)"
}

/// Compact memory format — `"MEM 8.2G/16G"`.
///
/// Strips spaces so the string fits in a fixed-width menu bar item. (D-02)
///
/// - Parameters:
///   - used: Bytes currently in use.
///   - total: Total physical memory in bytes.
/// - Returns: Formatted string like `"MEM 8.2G/16G"`.
func formatMemoryCompact(used: Double, total: Double) -> String {
    let usedStr = formatMemoryBytes(used).replacingOccurrences(of: " ", with: "")
    let totalStr = formatMemoryBytes(total).replacingOccurrences(of: " ", with: "")
    return "MEM \(usedStr)/\(totalStr)"
}
