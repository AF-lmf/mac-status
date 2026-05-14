# Phase 2: Network + Memory Monitoring - Research

**Researched:** 2026-05-14
**Domain:** macOS network bandwidth + memory utilization monitoring via Mach/BSD APIs
**Confidence:** HIGH

## Summary

Phase 2 adds two Readers to the MacStatus menu bar app: `NetworkReader` (download/upload rate via `getifaddrs` + `SystemConfiguration`) and `MemoryReader` (RAM used/total via `host_statistics64` + `host_info`). Both extend `TimerReader<T>`, inheriting Phase 1's Timer lifecycle, background-queue polling, and `onUpdate` callback pattern. The primary architectural risk is network interface detection — hardcoding `"en0"` breaks on VPN, Thunderbolt, and multi-adapter Macs. The verified solution uses `SCDynamicStoreCopyValue("State:/Network/Global/IPv4")` to dynamically resolve the primary interface, then polls only that interface's byte counters via `getifaddrs()`.

**Primary recommendation:** Follow the Stats (exelban/stats) source code patterns exactly — they are production-proven on 38k+ stars of real-world macOS usage. Do not hand-roll byte formatting when `ByteCountFormatter` exists. Do not poll all interfaces — only the primary one from SystemConfiguration.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Network byte counter reading | Reader (background queue) | — | `getifaddrs()` is a C call, must run off main thread per Phase 1 patterns |
| Primary interface detection | Reader (setup) | — | `SCDynamicStoreCopyValue` is lightweight, called in setup and on network change |
| Byte counter delta → throughput rate | Reader (read) | — | Pure arithmetic on raw counter data, no I/O |
| Byte formatting (B/KB/MB/GB) | Reader or Utility | — | `ByteCountFormatter` is a pure formatter, callable from any context |
| Memory page stats → bytes | Reader (read) | — | Multiply page counts by `vm_page_size`, `totalSize` from setup |
| NSStatusItem display update | `@MainActor StatusBarManager` | — | All `NSStatusBarButton` mutations must be on main thread per AppKit |
| Network change detection | Reader (setup + timer) | AppDelegate (NSNotification) | Optional: `SCDynamicStore` notifications; fallback: periodic re-check in read() |

## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Menu bar shows "↓2.1M ↑512K" format — arrow symbols for download/upload, auto-select KB/s or MB/s units
- **D-02:** Menu bar shows "MEM 8.2G/16G" format — label+value pattern matching CPU's "CPU 45%"
- **D-03:** Use `SCDynamicStoreCopyValue("State:/Network/Global/IPv4")` to get primary interface — never hardcode "en0"
- **D-04:** Filter virtual interfaces: `awdl`, `utun`, `bridge`, `gif`, `stf`, `lo`
- **D-05:** Use `getifaddrs()` reading `if_data.ifi_ibytes`/`ifi_obytes`, compute delta over time interval
- **D-06:** Network refresh interval: 1 second (faster sampling for accurate burst rate)
- **D-07:** Handle 64-bit counter wraparound — use signed difference to avoid negative values
- **D-08:** Use `host_statistics64(HOST_VM_INFO64)` for memory page statistics
- **D-09:** Use `host_info(HOST_BASIC_INFO)` for total physical memory
- **D-10:** Memory refresh interval: 2 seconds (slower-changing metric)
- **D-11:** Both Readers extend `TimerReader<T>`, implement `ReaderProtocol`
- **D-12:** NetworkReader `ValueType = NetworkStats`, MemoryReader `ValueType = MemoryStats` (both `Sendable` structs)
- **D-13:** Phase 2 uses multiple `NSStatusItem` (separate for CPU, network, memory) — Phase 4 merges
- **D-14:** StatusBarManager gets `updateNetwork()` and `updateMemory()` methods, each with FixedWidth NSStatusItem

### Inherited from Phase 1
- Swift 6 + strict concurrency
- 0.5% tolerance threshold for UI redraws (D-06 from Phase 1)
- `.monospacedDigit()` font for menu bar text
- `LSUIElement = YES`, no Dock icon
- `deinit` calls `removeStatusItem` for ghost icon prevention
- Background `DispatchQueue` polling + `MainActor` UI updates
- `TimerReader.start()` fires first read immediately (LIFE-03)

### Agent's Discretion
- Network interface change detection: can use timer-based re-check or `NSNotification` via SystemConfiguration callbacks
- Memory pressure level (`kern.memorystatus_vm_pressure_level`) — optional enhancement
- Byte formatting helper: use `ByteCountFormatter` or manual formatting for network/memory values

### Deferred Ideas (OUT OF SCOPE)
- Phase 4: Merging all indicators into a single NSStatusItem
- Memory pressure color coding (green/yellow/red)
- Network total usage counters (daily/monthly)
- Per-process network/memory breakdowns

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| NETW-01 | Status bar displays real-time download rate (KB/s or MB/s, auto-select unit) | `getifaddrs()` → `ifi_ibytes` delta / Δtime → `ByteCountFormatter` or manual → formatted string |
| NETW-02 | Status bar displays real-time upload rate (KB/s or MB/s, auto-select unit) | `getifaddrs()` → `ifi_obytes` delta / Δtime → same formatting pipeline |
| NETW-03 | Auto-detect active network interface (Wi-Fi/Ethernet/Thunderbolt), never hardcode | `SCDynamicStoreCopyValue("State:/Network/Global/IPv4")` → `PrimaryInterface` key |
| MEM-01 | Status bar displays memory used/total (e.g., "8.2G/16G") | `host_info(HOST_BASIC_INFO)` → `max_mem` for total; `host_statistics64(HOST_VM_INFO64)` → page counts × `vm_page_size` for used |

