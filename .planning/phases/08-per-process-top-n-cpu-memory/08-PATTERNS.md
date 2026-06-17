# Phase 8: Per-Process Top-N CPU & Memory - Pattern Map

**Mapped:** 2026-06-17
**Files analyzed:** 4 (1 new, 3 modified)
**Analogs found:** 4 / 4

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `MacStatus/MacStatus/Readers/ProcessResourceReader.swift` | service/reader | stateful-CRUD (snapshot-diff) | `MacStatus/MacStatus/Readers/ProcessNetworkReader.swift` + `MemoryReader.swift` | role-match (struct/Sendable pattern) + partial (C-interop pointer pattern) |
| `MacStatus/MacStatus/UI/PopoverManager.swift` | controller | event-driven (popover lifecycle) | `MacStatus/MacStatus/UI/PopoverManager.swift` lines 111-141 | exact (extend existing file) |
| `MacStatus/MacStatus/UI/Views/DashboardView.swift` | view + state | request-response | `MacStatus/MacStatus/UI/Views/DashboardView.swift` lines 262-381 | exact (extend DashboardState; mirror ProcessListView insertion) |
| `MacStatus/MacStatus/UI/Views/ProcessListView.swift` | component | request-response | `MacStatus/MacStatus/UI/Views/ProcessListView.swift` lines 57-91 | exact (generalize existing ProcessRow) |

---

## Pattern Assignments

### `MacStatus/MacStatus/Readers/ProcessResourceReader.swift` (new file — service, stateful snapshot-diff)

**Primary analog:** `MacStatus/MacStatus/Readers/ProcessNetworkReader.swift`
**Secondary analog (C-interop pointer pattern):** `MacStatus/MacStatus/Readers/MemoryReader.swift` lines 89-93

#### Sendable result struct pattern
Copy from `ProcessNetworkReader.swift` lines 5-14:
```swift
struct ProcessNetworkUsage: Sendable, Equatable {
    let processName: String
    let processIdentifier: Int32?
    let downloadBytesPerSec: Double
    let uploadBytesPerSec: Double
}
```
Adapt to:
```swift
struct ProcessResourceUsage: Sendable, Equatable {
    let processName: String
    let pid: Int32
    let cpuPercent: Double?   // nil = first frame (no prior snapshot) → display "—"
    let memoryBytes: UInt64   // ri_phys_footprint
}
```

#### Import pattern
Copy from `MemoryReader.swift` line 1 and `GPUReader.swift` lines 1-2:
```swift
import Darwin
import Foundation
```
`import Darwin` is sufficient for all libproc symbols (`proc_listpids`, `proc_pid_rusage`, `proc_name`, `mach_absolute_time`). No bridging header needed (same as existing MemoryReader/GPUReader).

#### Darwin C-interop withUnsafeMutablePointer pattern
Copy from `MemoryReader.swift` lines 89-93:
```swift
let result = withUnsafeMutablePointer(to: &vmStats) {
    $0.withMemoryRebound(to: integer_t.self, capacity: count) {
        host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
    }
}
```
Adapt for `proc_pid_rusage` (simpler — single raw pointer erase, no rebound needed):
```swift
var info = rusage_info_v4()
let ret = withUnsafeMutablePointer(to: &info) {
    proc_pid_rusage(pid, RUSAGE_INFO_V4, UnsafeMutableRawPointer($0))
}
guard ret == 0 else { continue }  // EPERM / ESRCH / process exited → skip silently
```

