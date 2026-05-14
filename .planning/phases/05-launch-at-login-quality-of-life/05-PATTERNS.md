# Phase 5: Launch at Login + Quality of Life - Patterns

**Date:** 2026-05-14
**Phase:** 05-launch-at-login-quality-of-life

## PATTERN MAPPING COMPLETE

## Files To Modify

| File | Role | Existing Pattern | Required Change |
|------|------|------------------|-----------------|
| `MacStatus/MacStatus/App/AppDelegate.swift` | App lifecycle and reader wiring | Create readers, assign callbacks, start/stop on launch/terminate | Add launch-at-login registration, factor reader start/stop, observe sleep/wake |
| `MacStatus/MacStatus/UI/StatusBarManager.swift` | Visible combined status item | `configureStatusButton(_:)` centralizes button configuration | Add right-click target/action and minimal quit menu |
| `MacStatus/MacStatus.xcodeproj/project.pbxproj` | Build target config | System frameworks are explicitly listed for SystemConfiguration and IOKit | Add ServiceManagement framework if required by the build |

## Closest Existing Analogs

### Reader Lifecycle

Source: `MacStatus/MacStatus/App/AppDelegate.swift`

```swift
cpuReader?.start()
networkReader?.start()
memoryReader?.start()
gpuReader?.start()
```

Phase 5 should factor this into `startReaders()` so wake recovery and launch share the same path.

### Termination Cleanup

Source: `MacStatus/MacStatus/App/AppDelegate.swift`

```swift
cpuReader?.stop()
networkReader?.stop()
memoryReader?.stop()
gpuReader?.stop()
```

Phase 5 should reuse this as `stopReaders()` and call it before sleep and during termination.

### Status Button Configuration

Source: `MacStatus/MacStatus/UI/StatusBarManager.swift`

```swift
private func configureStatusButton(_ button: NSStatusBarButton?) {
    button?.cell?.lineBreakMode = .byClipping
    button?.cell?.usesSingleLineMode = true
    button?.cell?.wraps = false
}
```

Phase 5 should add right-click target/action here without changing clipping, fixed width, or attributed title behavior.

### Framework Linking

Source: `MacStatus/MacStatus.xcodeproj/project.pbxproj`

```text
SystemConfiguration.framework in Frameworks
IOKit.framework in Frameworks
```

Phase 5 should follow the same explicit framework pattern for ServiceManagement if the project needs it.

## Constraints For Planner

- Keep AppDelegate as the lifecycle owner.
- Keep StatusBarManager as the only visible status item owner.
- Do not add a settings view or new UserDefaults key.
- Do not introduce a helper target for launch at login.
- Do not change Phase 4 display formatting.
- Do not add new timers outside existing reader instances.