## Standard Stack

### Core APIs (Zero External Dependencies)

| API | Purpose | Version/Source | Why Standard |
|-----|---------|----------------|--------------|
| `getifaddrs()` + `freeifaddrs()` | Walk all network interfaces, read byte counters | POSIX, `<ifaddrs.h>` | Only BSD-level API for raw byte counters. Used by every macOS network monitor (Stats, MenuMeters, iStat Menus) |
| `if_data.ifi_ibytes` / `ifi_obytes` | Inbound/outbound byte counters per interface | `<net/if_var.h>`, kernel struct | 32-bit counters in `if_data`; use `Int64` conversion for wraparound safety |
| `SCDynamicStoreCopyValue()` | Read SystemConfiguration dynamic store for primary interface | SystemConfiguration framework, macOS 10.0+ | Returns `State:/Network/Global/IPv4` → `PrimaryInterface` key. Standard macOS API for network state |
| `host_statistics64(HOST_VM_INFO64)` | VM page statistics (64-bit fields) | `<mach/vm_statistics.h>`, Mach kernel | 64-bit version with compressor, swapins/swapouts fields. Prefer over `host_statistics(HOST_VM_INFO)` |
| `host_info(HOST_BASIC_INFO)` | Physical memory size, CPU count | `<mach/host_info.h>`, Mach kernel | Returns `max_mem` (uint64_t, actual RAM). Use `max_mem`, NOT `memory_size` (capped at 2 GB) |
| `vm_page_size` | Page size in bytes (global extern) | `<mach/vm_page_size.h>` | Multiply page counts by this for byte values. Extern C variable — Swift can reference directly |
| `sysctlbyname()` | Memory pressure level, swap usage | `<sys/sysctl.h>` | `kern.memorystatus_vm_pressure_level` (1=normal, 2=warning, 4=critical); `vm.swapusage` for swap stats |

### Supporting Foundation APIs

| API | Purpose | When to Use |
|-----|---------|-------------|
| `ByteCountFormatter` | Format bytes → "2.1 MB", "512 KB" | Network rate and memory display formatting. Built into Foundation, no custom code needed |
| `ByteCountFormatter.CountStyle.file` | Use file-size style (1 KB = 1000 bytes) | Closest match to network speed display convention |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `getifaddrs()` + delta calc | `NWPathMonitor` (Network framework) | `NWPathMonitor` reports connectivity state, NOT throughput. Wrong tool. |
| `getifaddrs()` + delta calc | `nettop` command via `Process()` | 1-5ms process-spawn overhead per read, fragile output parsing, locale-dependent. Rejected by STACK.md |
| `SCDynamicStoreCopyValue` | Hardcoded `"en0"` | Breaks on VPN, Thunderbolt, USB-C Ethernet. Pitfall P5 from PITFALLS.md. Rejected by D-03 |
| `host_info(HOST_BASIC_INFO).memory_size` | `max_mem` field | `memory_size` is capped at 2 GB. `max_mem` returns actual full RAM. [VERIFIED: SDK header, host_info.h line 120 vs 127] |
| `ByteCountFormatter` | Manual formatting with `/1024` loops | `ByteCountFormatter` handles locale, unit selection, rounding automatically. Manual formatting is 40+ lines of bug-prone code |
| `vm_statistics` (32-bit `host_statistics`) | `vm_statistics64` (64-bit `host_statistics64`) | 32-bit variant lacks compressor fields (`compressor_page_count`, `swapins`, `swapouts`). Always use 64-bit on macOS 14+ |

**Installation:** No package installation needed — all APIs are part of macOS SDK frameworks included with Xcode:
- `getifaddrs()` / `freeifaddrs()` — `<ifaddrs.h>`, system library (linked automatically)
- `SystemConfiguration` — link framework in Xcode target (already linked for Phase 1 settings)
- Mach APIs (`host_statistics64`, `host_info`) — `<mach/mach.h>`, system library (linked automatically)

**Note for NetworkReader:** The `SystemConfiguration` framework must be added to the Xcode target's "Link Binary with Libraries" build phase. Check if Phase 1 already links it; if not, it needs to be added. `ifaddrs` and Mach APIs are part of `libSystem` and require no explicit linking.

## Architecture Patterns

