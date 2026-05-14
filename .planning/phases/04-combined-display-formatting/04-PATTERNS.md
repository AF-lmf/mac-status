# Phase 4: Combined Display + Formatting - Patterns

**Date:** 2026-05-14
**Phase:** 04-combined-display-formatting

## PATTERN MAPPING COMPLETE

## Files To Modify

| File | Role | Existing Pattern | Required Change |
|------|------|------------------|-----------------|
| `MacStatus/MacStatus/UI/StatusBarManager.swift` | Visible status item presentation | `latestCPUText`, `latestGPUText`, `latestMemoryText`, `latestNetworkText`, `combinedAttributedString()`, `baseAttributes()` | Preserve raw CPU/GPU/MEM state and color only value/status substrings |

## Closest Existing Analogs

### Segment-Aware Attributed Title

Source: `MacStatus/MacStatus/UI/StatusBarManager.swift`

```swift
private func combinedAttributedString() -> NSAttributedString {
    let result = NSMutableAttributedString()
    let separator = NSAttributedString(string: " | ", attributes: baseAttributes())

    result.append(NSAttributedString(string: latestCPUText, attributes: baseAttributes()))
    result.append(separator)
    result.append(NSAttributedString(string: latestGPUText, attributes: gpuAttributes()))
    result.append(separator)
    result.append(NSAttributedString(string: latestMemoryText, attributes: baseAttributes()))
    result.append(separator)
    result.append(NSAttributedString(string: latestNetworkText, attributes: baseAttributes()))

    return result
}
```

Phase 4 should keep this central construction point but append CPU/GPU/MEM as label + value so attributes apply only to the value/status word.

### Base Attributes

Source: `MacStatus/MacStatus/UI/StatusBarManager.swift`

```swift
private func baseAttributes() -> [NSAttributedString.Key: Any] {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byClipping

    return [
        .font: NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.smallSystemFontSize,
            weight: .regular
        ),
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: paragraph,
    ]
}
```

Phase 4 should reuse this as the default for labels, separators, network, and normal/default values.

### Fixed Width / Single Line

Source: `MacStatus/MacStatus/UI/StatusBarManager.swift`

```swift
networkStatusItem = NSStatusBar.system.statusItem(withLength: 300)
button?.cell?.lineBreakMode = .byClipping
button?.cell?.usesSingleLineMode = true
button?.cell?.wraps = false
```

Phase 4 must preserve these exact behaviors to satisfy DISP-02.

## Constraints For Planner

- Do not create or remove status items.
- Do not move reader logic into UI formatting code.
- Do not parse CPU/GPU percentages from strings when raw values are available during update.
- Do not color labels, separators, or network text.
- Do not use GPU green for normal/default state.
- Do not change fixed width `300` in Phase 4.
