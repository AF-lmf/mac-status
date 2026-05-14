# Phase 3: GPU Monitoring - Patterns

**Date:** 2026-05-14
**Phase:** 03-gpu-monitoring

## PATTERN MAPPING COMPLETE

## Files To Create

| File | Role | Closest Existing Analog | Pattern To Reuse |
|------|------|-------------------------|------------------|
| `MacStatus/MacStatus/Readers/GPUReader.swift` | System metric reader | `MacStatus/MacStatus/Readers/MemoryReader.swift` and `MacStatus/MacStatus/Readers/NetworkReader.swift` | `TimerReader<T>` subclass, `Sendable` value type, `onUpdate?(nil)` fallback |

## Files To Modify

| File | Role | Existing Pattern | Required Change |
|------|------|------------------|-----------------|
| `MacStatus/MacStatus.xcodeproj/project.pbxproj` | Xcode source/framework registration | Existing `MemoryReader.swift in Sources` and `SystemConfiguration.framework in Frameworks` entries | Add `GPUReader.swift` source refs and `IOKit.framework` framework refs |
| `MacStatus/MacStatus/App/AppDelegate.swift` | Reader wiring hub | CPU/network/memory properties, callbacks, start/stop lifecycle | Add `gpuReader`, `updateGPU` callback, start/stop/nil lifecycle |
| `MacStatus/MacStatus/UI/StatusBarManager.swift` | Visible status item presentation | `latestCPUText`, `latestMemoryText`, `latestNetworkText`, `updateCombinedStatus()` | Add GPU state, target order, GPU segment coloring |
| `MacStatus/MacStatus/Utils/ByteFormatting.swift` | Compact display formatting | `formatNetworkCompact`, `formatMemoryPressure` | Change memory labels from `MEM` to `M`; optionally add pressure color helper if kept out of `StatusBarManager` |

## Concrete Code Excerpts

### Reader Subclass Pattern

Source: `MacStatus/MacStatus/Readers/MemoryReader.swift`

```swift
final class MemoryReader: TimerReader<MemoryStats> {
    init() {
        super.init(interval: 2.0)
    }

    override func read() {
        // system API
        guard result == 0 else {
            onUpdate?(nil)
            return
        }

        onUpdate?(MemoryStats(...))
    }
}
```

GPUReader should follow this shape exactly.

### Main-Thread UI Wiring Pattern

Source: `MacStatus/MacStatus/App/AppDelegate.swift`

```swift
memoryReader?.onUpdate = { [weak self] stats in
    DispatchQueue.main.async {
        self?.statusBarManager?.updateMemory(stats)
    }
}
memoryReader?.start()
```

GPUReader should use the same callback shape.

### Combined Status Pattern

Source: `MacStatus/MacStatus/UI/StatusBarManager.swift`

```swift
private func updateCombinedStatus() {
    setTitle(
        "\(latestCPUText) | \(latestMemoryText) | \(latestNetworkText)",
        on: networkStatusItem
    )
}
```

Phase 3 should evolve this to:

```swift
"\(latestCPUText) | \(latestGPUText) | \(latestMemoryText) | \(latestNetworkText)"
```

Then build an attributed string that colors only the GPU range when `latestGPUPressure` is not nil.

## Constraints For Planner

- Do not create a separate visible GPU `NSStatusItem`; Phase 2 UAT showed separate items are unreliable for the user.
- Do not color CPU/MEM in Phase 3; that is deferred to Phase 4.
- Do not use `Process`, `top`, `nettop`, or shell commands for readings.
- Do not put IOKit calls on the main thread.