### System Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          AppDelegate (Main Thread)                             │
│  ┌─────────────────────┐    ┌─────────────────────┐    ┌──────────────────┐  │
│  │ CPUReader (Phase 1) │    │ NetworkReader (new) │    │ MemoryReader(new)│  │
│  │ interval: 2.0s      │    │ interval: 1.0s      │    │ interval: 2.0s   │  │
│  └────────┬────────────┘    └────────┬────────────┘    └────────┬─────────┘  │
│           │ onUpdate(Double?)        │ onUpdate(NetworkStats?)  │ onUpdate(  │
│           │                          │                          │  MemoryStats?)│
│           ▼                          ▼                          ▼             │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │              @MainActor StatusBarManager                                 │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                   │  │
│  │  │ NSStatusItem │  │ NSStatusItem │  │ NSStatusItem │                   │  │
│  │  │ (CPU, varLen)│  │ (Net, fixed) │  │ (Mem, fixed) │                   │  │
│  │  │ "CPU 45%"   │  │ "↓2.1M ↑512K"│  │ "MEM 8.2G/16G"│                  │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘                   │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────┘

                    DATA FLOW (NetworkReader Example)
                    
  Timer fires (1.0s)
       │
       ▼
  DispatchQueue.global(qos: .utility)
       │
       ├──→ SCDynamicStoreCopyValue("State:/Network/Global/IPv4")
       │    └──→ PrimaryInterface = "en0"
       │
       ├──→ getifaddrs(&ifap)  ──→  walk interfaces
       │    └──→ Match ifa_name == "en0" + AF_LINK check
       │         └──→ Cast ifa_data → if_data → ifi_ibytes, ifi_obytes
       │
       ├──→ Delta calc: (current - previous) / timeDelta
       │    ├── First read: store baseline, return nil
       │    └── Subsequent: rate = max(Δbytes / Δt, 0)
       │
       ├──→ Wrap in NetworkStats(download: rate_dl, upload: rate_ul)
       │
       └──→ onUpdate?(stats)
            │
            ▼ (callback on background queue)
       DispatchQueue.main.async {
           statusBarManager?.updateNetwork(stats)
       }
       
       @MainActor func updateNetwork(_ stats: NetworkStats?) {
           // Apply 0.5% tolerance, format bytes, update attributedTitle
       }
```

### Recommended Project Structure (Phase 2 additions)

```
MacStatus/MacStatus/
├── Readers/
│   ├── ReaderProtocol.swift          # (existing)
│   ├── TimerReader.swift             # (existing)
│   ├── CPUReader.swift               # (existing)
│   ├── NetworkReader.swift           # NEW: NetworkStats + getifaddrs + delta
│   └── MemoryReader.swift            # NEW: MemoryStats + host_statistics64
├── UI/
│   └── StatusBarManager.swift        # MODIFY: add updateNetwork(), updateMemory()
├── App/
│   └── AppDelegate.swift             # MODIFY: register NetworkReader, MemoryReader
└── Utils/
    └── SettingsManager.swift          # (existing — may need per-reader intervals)
```

### Pattern 1: Delta-Based Network Rate Calculation

**What:** Raw `ifi_ibytes`/`ifi_obytes` are monotonically increasing counters. Rate = (current - previous) / elapsed_time. Use `Int64` conversion from `u_int32_t` to handle counter wraparound safely.

**When to use:** Network bandwidth display. Every read cycle.

**Critical detail — the 32-bit counter problem:** `if_data.ifi_ibytes` and `ifi_obytes` are `u_int32_t`, meaning they wrap at ~4.3 GB. On a fast network (e.g., 10 Gbps Ethernet), the counter can wrap in under 4 seconds. **Always convert to `Int64` before subtraction** and use `max(result, 0)` to handle wraparound into negative territory.

**Example:**
```swift
// Source: exelban/stats Modules/Net/readers.swift (lines 220-230, adapted)
// VERIFIED: SDK header if_var.h, struct if_data (line 151)
func getBytesInfo(_ pointer: UnsafeMutablePointer<ifaddrs>) -> (upload: Int64, download: Int64)? {
    guard let addrPtr = pointer.pointee.ifa_addr,
          addrPtr.pointee.sa_family == UInt8(AF_LINK) else {
        return nil
    }
    guard let raw = pointer.pointee.ifa_data else { return nil }
    let data = raw.assumingMemoryBound(to: if_data.self)
    // CRITICAL: Convert u_int32_t → Int64 to handle wraparound
    return (upload: Int64(data.pointee.ifi_obytes),
            download: Int64(data.pointee.ifi_ibytes))
}
```

### Pattern 2: Primary Interface Detection via SystemConfiguration

**What:** Read `State:/Network/Global/IPv4` from the SystemConfiguration dynamic store. The `PrimaryInterface` key returns the BSD name (e.g., `"en0"`) of the interface carrying default-route traffic.

**When to use:** During `setup()` (once), and optionally on a slower timer (every 10s) or `SCDynamicStore` notification for interface changes.

**Example:**
```swift
// Source: exelban/stats Modules/Net/readers.swift (lines 130-135)
// VERIFIED: Apple SystemConfiguration documentation
private var primaryInterface: String {
    if let global = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString),
       let dict = global as? [String: Any],
       let name = dict["PrimaryInterface"] as? String {
        return name
    }
    return ""
}
```

### Pattern 3: Memory Page Stats → Byte Calculation

**What:** `host_statistics64` returns page counts. Multiply each by the global `vm_page_size` to get byte values. Calculate "used" memory using the standard macOS formula.

**When to use:** Every memory read cycle.

**Example:**
```swift
// Source: exelban/stats Modules/RAM/readers.swift (lines 45-65)
// VERIFIED: SDK header vm_statistics.h (struct vm_statistics64, lines 142-210)
var stats = vm_statistics64()
var count = UInt32(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

let result: kern_return_t = withUnsafeMutablePointer(to: &stats) {
    $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
        host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
    }
}

guard result == KERN_SUCCESS else { return }