#### Reader class shape (stateful — NOT enum like ProcessNetworkReader)
`ProcessNetworkReader` is a stateless `enum` with static methods. `ProcessResourceReader` must be a `final class` to hold `prevSnapshot`. Model the class skeleton after `GPUReader.swift` lines 27-40 (final class with private state), but without `TimerReader` inheritance (driven by PopoverManager's Task loop instead):
```swift
final class ProcessResourceReader {
    private var prevSnapshot: [ProcessKey: SnapshotEntry] = [:]

    struct ProcessKey: Hashable {
        let pid: Int32
        let startAbstime: UInt64   // ri_proc_start_abstime — PID-reuse-safe key
    }
    struct SnapshotEntry {
        let cpuTicks: UInt64       // ri_user_time + ri_system_time (Mach ticks)
        let wallTicks: UInt64      // mach_absolute_time() at sample time
    }

    func clearSnapshot() { prevSnapshot.removeAll() }

    /// Synchronous. Call only from Task.detached(priority: .utility).
    func sample() -> ([ProcessResourceUsage], [ProcessResourceUsage]) { ... }
}
```

#### proc_listpids two-call buffer pattern (from RESEARCH.md — no codebase analog)
```swift
let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
guard needed > 0 else { return ([], []) }
let count = Int(needed) / MemoryLayout<Int32>.size
var pids = [Int32](repeating: 0, count: count + count / 10)  // +10% headroom
let actual = pids.withUnsafeMutableBytes { buf in
    proc_listpids(UInt32(PROC_ALL_PIDS), 0, buf.baseAddress, Int32(buf.count))
}
guard actual > 0 else { return ([], []) }
let pidCount = Int(actual) / MemoryLayout<Int32>.size
// Filter: guard pid > 0 else { continue }  // skip pid 0 (kernel_task)
```

#### CPU% delta formula (units cancel — from RESEARCH.md verified finding)
```swift
// wallNow = mach_absolute_time()  — same tick unit as ri_user_time
let cpuTicks = info.ri_user_time + info.ri_system_time
if let prev = prevSnapshot[key] {
    let deltaCPU  = cpuTicks >= prev.cpuTicks ? cpuTicks - prev.cpuTicks : 0
    let deltaWall = wallNow  > prev.wallTicks  ? wallNow  - prev.wallTicks : 0
    if deltaWall > 0 {
        cpuPercent = min(Double(deltaCPU) / Double(deltaWall) * 100.0, 999.9)
    }
}
// First frame: cpuPercent stays nil → UI displays "—"
```

#### Sorting / Top-N pattern
Copy sort style from `ProcessNetworkReader.swift` lines 124-130:
```swift
.sorted {
    if $0.totalBytesPerSec == $1.totalBytesPerSec {
        return $0.processName < $1.processName
    }
    return $0.totalBytesPerSec > $1.totalBytesPerSec
}
```
Adapt for CPU (nil cpuPercent sorts last via `-1` sentinel):
```swift
let cpuSorted = candidates.sorted {
    let a = $0.cpuPercent ?? -1
    let b = $1.cpuPercent ?? -1
    if a == b { return $0.name < $1.name }
    return a > b
}
let cpuTop5 = Array(cpuSorted.prefix(5)).map { ProcessResourceUsage(...) }
```
Memory sort (no nil):
```swift
let memSorted = candidates.sorted {
    if $0.memBytes == $1.memBytes { return $0.name < $1.name }
    return $0.memBytes > $1.memBytes
}
let memTop5 = Array(memSorted.prefix(5)).map { ProcessResourceUsage(...) }
```

---

### `MacStatus/MacStatus/UI/PopoverManager.swift` (modify — add resource sampling loop)

**Analog:** `PopoverManager.swift` lines 22-24 (task property), 111-141 (refreshProcessList pattern), 100-105 (popoverDidClose)

#### New task property (lines 22-24 — mirror existing processRefreshTask):
```swift
// Existing (line 23):
private var processRefreshTask: Task<Void, Never>?

// Add alongside it:
private var resourceSampleTask: Task<Void, Never>?
private let resourceReader = ProcessResourceReader()
```

#### Sampling loop pattern — copy structure from `refreshProcessList()` lines 118-139, adapt for loop:
```swift
// Existing one-shot pattern (lines 118-139):
processRefreshTask = Task { [weak self] in
    let result = await Task.detached(priority: .utility) {
        ProcessNetworkReader.readTopProcesses()
    }.value

    guard !Task.isCancelled else { return }

    await MainActor.run { [weak self] in
        guard let self else { return }
        self.dashboardState.topProcesses = procs
        self.dashboardState.processesLoading = false
    }
}

// New loop variant for resource sampling:
func startResourceSampling() {
    resourceSampleTask?.cancel()
    resourceSampleTask = Task { [weak self] in
        while !Task.isCancelled {
            guard let self else { return }
            let (cpuTop, memTop) = await Task.detached(priority: .utility) {
                [reader = self.resourceReader] in
                reader.sample()
            }.value

            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.dashboardState.topCPUProcesses = cpuTop
                self.dashboardState.topMemoryProcesses = memTop
                self.dashboardState.resourceLoading = false
            }

            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
    }
}
```

#### toggle() call site — copy from lines 64-67, add startResourceSampling() after existing refreshProcessList():
```swift
// Existing (lines 64-67):
popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
refreshProcessList()   // ← existing, keep
// Add:
startResourceSampling()
```

#### popoverDidClose() — copy from lines 103-105, extend:
```swift
// Existing (lines 103-105):
func popoverDidClose(_ notification: Notification) {
    stopOutsideClickMonitor()
    // Add:
    resourceSampleTask?.cancel()
    resourceSampleTask = nil
    resourceReader.clearSnapshot()
    dashboardState.resourceLoading = true  // reset spinner for next open
}
```

---

### `MacStatus/MacStatus/UI/Views/DashboardView.swift` (modify — DashboardState new fields + two new sections)

**Analog:** `DashboardView.swift` lines 262-381 (DashboardState), lines 67-71 (ProcessListView insertion point)

#### New DashboardState @Published fields — copy from lines 289-291 (Processes group), add after:
```swift
// Existing (lines 289-291):
@Published var topProcesses: [ProcessNetworkUsage] = []
@Published var processesLoading: Bool = false
@Published var processError: String?

// Add:
@Published var topCPUProcesses: [ProcessResourceUsage] = []
@Published var topMemoryProcesses: [ProcessResourceUsage] = []
@Published var resourceLoading: Bool = true
@Published var resourceError: String? = nil
```

#### New sections in DashboardView body — copy ProcessListView insertion pattern from lines 67-71:
```swift
// Existing (lines 67-71):
ProcessListView(
    processes: state.topProcesses,
    isLoading: state.processesLoading,
    errorMessage: state.processError
)

// Add two new sections immediately after:
ProcessResourceSectionView(
    title: "CPU 占用 Top 5",
    items: state.topCPUProcesses,
    isLoading: state.resourceLoading,
    trailingText: { proc in
        proc.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "—"
    }
)
ProcessResourceSectionView(
    title: "内存占用 Top 5",
    items: state.topMemoryProcesses,
    isLoading: state.resourceLoading,
    trailingText: { proc in
        ByteFormatting.format(Double(proc.memoryBytes))
    }
)
```

#### Card background style — copy from `ProcessListView.swift` lines 47-51 (or `MetricCardWithSparkline` lines 148-152):
```swift
.padding(10)
.background(
    RoundedRectangle(cornerRadius: 8)
        .fill(Color.primary.opacity(0.04))
)
```

---

### `MacStatus/MacStatus/UI/Views/ProcessListView.swift` (modify — extract ProcessMetricRow, keep ProcessRow working)

**Analog:** `ProcessListView.swift` lines 57-91 (existing private ProcessRow)

#### Existing ProcessRow to generalize — copy lines 57-91:
```swift
private struct ProcessRow: View {
    let process: ProcessNetworkUsage

    var body: some View {
        HStack(spacing: 6) {
            Text(process.processName)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.tail)

            if let pid = process.processIdentifier {
                Text("(\(pid))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Label(ByteFormatting.format(process.uploadBytesPerSec) + "/s", systemImage: "arrow.up")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.orange)

            Label(ByteFormatting.format(process.downloadBytesPerSec) + "/s", systemImage: "arrow.down")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.blue)
        }
        .padding(.vertical, 1)
    }
}
```

#### Generalized ProcessMetricRow — extract HStack skeleton, add generic trailing:
```swift
struct ProcessMetricRow<Trailing: View>: View {
    let processName: String
    let pid: Int32?
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 6) {
            Text(processName)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.tail)

            if let pid {
                Text("(\(pid))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
            trailing()
        }
        .padding(.vertical, 1)
    }
}
```

Replace existing `ProcessRow` usage in `ProcessListView` with:
```swift
ProcessMetricRow(processName: proc.processName, pid: proc.processIdentifier) {
    Label(ByteFormatting.format(proc.uploadBytesPerSec) + "/s", systemImage: "arrow.up")
        .font(.system(.caption2, design: .monospaced))
        .foregroundStyle(.orange)
    Label(ByteFormatting.format(proc.downloadBytesPerSec) + "/s", systemImage: "arrow.down")
        .font(.system(.caption2, design: .monospaced))
        .foregroundStyle(.blue)
}
```

#### Loading / empty state pattern — copy from `ProcessListView.swift` lines 19-45 verbatim for new CPU/memory sections:
```swift
if isLoading {
    HStack {
        ProgressView().scaleEffect(0.6)
        Text("Sampling...")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .padding(.vertical, 8)
} else if items.isEmpty {
    Text("无数据")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 8)
} else {
    ForEach(Array(items.prefix(5).enumerated()), id: \.offset) { _, proc in
        ProcessMetricRow(...) { ... }
    }
}
```

---

## Shared Patterns

### `import Darwin` — Darwin C-interop
**Source:** `MacStatus/MacStatus/Readers/MemoryReader.swift` line 1, `GPUReader.swift` line 1
**Apply to:** `ProcessResourceReader.swift`
All libproc symbols (`proc_listpids`, `proc_pid_rusage`, `proc_name`, `mach_absolute_time`, `rusage_info_v4`, `RUSAGE_INFO_V4`, `PROC_ALL_PIDS`) are accessible via `import Darwin`. No bridging header required.

### withUnsafeMutablePointer C-struct pointer pattern
**Source:** `MacStatus/MacStatus/Readers/MemoryReader.swift` lines 89-93
**Apply to:** `ProcessResourceReader.swift` — `proc_pid_rusage` call
Use `UnsafeMutableRawPointer($0)` to erase `UnsafeMutablePointer<rusage_info_v4>` to the `void *` that `proc_pid_rusage`'s third parameter (`rusage_info_t *`) expects.

### Task.detached(priority: .utility) + MainActor.run result delivery
**Source:** `MacStatus/MacStatus/UI/PopoverManager.swift` lines 118-139
**Apply to:** `PopoverManager.startResourceSampling()` — heavy syscall loop runs detached, results posted back via `await MainActor.run`.

### Sendable struct result type
**Source:** `MacStatus/MacStatus/Readers/ProcessNetworkReader.swift` lines 5-14
**Apply to:** `ProcessResourceUsage` — pure value type (`String`, `Int32`, `Double?`, `UInt64`), all fields Sendable, allowing safe transfer across actor boundaries without `@unchecked Sendable`.

### Card section visual style
**Source:** `MacStatus/MacStatus/UI/Views/ProcessListView.swift` lines 47-52
**Apply to:** New CPU/memory section views in `DashboardView.swift`
```swift
.padding(10)
.background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
```

### ByteFormatting.format() for memory display
**Source:** `MacStatus/MacStatus/UI/Views/ProcessListView.swift` line 76 (upload), `DashboardView.swift` line 342
**Apply to:** Memory trailing text in `ProcessMetricRow` for memory section:
```swift
ByteFormatting.format(Double(proc.memoryBytes))
```

---

## Required Non-Pattern Step: pbxproj Registration

**Background:** Phase 7 post-mortem — files created outside Xcode are not automatically added to the compile target; BUILD SUCCEEDED but the type was missing at runtime.

**Required for:** `MacStatus/MacStatus/Readers/ProcessResourceReader.swift`

**Pattern source:** `MacStatus/MacStatus.xcodeproj/project.pbxproj` — existing Readers group entries

Three additions required in `project.pbxproj`:

1. **PBXFileReference** (copy from line 58 — GPUReader pattern):
```
/* ProcessResourceReader.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ProcessResourceReader.swift; sourceTree = "<group>"; };
```

2. **PBXBuildFile** (copy from line 24 — GPUReader pattern):
```
/* ProcessResourceReader.swift in Sources */ = {isa = PBXBuildFile; fileRef = <new UUID> /* ProcessResourceReader.swift */; };
```

3. **Readers group child** — add the new PBXFileReference UUID to the Readers group children array (same group that contains `GPUReader.swift`, `BatteryReader.swift`, `ProcessNetworkReader.swift` at pbxproj lines 58, 59, 54).

4. **Sources build phase** — add the new PBXBuildFile UUID to the Sources phase (mirror line 283: `E10000000000000000000002 /* ProcessNetworkReader.swift in Sources */`).

The safest method is to create the file via **Xcode → File → New File** within the `Readers` group, which handles all four pbxproj entries automatically.

---

## No Analog Found

All four files have codebase analogs. No files require falling back to RESEARCH.md patterns exclusively — though the `proc_listpids` two-call buffer dance and the CPU-ticks-cancel math have no direct codebase precedent and must be copied from RESEARCH.md `## Code Examples`.

---

## Metadata

**Analog search scope:** `MacStatus/MacStatus/Readers/`, `MacStatus/MacStatus/UI/`, `MacStatus/MacStatus/UI/Views/`, `MacStatus/MacStatus.xcodeproj/project.pbxproj`
**Files scanned:** 8 (ProcessNetworkReader, MemoryReader, GPUReader, BatteryReader, PopoverManager, DashboardView, ProcessListView, project.pbxproj)
**Pattern extraction date:** 2026-06-17

## PATTERN MAPPING COMPLETE
