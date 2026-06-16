import AppKit

// MARK: - NSColor Hex Extension

extension NSColor {

    /// 从 "#RRGGBB" 格式字符串初始化 NSColor（sRGB 色彩空间）。
    ///
    /// 非法格式（长度不对、非十六进制字符）返回 nil，不 crash。
    /// 符合威胁模型 T-06-06：hex 字符串来自 UserDefaults，须容错解析。
    convenience init?(hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard cleaned.count == 6 else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        self.init(colorSpace: .sRGB, components: [r, g, b, 1.0], count: 4)
    }

    /// 将颜色转回 "#RRGGBB" 格式字符串（sRGB，截断到 0–255 整数）。
    ///
    /// 若颜色无法转换到 sRGB 色彩空间（极少见），回退返回 "#000000"。
    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