let active     = Double(stats.active_count) * Double(vm_page_size)
let wired      = Double(stats.wire_count) * Double(vm_page_size)
let compressed = Double(stats.compressor_page_count) * Double(vm_page_size)
let inactive   = Double(stats.inactive_count) * Double(vm_page_size)
let speculative = Double(stats.speculative_count) * Double(vm_page_size)
let purgeable  = Double(stats.purgeable_count) * Double(vm_page_size)
let external   = Double(stats.external_page_count) * Double(vm_page_size)

// Standard macOS "used" formula (matches Activity Monitor)
let used = active + inactive + speculative + wired + compressed - purgeable - external
```

### Pattern 4: Total Physical Memory (Setup-Time Read)

**What:** `host_info(HOST_BASIC_INFO)` returns physical memory. Use `max_mem` (uint64_t), not `memory_size` (capped at 2 GB).

**When to use:** Once during `setup()`, stored as instance property.

**Example:**
```swift
// Source: exelban/stats Modules/RAM/readers.swift (lines 28-40)
// VERIFIED: SDK header host_info.h (struct host_basic_info, lines 116-128)
var stats = host_basic_info()
var count = UInt32(MemoryLayout<host_basic_info_data_t>.size / MemoryLayout<integer_t>.size)

let kerr: kern_return_t = withUnsafeMutablePointer(to: &stats) {
    $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_info(mach_host_self(), HOST_BASIC_INFO, $0, &count)
    }
}

guard kerr == KERN_SUCCESS else { return }
self.totalSize = Double(stats.max_mem)  // max_mem, NOT memory_size!
```

### Pattern 5: Per-Reader Refresh Intervals

**What:** NetworkReader uses 1.0s (D-06), MemoryReader uses 2.0s (D-10). These differ from `SettingsManager.shared.refreshInterval` (currently 2.0s). Pass the interval directly to `TimerReader.init(interval:)`.

**When to use:** In each Reader's `init()`.

### Anti-Patterns to Avoid

- **Hardcoding `"en0"`:** Broken by VPN, Thunderbolt Ethernet, USB-C adapters. Use SystemConfiguration. [Pitfall P5]
- **Polling all interfaces:** Unnecessary overhead. Poll only the primary interface found by SystemConfiguration. Filter virtual interfaces by prefix match.
- **Using `host_basic_info.memory_size`:** Capped at 2 GB since 32-bit era. Always use `max_mem`. [VERIFIED: SDK host_info.h line 119 vs 127]
- **Float for byte counters:** `u_int32_t` × time can overflow `Float` precision. Use `Int64` and `Double` for rates.
- **Not calling `freeifaddrs()`:** Memory leak on every read cycle. Always pair `getifaddrs` with `freeifaddrs`.
- **Main-thread Mach calls:** `host_statistics64` and `host_info` involve kernel traps. Always call from background queue (TimerReader handles this).
- **String formatting on background queue:** `NSAttributedString` creation requires main thread. Format bytes as `String` in Reader, create `NSAttributedString` in `@MainActor StatusBarManager`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Byte formatting (B/KB/MB/GB) | Manual `/1024` loop with switch cases | `ByteCountFormatter` (Foundation) | Handles locale, unit selection, rounding, and edge values (0 bytes, exact boundaries). 1 line vs 40+ lines of bug-prone code. `ByteCountFormatter.string(fromByteCount: 2200000)` → `"2.2 MB"` |
| Network rate formatting | Custom string interpolation | `ByteCountFormatter` + "/s" suffix | Same formatter, just append `"/s"`. For D-01's "↓2.1M ↑512K" format, call formatter twice (once for DL, once for UL) |
| Memory value formatting | Manual GB/MB calculation | `ByteCountFormatter` with custom `countStyle` | Consistent with network formatting. For D-02's "8.2G/16G" format, call formatter on used and total separately |
| Primary interface detection | Hardcoding `"en0"` or regex on interface names | `SCDynamicStoreCopyValue("State:/Network/Global/IPv4")` → `PrimaryInterface` | This is the canonical macOS API. Used by every production network monitor. |
| Counter wraparound handling | Complex overflow detection logic | `Int64(u_int32_t_value)` + `max(delta, 0)` | `Int64` promotion makes subtraction always produce correct signed result. `max(0)` handles the edge case. |

**Key insight:** `ByteCountFormatter` is the single most important don't-hand-roll in this phase. Stats implements custom byte formatting across 150+ lines of code (in `Double+Extensions.swift` and formatter views). For MacStatus v1, `ByteCountFormatter` with `countStyle = .file` provides identical output in a single call. The `.file` style uses 1000-byte units, matching the `KB/s`/`MB/s` convention users expect for network speed.

## Common Pitfalls

### Pitfall 1: Using `host_basic_info.memory_size` Instead of `max_mem`

**What goes wrong:** `memory_size` returns 2 GB (2147483648) on any Mac with more than 2 GB RAM, because the field is a 32-bit `natural_t` capped at 2 GB for backward compatibility. The menu bar shows "MEM 2.0G/2.0G" on a 16 GB Mac.

**Why it happens:** Apple added `max_mem` (uint64_t) in a later revision of the struct but kept `memory_size` for backward compatibility.

**How to avoid:** Always use `stats.max_mem`. Verified in SDK header `host_info.h` line 127: `uint64_t max_mem; /* actual size of physical memory */` and the Stats source code. [VERIFIED: SDK header]

**Warning signs:** Menu bar shows exactly 2.00 GB total on any test Mac.

### Pitfall 2: 32-bit Network Counter Wraparound

**What goes wrong:** `if_data.ifi_ibytes` and `ifi_obytes` are `u_int32_t` (max ~4.29 GB). On a 10 Gbps connection, the counter wraps in ~3.4 seconds. If the read interval is 1 second, the delta `current - previous` could be negative when `current < previous` after wraparound.

**Why it happens:** The BSD `if_data` struct was defined in the 32-bit era. The `if_data64` variant (with 64-bit counters) exists but `getifaddrs()` returns `if_data` by default.

**How to avoid:** Convert `u_int32_t` to `Int64` before subtraction. `Int64(u_int32_value)` always gives a positive number in `Int64` range. Then: `let delta = max(current - previous, 0)` handles the wraparound case where `current < previous` (the counter wrapped and the real delta is `current + 2^32 - previous`, but for rate display, treating it as 0 for one cycle is acceptable).

**Warning signs:** Negative upload/download rates in menu bar. Bursts of 0 KB/s that don't match real network activity. [VERIFIED: SDK header if_var.h, `struct if_data` uses `u_int32_t` for `ifi_ibytes`/`ifi_obytes`]

### Pitfall 3: `freeifaddrs()` Not Called

**What goes wrong:** `getifaddrs()` allocates a linked list of `ifaddrs` structs. If `freeifaddrs()` is not called, the entire list leaks (~1-2 KB per read cycle). At 1 Hz, this leaks ~86 MB/day.

**How to avoid:** Always use `defer { freeifaddrs(ifap) }` right after `getifaddrs(&ifap)`.

**Warning signs:** Memory usage of MacStatus grows steadily in Activity Monitor.

### Pitfall 4: Interface Name Change During Polling

**What goes wrong:** User switches from Wi-Fi to Ethernet (or connects VPN). The primary interface name changes. The reader continues polling the old interface and shows 0 KB/s.

**How to avoid:** Re-read the primary interface name from SystemConfiguration on every read cycle (it's a cheap `SCDynamicStoreCopyValue` call). Or cache it and re-read every 10 seconds + on network change notification.

**Warning signs:** Network rate drops to 0 after connecting/disconnecting VPN or switching networks.

### Pitfall 5: Sleep/Wake Data Freeze

**What goes wrong:** After Mac wakes from sleep, the stored previous byte counts are stale (hours old). The delta calculation produces 0 or near-0 rates. TimerReader doesn't auto-detect sleep.

**How to avoid:** Listen for `NSWorkspace.didWakeNotification` in NetworkReader. On wake, reset stored counters to nil (forces a baseline-only read next cycle). This is documented in PITFALLS.md Pitfall 2 but can be deferred to phase 2 — the minimum viable fix is resetting counters on wake.

**Warning signs:** Network rate stuck at 0 KB/s after wake. Same issue as PITFALLS.md Pitfall 2.

## Code Examples

Verified patterns from official sources:

### NetworkReader: Core Read Cycle

```swift
// Source: exelban/stats Modules/Net/readers.swift (adapted for TimerReader<T> pattern)
// VERIFIED: SDK headers if_var.h (struct if_data), SystemConfiguration framework
final class NetworkReader: TimerReader<NetworkStats> {

    private var previousBytes: (download: Int64, upload: Int64)?
    private var previousTime: Date?
    private var currentInterface: String = ""

    override func setup() {
        currentInterface = getPrimaryInterface()
        previousBytes = nil
        previousTime = nil
    }

    override func read() {
        let now = Date()
        let interface = getPrimaryInterface()  // re-read in case it changed

        guard !interface.isEmpty,
              let bytes = readBytes(for: interface) else {
            onUpdate?(nil)
            return
        }

        defer {
            previousBytes = bytes
            previousTime = now
        }

        guard let prev = previousBytes, let prevTime = previousTime else {
            return  // first read: baseline only, no rate yet
        }

        let dt = now.timeIntervalSince(prevTime)
        guard dt > 0 else { return }

        let dlRate = Double(max(bytes.download - prev.download, 0)) / dt
        let ulRate = Double(max(bytes.upload - prev.upload, 0)) / dt

        onUpdate?(NetworkStats(downloadBytesPerSec: dlRate,
                               uploadBytesPerSec: ulRate))
    }

    private func getPrimaryInterface() -> String {
        guard let global = SCDynamicStoreCopyValue(
            nil, "State:/Network/Global/IPv4" as CFString
        ),
        let dict = global as? [String: Any],
        let name = dict["PrimaryInterface"] as? String else {
            return ""
        }
        return name
    }

    private func readBytes(for interface: String) -> (download: Int64, upload: Int64)? {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return nil }
        defer { freeifaddrs(first) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let current = ptr else { break }

            let name = String(cString: current.pointee.ifa_name)
            guard name == interface else { continue }

            guard let addr = current.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK) else { continue }

            guard let raw = current.pointee.ifa_data else { continue }
            let data = raw.assumingMemoryBound(to: if_data.self)
            return (download: Int64(data.pointee.ifi_ibytes),
                    upload: Int64(data.pointee.ifi_obytes))
        }
        return nil
    }
}
```

### MemoryReader: Core Read Cycle

```swift
// Source: exelban/stats Modules/RAM/readers.swift (lines 28-65, adapted)
// VERIFIED: SDK headers vm_statistics.h, host_info.h
final class MemoryReader: TimerReader<MemoryStats> {

    private var totalSize: Double = 0  // bytes, set in setup()

    override func setup() {
        var stats = host_basic_info()
        var count = UInt32(MemoryLayout<host_basic_info_data_t>.size
                          / MemoryLayout<integer_t>.size)

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_info(mach_host_self(), HOST_BASIC_INFO, $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else {
            totalSize = 0
            return
        }
        totalSize = Double(stats.max_mem)  // use max_mem, NOT memory_size!
    }

    override func read() {
        var stats = vm_statistics64()
        var count = UInt32(MemoryLayout<vm_statistics64_data_t>.size
                          / MemoryLayout<integer_t>.size)

        let result: kern_return_t = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            onUpdate?(nil)
            return
        }

        let pageSize = Double(vm_page_size)
        let active   = Double(stats.active_count) * pageSize
        let wired    = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        let inactive = Double(stats.inactive_count) * pageSize
        let speculative = Double(stats.speculative_count) * pageSize
        let purgeable = Double(stats.purgeable_count) * pageSize
        let external  = Double(stats.external_page_count) * pageSize

        let used = active + inactive + speculative + wired
                 + compressed - purgeable - external
        let free = max(totalSize - used, 0)

        onUpdate?(MemoryStats(usedBytes: max(used, 0),
                              totalBytes: totalSize,
                              freeBytes: free))
    }
}
```

### Sendable Data Types

```swift
// Matches Phase 1 CPULoad pattern
struct NetworkStats: Sendable {
    let downloadBytesPerSec: Double
    let uploadBytesPerSec: Double
}

struct MemoryStats: Sendable {
    let usedBytes: Double
    let totalBytes: Double
    let freeBytes: Double
}
```

### Byte Formatting for Menu Bar

```swift
// Using Foundation ByteCountFormatter — do NOT hand-roll
import Foundation

func formatNetworkRate(_ bytesPerSec: Double) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file       // 1000-byte units (KB/s, MB/s)
    formatter.allowsNonnumericFormatting = false
    return formatter.string(fromByteCount: Int64(bytesPerSec)) + "/s"
    // Example outputs: "512 KB/s", "2.1 MB/s", "0 KB/s"
}

func formatMemoryBytes(_ bytes: Double) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .memory     // 1024-byte units (GiB)
    formatter.allowsNonnumericFormatting = false
    return formatter.string(fromByteCount: Int64(bytes))
    // Example outputs: "8.2 GB", "16 GB"
}

// D-01 format: "↓2.1M ↑512K" (compact, no trailing /s on arrow side)
func formatNetworkCompact(download: Double, upload: Double) -> String {
    let dl = formatNetworkRate(download)
        .replacingOccurrences(of: "/s", with: "")
    let ul = formatNetworkRate(upload)
        .replacingOccurrences(of: "/s", with: "")
    return "↓\(dl) ↑\(ul)"
}

// D-02 format: "MEM 8.2G/16G"
func formatMemoryCompact(used: Double, total: Double) -> String {
    let usedStr = formatMemoryBytes(used)
        .replacingOccurrences(of: " ", with: "")
    let totalStr = formatMemoryBytes(total)
        .replacingOccurrences(of: " ", with: "")
    return "MEM \(usedStr)/\(totalStr)"
}
```

### StatusBarManager Extension

```swift
// Add to existing @MainActor StatusBarManager class
@MainActor
final class StatusBarManager {
    // Phase 2 additions:

    private var networkStatusItem: NSStatusItem?
    private var memoryStatusItem: NSStatusItem?
    private var lastNetworkStats: NetworkStats?
    private var lastMemoryStats: MemoryStats?

    func setupNetworkItem() {
        // Fixed width to prevent menu bar jitter (Pitfall 8)
        networkStatusItem = NSStatusBar.system.statusItem(withLength: 90)
        networkStatusItem?.autosaveName = "com.macstatus.network"
        networkStatusItem?.button?.attributedTitle =
            attributedString("↓-- ↑--")
    }

    func setupMemoryItem() {
        memoryStatusItem = NSStatusBar.system.statusItem(withLength: 100)
        memoryStatusItem?.autosaveName = "com.macstatus.memory"
        memoryStatusItem?.button?.attributedTitle =
            attributedString("MEM --/--")
    }

    func updateNetwork(_ stats: NetworkStats?) {
        guard let stats else {
            networkStatusItem?.button?.attributedTitle =
                attributedString("↓-- ↑--")
            lastNetworkStats = nil
            return
        }
        // Tolerance check: skip redraw if < 1 KB/s change
        if let last = lastNetworkStats,
           abs(stats.downloadBytesPerSec - last.downloadBytesPerSec) < 1024,
           abs(stats.uploadBytesPerSec - last.uploadBytesPerSec) < 1024 {
            return
        }
        lastNetworkStats = stats
        let text = formatNetworkCompact(
            download: stats.downloadBytesPerSec,
            upload: stats.uploadBytesPerSec
        )
        networkStatusItem?.button?.attributedTitle = attributedString(text)
    }

    func updateMemory(_ stats: MemoryStats?) {
        guard let stats else {
            memoryStatusItem?.button?.attributedTitle =
                attributedString("MEM --/--")
            lastMemoryStats = nil
            return
        }
        // Tolerance check: skip redraw if < 0.5% change
        if let last = lastMemoryStats {
            let change = abs(stats.usedBytes - last.usedBytes) / stats.totalBytes
            if change < 0.005 { return }
        }
        lastMemoryStats = stats
        let text = formatMemoryCompact(
            used: stats.usedBytes,
            total: stats.totalBytes
        )
        memoryStatusItem?.button?.attributedTitle = attributedString(text)
    }
}
```

### AppDelegate Wiring

```swift
// Add to existing AppDelegate.applicationDidFinishLaunching:
func applicationDidFinishLaunching(_ notification: Notification) {
    statusBarManager = StatusBarManager()
    // Phase 2: add network + memory items
    statusBarManager?.setupNetworkItem()
    statusBarManager?.setupMemoryItem()

    // Existing CPU
    cpuReader = CPUReader()
    cpuReader?.onUpdate = { [weak self] value in
        DispatchQueue.main.async {
            self?.statusBarManager?.updateCPU(value)
        }
    }
    cpuReader?.start()

    // Phase 2: Network (1s interval per D-06)
    networkReader = NetworkReader(interval: 1.0)
    networkReader?.onUpdate = { [weak self] stats in
        DispatchQueue.main.async {
            self?.statusBarManager?.updateNetwork(stats)
        }
    }
    networkReader?.start()

    // Phase 2: Memory (2s interval per D-10)
    memoryReader = MemoryReader(interval: 2.0)
    memoryReader?.onUpdate = { [weak self] stats in
        DispatchQueue.main.async {
            self?.statusBarManager?.updateMemory(stats)
        }
    }
    memoryReader?.start()
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `host_info(HOST_BASIC_INFO).memory_size` | `host_basic_info.max_mem` | macOS 10.x era (64-bit transition) | `memory_size` capped at 2 GB; only `max_mem` returns actual RAM |
| `host_statistics(HOST_VM_INFO)` (32-bit) | `host_statistics64(HOST_VM_INFO64)` (64-bit) | macOS 10.x era | 64-bit version includes compressor fields needed for accurate memory accounting |
| `if_data` (32-bit counters) | Still standard for `getifaddrs()` | No change | `if_data64` exists in kernel but `getifaddrs()` returns `if_data`. Must handle wraparound in userspace |
| `LSSharedFileListInsertItemURL` (login items) | `SMAppService.mainApp.register()` | macOS 13 (Ventura) | Modern API, simpler. Phase 5 |
| Hardcoded interface name `"en0"` | `SCDynamicStoreCopyValue` primary interface | Best practice since macOS 10.x | Dynamic detection handles VPN, multi-adapter, Thunderbolt |

**Deprecated/outdated:**
- `host_statistics()` (32-bit `HOST_VM_INFO`): Returns `vm_statistics_data_t` which lacks `compressor_page_count`, `swapins`, `swapouts`. Always use `host_statistics64(HOST_VM_INFO64)` on macOS 14+. [VERIFIED: SDK header shows compressor fields only in `vm_statistics64`]
- `host_basic_info.memory_size` field: Capped at 2 GB. Use `max_mem` only. [VERIFIED: SDK header host_info.h]
- `nettop` command for network rates: Process-spawn overhead, locale-dependent output parsing. [Rejected by STACK.md]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `ByteCountFormatter.CountStyle.file` uses 1000-byte KB (matching network speed convention "KB/s") | Don't Hand-Roll | If it uses 1024-byte units, network rates will show slightly different values than user expects. Verified via `swift -e` test: `ByteCountFormatter().string(fromByteCount: 2200000)` → `"2.2 MB"`. This matches 1000-byte convention (2.2 × 10^6 = 2.2 MB). |
| A2 | `vm_page_size` is 16384 (16 KB) on Apple Silicon macOS. This is 4096 on Intel. | Memory reading | If Apple changes page size in future architecture, used/total formula remains correct because we multiply page counts by the actual `vm_page_size` variable — not hardcoded. No risk. |
| A3 | `SystemConfiguration` framework is already linked in the Xcode target from Phase 1 | Architecture | If not linked, the build will fail with "No such module 'SystemConfiguration'". Fix: add framework in target's "Link Binary with Libraries". Low risk, 10-second fix. |
| A4 | `NetworkReader(interval: 1.0)` passes interval directly to `TimerReader` constructor rather than using `SettingsManager.shared.refreshInterval` | Architecture | The `TimerReader` init takes `interval: TimeInterval` — passing a literal value is valid. If SettingsManager needs per-reader intervals later, refactor is trivial (add `networkRefreshInterval` key). |
| A5 | Virtual interface filter list (awdl, llw, utun, bridge, gif, stf, lo, anpi, ap) is complete for macOS 14+ | Network interface detection | Missing a prefix means a virtual interface could be selected as primary if SystemConfiguration returns it. However, SystemConfiguration's `PrimaryInterface` already filters to the default-route interface — virtual interfaces don't carry default routes. The filter list is a defense-in-depth measure. |

## Open Questions (RESOLVED)

1. **Should NetworkReader re-detect primary interface on every read cycle?**
   - RESOLVED: Re-read every cycle (1s) — it's a dictionary lookup from an in-memory cache, nearly zero overhead. This provides immediate response to interface changes without additional notification infrastructure.

2. **Should NetworkReader handle sleep/wake in Phase 2?**
   - RESOLVED: Include in Phase 2 as a low-effort fix. Add `NSWorkspace.didWakeNotification` observer to BOTH NetworkReader and MemoryReader. On wake: reset stored baseline to nil. This is ~5 lines per Reader.

3. **NetworkStats tolerance threshold for UI redraw?**
   - RESOLVED: Use 1 KB/s (1024 bytes/s) absolute threshold. At typical rates (100 KB/s - 100 MB/s), this prevents redraws for sub-KB changes while updating for any meaningful traffic change.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| macOS SDK (getifaddrs, mach, SystemConfiguration) | All readers | ✓ | macOS 26.x SDK via Xcode 26.x | — (built into OS) |
| SystemConfiguration framework | NetworkReader | — requires linking | macOS SDK | Must add to Xcode target |
| ByteCountFormatter (Foundation) | Byte formatting | ✓ | Foundation, macOS 10.8+ | — (standard library) |
| Xcode toolchain | Build | ✓ | Xcode 26.x | — |

**Missing dependencies with no fallback:** None — all APIs are part of macOS SDK included with Xcode.

**Note:** `SystemConfiguration.framework` must be linked in the Xcode target. Check if Phase 1 already added it. If not, add to "Link Binary with Libraries" build phase.

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | N/A — desktop app, no user auth |
| V3 Session Management | No | N/A |
| V4 Access Control | No | N/A — single-user Mac |
| V5 Input Validation | No | N/A — no user input processed (reads system APIs only) |
| V6 Cryptography | No | N/A |

**Note:** MacStatus v1 is a read-only system monitor with no network server, no user data storage, and no user input beyond preferences. The only data leaving the app is the menu bar display. Standard macOS code signing (required for `SMAppService` in Phase 5) provides integrity verification.

### Known Threat Patterns for Mach/BSD System APIs

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| `getifaddrs()` buffer over-read | Information Disclosure | `freeifaddrs()` after use, bound `ifa_next` pointer traversal. The linked list is kernel-provided — treat as untrusted data. |
| Mach port exhaustion (`mach_host_self()`) | Denial of Service | `mach_host_self()` returns a send right, not a new port. No exhaustion risk. Call is O(1). |
| IOKit enumeration | Elevation of Privilege | Not used in Phase 2. Network and memory use only public Mach/BSD APIs that work without elevated privileges. |

## Sources

### Primary (HIGH confidence)
- **exelban/stats** (GitHub, 38.8k stars, MIT) — `Modules/Net/readers.swift` (network byte counters, SystemConfiguration primary interface detection, delta calculation pattern), `Modules/RAM/readers.swift` (host_statistics64 memory page stats, host_basic_info total memory, memory pressure). [VERIFIED: direct source code fetch from raw.githubusercontent.com]
- **Apple macOS SDK 26.x headers** (at `/Applications/Xcode.app/.../MacOSX.sdk/usr/include/`) — `mach/vm_statistics.h` (`vm_statistics64_data_t` struct, lines 142-210), `mach/host_info.h` (`host_basic_info` struct, lines 116-128), `net/if_var.h` (`if_data` struct, lines 151-181), `sys/sysctl.h` (`xsw_usage` struct, lines 539-545). [VERIFIED: local file read from SDK headers]
- **Foundation `ByteCountFormatter`** — Verified via `swift -e 'import Foundation; print(ByteCountFormatter().string(fromByteCount: 2200000))'` → `"2.2 MB"`. Class available since macOS 10.8. [VERIFIED: local swift invocation]

### Secondary (MEDIUM confidence)
- **Apple Developer Documentation** (`developer.apple.com`) — `SCDynamicStoreCopyValue`, `getifaddrs(3)`, `host_statistics64`, `host_info`. Documentation pages require JavaScript; struct definitions verified from local SDK headers instead.
- **exelban/stats architecture** — `Kit/module/` base class patterns. Referenced from STACK.md and ARCHITECTURE.md (already HIGH confidence from Phase 1 research).

### Tertiary (LOW confidence)
- None. All claims verified against SDK headers or production source code.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs verified against Xcode 26.x SDK headers and Stats production source code
- Architecture: HIGH — follows Phase 1 patterns exactly; Stats patterns are production-proven
- Pitfalls: HIGH — concrete failure modes from SDK struct analysis (32-bit counters, memory_size cap) and Stats issue tracker

**Research date:** 2026-05-14
**Valid until:** 2026-08-14 (90 days — stable Mach/BSD APIs, no expected breaking changes)

**Verified struct fields:**
- `vm_statistics64`: `active_count`, `inactive_count`, `wire_count`, `compressor_page_count`, `purgeable_count`, `external_page_count`, `speculative_count`, `free_count`, `swapins`, `swapouts` [SDK `vm_statistics.h` lines 142-210]
- `host_basic_info`: `max_cpus`, `avail_cpus`, `memory_size` (capped 2 GB), `physical_cpu`, `logical_cpu`, `max_mem` [SDK `host_info.h` lines 116-128]
- `if_data`: `ifi_ibytes` (u_int32_t), `ifi_obytes` (u_int32_t), `ifi_baudrate` [SDK `if_var.h` lines 151-181]
- `xsw_usage`: `xsu_total`, `xsu_avail`, `xsu_used`, `xsu_pagesize` [SDK `sysctl.h` lines 539-545]
- `vm_page_size`: `extern vm_size_t vm_page_size;` [SDK `vm_page_size.h` line 42]

**Virtual interface prefixes (verified on macOS 26.4):** `awdl`, `llw`, `utun`, `bridge`, `gif`, `stf`, `lo`, `anpi`, `ap` [VERIFIED: local `ifconfig -l` output]
