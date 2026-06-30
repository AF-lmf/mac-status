# Phase 13: Safe Fan Control Gate & Write Path — Research

**Researched:** 2026-06-26
**Domain:** AppleSMC write path, privilege model, Ftst unlock, FanControlManager architecture, SwiftUI opt-in gate
**Confidence:** MEDIUM-HIGH (write-mechanism section HIGH from cross-verified sources; Apple Silicon Ftst sequence MEDIUM — documented by independent research projects but untested on Mac15,9 locally)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Manual fan control is OFF by default; system auto control is always the baseline. The master opt-in is a new Settings toggle (`风扇手动控制`, default off), reusing `SettingsManager` UserDefaults toggle + `.settingsDidChange` live-reapply pattern.
- **D-02:** First enable shows a one-time explicit risk-confirmation dialog: hardware risk explanation, target clamping promise, restore-on-failure/exit promise. Explicit confirm required; cancel leaves system auto.
- **D-03:** One-time consent: after the first confirmation, re-entering manual mode does NOT re-prompt. Control affordance lives inside the existing `温度与风扇` popover section; current mode and one-click restore always visible while manual mode is active.
- **D-04:** If `FanCapabilities.safeControlAvailable == false`, the opt-in toggle is NOT offered at all (hidden, not disabled).
- **D-05:** Primary input is a slider bounded to the live hardware min/max. Target RPM renders as a read-only numeric label using the Phase 12 fixed-width, right-aligned, monospaced value column.
- **D-06:** No free-form numeric text entry as primary control. The slider is the source of truth.
- **D-07:** Single unified target applied to all fans (clamped per-fan against each fan's own live min/max). Per-fan independent control is deferred.
- **D-08:** Every control action (enter manual / set target / restore auto) writes via the restricted control component, then reads back mode + target RPM + current RPM. UI shows "手动已生效" only after read-back confirms expected mode and target. IOKit "success" return alone is not trusted.
- **D-09:** Read-back reuses the existing read path for `FS! ` / `F{i}Md` / `F{i}Tg` / `F{i}Ac`. Mode and target must match exactly; current RPM may be within a ramp tolerance.
- **D-10:** Write fail or read-back disagreement → immediately attempt restore auto, revert UI, show inline `控制未生效，已恢复自动`. No modal, no spam.
- **D-11:** One-click "恢复系统自动控制" always present while manual mode is engaged; restore also read-back verified.
- **D-12:** Decision-gate fail-closed: if write/read-back/restore cannot be proven safe and recoverable on hardware, manual-control path stays unavailable (toggle hidden). Read-only thermal+fan monitoring continues.
- **D-13:** Research MUST first determine whether SMC fan-control writes succeed in-process WITHOUT root. If root-less writes work and read-back verifies → single-process model. (Research answer: NO — root is required. See headline conclusion below.)
- **D-14:** If writes require root → privileged helper (SMAppService daemon + XPC, one-time admin authorization) is acceptable. Helper must expose only high-level bounded actions (`setManualTarget(rpm:)`, `restoreAutoControl()`), never raw-key passthrough.
- **D-15:** Fail-closed always wins. If neither root-less write nor verifiable helper path can be proven safe + recoverable, ship read-only.
- **D-16:** All raw SMC writes are centralized in a restricted control component/helper, separate from the existing read-only `SMCReader`.

### Claude's Discretion
- Exact type names and file splits.
- Final in-process-vs-helper decision (gated on this research; research says: helper required).
- Read-back tolerance thresholds (planner sets exact values).
- Precise Chinese copy for new UI elements, as long as locked safety invariants hold: default-auto, explicit opt-in, clamp-to-live-bounds, read-back-before-success, always-available verified restore, centralized writes, and fail-closed.

### Deferred Ideas (OUT OF SCOPE)
- Per-fan independent manual targets.
- Lifecycle recovery on quit/sleep/wake/rollback/capability re-probe (FCTRL-05) → Phase 14.
- Real-hardware UAT sign-off and full unsupported/failure-state UI matrix (UAT-01/02/03) → Phase 14.
- Auto fan curves, temperature-driven scheduling, profiles, silent/low-noise modes, below-floor control, remote control, raw SMC key browser.
- Free-form numeric RPM entry as primary input.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FCTRL-01 | User must explicitly opt-in to manual fan control; system auto control is always the default. | D-01..D-04 locked decisions; Settings toggle pattern from SettingsManager; safeControlAvailable gate from FanReader |
| FCTRL-02 | Manual RPM target must be clamped to live hardware min/max; cannot go below Apple default floor or set silent mode. | Hardware probe confirms F{i}Mn/F{i}Mx readable on Mac15,9; clamp logic at FanControlManager layer |
| FCTRL-03 | Every fan-control write must read-back mode + target + current RPM; IOKit success alone is not trusted. | Verified by ecosystem research: "write returned success" trap documented in PITFALLS.md and stats issue #2928; SMC-level result byte (output struct field) must be checked |
| FCTRL-04 | One-click restore to system auto control, read-back verified. | Restore sequence: write F{i}Md=0 + Ftst=0 via helper, read-back F{i}Md=auto, then confirm UI |
| FCTRL-06 | Fan control writes centralized in restricted control component / helper; SwiftUI views call only high-level intent actions. | Architecture: FanControlManager (D-16); XPC protocol exposes only setManualTarget/restoreAutoControl |
</phase_requirements>

---

## Summary

Phase 13 opens the first SMC write path in MacStatus. The critical architectural question (D-13) is now resolved by research: **SMC fan-control writes require root and cannot succeed from the regular in-process user-client on Apple Silicon/macOS Sequoia.** This makes the SMAppService-daemon + XPC helper architecture mandatory, not optional.

Every production fan-control tool on macOS (Stats/exelban, ThermalForge, AlDente, Macs Fan Control, smctl, macos-smc-fan) uses a privileged root daemon to write SMC keys, either via the older `SMJobBless` pattern or the modern `SMAppService.daemon` pattern. Direct in-process writes return `kIOReturnNotPrivileged (0xe00002c2)` without root, and on M3+ chips `thermalmonitord` additionally enforces System Mode (mode 3), requiring the `Ftst=1` unlock sequence before mode writes are accepted by firmware.

The project already imports `ServiceManagement` and uses `SMAppService.mainApp` for the login-item feature. The privileged-helper path is a natural extension using the same framework.

**Primary recommendation:** Implement a minimal `SMAppService.daemon` + XPC helper (`FanControlHelper`) that exposes only two high-level operations: `setManualTarget(rpm:)` and `restoreAutoControl()`. All write logic lives in the helper; the main app calls only the XPC protocol. `FanControlManager` (main-app layer, `@MainActor`) owns the state machine, calls the XPC helper, performs read-back verification using the existing `FanReader` / `SMCReader` read path, and updates `DashboardState`. If the helper path cannot be registered or verified, `safeControlAvailable` stays `false` and the toggle stays hidden.

---

## HEADLINE CONCLUSION: Write Mechanism (D-13)

**Root-less in-process SMC writes: NOT POSSIBLE on Apple Silicon / macOS Sequoia.**

| Finding | Evidence | Confidence |
|---------|----------|------------|
| SMC command `6` (write) via `IOConnectCallStructMethod(selector:2)` returns `kIOReturnNotPrivileged` from unprivileged process | macos-smc-fan research docs: "writes to restricted keys return `kIOReturnNotPrivileged` unless process runs as root" | HIGH [CITED: github.com/agoodkind/macos-smc-fan/docs/research.md] |
| The permission asymmetry is at firmware level, not IOKit-connection level — same `IOServiceOpen` call is used for both reads and writes | macos-smc-fan research: "both reads and writes use identical `IOServiceOpen` params; permission asymmetry doesn't originate at the IOKit connection level" | HIGH [CITED: github.com/agoodkind/macos-smc-fan/docs/research.md] |
| All production fan-control tools (Stats, ThermalForge, AlDente, Macs Fan Control, smctl, macos-smc-fan) use a privileged helper daemon for SMC writes | Cross-verified across multiple projects | HIGH [VERIFIED by cross-source] |
| On M3/M4+, `thermalmonitord` enforces System Mode (mode 3) and blocks direct fan mode writes at firmware level (RTKit returns `0x82 SmcBadCommand`) even if root | stats issue #2928; macos-smc-fan research | MEDIUM [CITED: github.com/exelban/stats/issues/2928] |
| The `Ftst=1` unlock sequence is required before `F{i}Md` mode writes succeed on Apple Silicon: write Ftst=1, wait 3–6 seconds for `thermalmonitord` polling cycle to yield, then write F{i}Md=1 | macos-smc-fan research; stats codebase | MEDIUM [CITED: github.com/agoodkind/macos-smc-fan/docs/research.md] |
| Mac15,9 (M3 Max) has readable `F{i}Md` (type `ui8`, value `0x00`) and absent `FS! ` key — mode key casing is uppercase `Md` on this generation | Phase 11 hardware probe at 11-HARDWARE-PROBE.md | HIGH [VERIFIED: local probe] |
| `FS! ` key reads as nil on Mac15,9 | Phase 11 hardware probe | HIGH [VERIFIED: local probe] |

**Architecture decision (D-13 answer):** Use SMAppService daemon + XPC helper. Root-less in-process write is not viable. The fail-closed fallback (D-15) is shipping read-only if the helper cannot be registered or verified.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| SMC fan key writes (F{i}Md, F{i}Tg, Ftst) | Privileged Helper Daemon | — | Root required; firmware-level permission check |
| XPC protocol / bounded intent API | Main App (FanControlManager) | Helper (server side) | Thin bounded interface; no raw-key passthrough |
| Read-back verification (F{i}Md, F{i}Tg, F{i}Ac) | Main App (FanControlManager via FanReader/SMCReader) | — | Reads need no root; existing path is authoritative |
| Fan control state machine (manual/auto/pending/failed) | Main App (FanControlManager @MainActor) | — | Single actor; drives DashboardState |
| Opt-in gate & consent dialog | Main App (SwiftUI / SettingsView) | SettingsManager | UserDefaults toggle, one-time dialog |
| RPM slider + target display | Main App (DashboardView / FanSectionView) | — | High-level SwiftUI only; never touches raw SMC |
| Hardware capability gate (safeControlAvailable) | FanReader / FanCapabilities | — | Flip only after helper verified + keys confirmed |
| Admin authorization (one-time) | macOS SMAppService (System Settings > Login Items) | — | User enables in System Settings; no password prompt at launch |

---

## Standard Stack

### Core (No new dependencies — pure macOS system frameworks)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `IOKit` (system) | macOS 13+ | SMC read path (existing) — unchanged | Already in use by SMCReader |
| `ServiceManagement` | macOS 13+ | SMAppService.daemon registration; already imported in SettingsManager.swift | Apple's modern privileged-helper API; replaces deprecated SMJobBless |
| `Foundation` / XPC | macOS 13+ | NSXPCConnection, NSXPCInterface for helper communication | System-provided; no third-party dependency |
| `SwiftUI` | macOS 13+ | Opt-in toggle, slider, mode indicator, restore button (existing views extended) | Already in use throughout the app |

**No new external packages.** The entire Phase 13 implementation uses only Apple system frameworks already present in the project.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SMAppService.daemon | SMJobBless | SMJobBless is deprecated since macOS 13; SMAppService is the current Apple-endorsed API; the project already uses SMAppService.mainApp |
| NSXPCConnection | CFMessagePort / Mach port directly | NSXPCConnection is the modern, safer Swift-native XPC abstraction; Mach ports require more boilerplate and have no Swift-native protocol support |
| In-process helper stub (single binary) | Separate helper binary | Separate helper binary is required: the helper must run as root (LaunchDaemon), which requires a different process context from the sandboxed/ad-hoc main app |

### Package Legitimacy Audit

> No external packages to install. This phase uses only Apple system frameworks (IOKit, ServiceManagement, Foundation, SwiftUI). Package legitimacy audit: SKIPPED (no third-party packages).

---

## Architecture Patterns

### System Architecture Diagram

```
[DashboardView / FanSectionView]
  | (high-level intent: setManualTarget, restoreAutoControl)
  v
[FanControlManager @MainActor]  ←→  [FanReader / SMCReader (read-only)]
  |   (XPC call)                         ^ (read-back verification)
  v
[NSXPCConnection]
  |
  v
[FanControlHelper daemon (root / LaunchDaemon)]
  |   (IOConnectCallStructMethod cmd=6)
  v
[AppleSMC IOKit user-client]
  |
  v
[SMC firmware / thermalmonitord]
```

**Key data flows:**
1. User drags slider → SwiftUI calls `FanControlManager.setManualTarget(rpm:)` on @MainActor
2. `FanControlManager` clamps RPM to live hardware bounds → sends `setManualTarget(clampedRPM:)` via NSXPCConnection
3. Helper (root) executes: write `Ftst=1`, wait for thermalmonitord yield (~3–6 s), write `F{i}Md=1` + `F{i}Tg`, write `Ftst=0`
4. Helper returns success/failure to main app
5. `FanControlManager` reads back via `FanReader` / `SMCReader` (no root needed): checks `F{i}Md`, `F{i}Tg`, `F{i}Ac`
6. If read-back confirms → `DashboardState.fanControlState = .manualVerified`; UI shows "手动已生效"
7. If read-back fails → call `restoreAutoControl()` via helper; revert UI

### Recommended Project Structure

```
MacStatus/MacStatus/
├── Control/
│   ├── FanControlManager.swift     # @MainActor state machine; XPC client; read-back logic
│   └── FanControlProtocol.swift    # NSXPCInterface-compatible protocol (Objective-C compatible)
├── FanControlHelper/               # Separate target in .xcodeproj
│   ├── main.swift                  # Helper entry point; NSXPCListener
│   ├── FanControlHelperImpl.swift  # Implements FanControlProtocol; runs as root
│   ├── SMCWriter.swift             # Raw SMC write primitives + Ftst unlock sequence
│   └── Info.plist                  # Helper bundle info
├── Resources/
│   └── LaunchDaemons/
│       └── com.macstatus.fancontrolhelper.plist  # LaunchDaemon plist (embedded in app bundle)
├── Readers/
│   ├── SMCReader.swift             # UNCHANGED — read-only
│   └── FanReader.swift             # UNCHANGED except: flip safeControlAvailable=true on Mac15,9 after helper verified
├── UI/Views/
│   └── DashboardView.swift         # Add fan control affordance inside 温度与风扇 section
└── Utils/
    └── SettingsManager.swift       # Add manualFanControlEnabled toggle (default false) + hasConfirmedFanRisk (default false)
```

### Pattern 1: SMAppService Daemon Registration

**What:** Register a LaunchDaemon using SMAppService (macOS 13+). The daemon plist lives in `Contents/Library/LaunchDaemons/`. User approves once in System Settings > Login Items (no password prompt needed, but admin approval required).

**When to use:** Any time the main app needs to perform a privileged operation (SMC write, hardware control). The daemon persists across app launches.

```swift
// Source: Apple Developer Documentation — SMAppService
import ServiceManagement

// Registration (call on first manual-control enable)
let service = SMAppService.daemon(plistName: "com.macstatus.fancontrolhelper.plist")
do {
    try service.register()
    // Status may be .requiresApproval — direct user to System Settings
} catch {
    // Registration failed; keep safeControlAvailable = false
}

// Check status before each use
switch service.status {
case .enabled:
    // Daemon is running; proceed with XPC
case .requiresApproval:
    // Show user message: "请在 系统设置 > 登录项 中允许 MacStatus 风扇控制"
case .notRegistered, .notFound:
    // Fall back to read-only mode
@unknown default:
    break
}
```

**Important:** `SMAppService.daemon` requires the plist to declare `MachServices` for XPC (not `UserName: root` alone). The helper binary must be in `Contents/Library/HelperTools/`. [CITED: developer.apple.com/documentation/servicemanagement/smappservice]

### Pattern 2: XPC Bounded Interface (FanControlProtocol)

**What:** Define a thin Objective-C-compatible protocol for the XPC interface. This is the only API surface the helper exposes — no raw SMC key passthrough.

```swift
// Source: [ASSUMED] — standard NSXPCInterface pattern; no library-specific API
// FanControlProtocol.swift (shared between main app and helper targets)
import Foundation

@objc protocol FanControlProtocol {
    /// Set all fans to manual mode at the specified target RPM.
    /// Performs: Ftst=1 unlock, F{i}Md=1, F{i}Tg=target, Ftst=0.
    /// Reply: success=true if SMC write sequence succeeded at firmware level.
    func setManualTarget(
        rpm: UInt16,
        reply: @escaping (_ success: Bool, _ smcResultCode: Int32) -> Void
    )

    /// Restore system automatic fan control.
    /// Performs: F{i}Md=0, Ftst=0.
    /// Reply: success=true if mode confirmed auto.
    func restoreAutoControl(
        reply: @escaping (_ success: Bool) -> Void
    )
}
```

**Caller (FanControlManager, main app):**
```swift
// Source: [ASSUMED] — standard NSXPCConnection pattern
@MainActor
final class FanControlManager {
    private var connection: NSXPCConnection?

    private func helperConnection() -> NSXPCConnection {
        let c = NSXPCConnection(machServiceName: "com.macstatus.fancontrolhelper",
                                options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: FanControlProtocol.self)
        c.resume()
        return c
    }

    func setManualTarget(rpm: Double, latestSnapshot: FanSnapshot) async -> FanControlResult {
        let clamped = clamp(rpm, snapshot: latestSnapshot)
        let conn = helperConnection()
        defer { conn.invalidate() }

        return await withCheckedContinuation { continuation in
            let proxy = conn.remoteObjectProxyWithErrorHandler { err in
                continuation.resume(returning: .helperError(err))
            } as? FanControlProtocol

            proxy?.setManualTarget(rpm: UInt16(clamped)) { success, code in
                continuation.resume(returning: success ? .writeSucceeded : .writeFailed(code: code))
            }
        }
    }
}
```

### Pattern 3: SMC Write Sequence (Helper Side — Ftst Unlock)

**What:** The write sequence the helper must perform to override `thermalmonitord` on Apple Silicon (M3 and later).

**When to use:** Every `setManualTarget` call on Apple Silicon. The `FS! ` key is absent on Mac15,9; use `F{i}Md` (uppercase `Md`) directly.

```swift
// Source: [CITED: github.com/agoodkind/macos-smc-fan/docs/research.md]
// SMCWriter.swift (helper target only — runs as root)

// STEP 1 — Unlock: inhibit thermalmonitord reclaim
try smcWrite(key: "Ftst", value: UInt8(1))

// STEP 2 — Wait for thermalmonitord polling cycle to yield (~3–6 s)
// thermalmonitord polls at ~4000ms idle, ~250ms under load.
// Use a retry loop with 100ms interval, 10s timeout, checking F{i}Md transitions from 3 → 0
var unlocked = false
let deadline = Date().addingTimeInterval(10)
while Date() < deadline {
    let mode = try smcReadUI8(key: "F0Md")
    if mode != 3 { unlocked = true; break }
    Thread.sleep(forTimeInterval: 0.1)
}
guard unlocked else { throw FanControlError.unlockTimeout }

// STEP 3 — Write mode=1 (manual) and target RPM
try smcWrite(key: "F0Md", value: UInt8(1))
try smcWrite(key: "F1Md", value: UInt8(1))
try smcWrite(key: "F0Tg", floatRPM: targetRPM)
try smcWrite(key: "F1Tg", floatRPM: targetRPM)

// STEP 4 — Release: let thermalmonitord resume oversight (safety)
// NOTE: Ftst=0 re-enables thermalmonitord reclaim; the helper keeps Ftst=1
// active only during the write window, then releases it.
try smcWrite(key: "Ftst", value: UInt8(0))
```

**For restore to auto:**
```swift
// Source: [CITED: github.com/agoodkind/macos-smc-fan/docs/research.md]
try smcWrite(key: "F0Md", value: UInt8(0))  // 0 = auto
try smcWrite(key: "F1Md", value: UInt8(0))
try smcWrite(key: "Ftst", value: UInt8(0))  // ensure unlock released
```

### Pattern 4: Read-Back Verification (Main App Side)

**What:** After helper reports write succeeded, main app reads back using the existing read-only path to confirm hardware state.

```swift
// Source: [ASSUMED] — derives from D-08, D-09 locked decisions and existing FanReader patterns
@MainActor
func verifyManualMode(targetRPM: Double, snapshot: FanSnapshot) async -> Bool {
    // Wait a brief moment for mode to settle (fans need ramp time)
    try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 s initial settle

    let verifySnapshot = fanReader.readValue()

    for fan in verifySnapshot.fans {
        // Mode must be manual (F{i}Md = 1 confirmed via FanReader diagnosticReadings)
        // Target must match within ±1 RPM (exact type match for flt encoding)
        // Current RPM is allowed to be within a ramp tolerance (±15% or ±200 RPM, whichever is larger)
        guard verifyModeManual(fan) else { return false }
        guard let target = fan.targetRPM, abs(target - targetRPM) <= 1.0 else { return false }
    }
    return true
}
```

**Read-back tolerance guidance (for planner to finalize):**
- Mode (`F{i}Md`): must be exactly `1` (manual). No tolerance.
- Target (`F{i}Tg` as `flt`): must match written value within ±1 RPM (encoding round-trip).
- Current (`F{i}Ac`): allow up to 15% deviation from target OR ±200 RPM, whichever is larger. Fans take 5–15 s to ramp to a new target; read-back should not wait that long, so current RPM check is advisory rather than blocking.

### Anti-Patterns to Avoid

- **IOKit-success-only check:** Writing to F{i}Md and checking only that `IOConnectCallStructMethod` returned `kIOReturnSuccess`. The SMC output struct has a separate `result` byte; firmware rejections (SmcBadCommand `0x82`) appear there, not in the IOKit return code. Always inspect `output.result`.
- **Skipping Ftst on Apple Silicon:** Writing F{i}Md=1 directly without the Ftst=1 unlock on M3+ results in a silent no-op or SmcBadCommand. The mode key reads back as if it changed but `thermalmonitord` restores mode=3 within its next polling cycle (~250–4000 ms).
- **Persisting manual RPM target in UserDefaults for auto-apply on next launch:** A persisted target can be applied on a fresh launch while the user has no manual-mode intention, silently overriding thermalmonitord. Phase 13 must NOT auto-apply any persisted target; Phase 14 handles lifecycle recovery.
- **Letting SwiftUI views talk directly to the helper:** Views must call only `FanControlManager` high-level methods. The XPC connection must never be exposed to the view layer.
- **Assuming FS!  is available on Mac15,9:** Hardware probe confirmed `FS! ` reads as nil on this hardware. Do not use `FS! ` — use `F{i}Md` exclusively.
- **Main-actor blocking during Ftst retry loop:** The 3–6 s retry loop runs inside the helper (root daemon), not on the main app. The XPC reply is async. Never put a `Thread.sleep` or blocking loop on @MainActor or in a SwiftUI button action.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Privileged execution | Custom setuid binary or `AuthorizationExecuteWithPrivileges` | SMAppService.daemon + XPC | Deprecated / insecure; SMAppService is Apple's current supported API |
| XPC boilerplate | Custom Mach port message loop | NSXPCConnection + NSXPCInterface | Swift-native, type-safe, automatic memory management |
| SMC write encoding for `ui8` | Custom byte-packing | Use same SMCParamStruct + cmd=6 pattern as existing SMCReader, with `data8 = cmdWriteKey` | The 80-byte ABI guard is already in SMCReader; the write command uses the same struct |
| Ftst unlock timing | `usleep` guess | Documented retry loop with F{i}Md mode transition detection | Timing varies by thermal load; polling is the correct approach |

**Key insight:** The SMC write ABI uses the same `SMCParamStruct` (80-byte layout, same `IOConnectCallStructMethod` selector 2) as reads. The only difference is: `data8 = cmdWriteKey` (6 instead of 5), the bytes field is populated with the value to write, and `keyInfo.dataSize` + `keyInfo.dataType` must be set. This means the helper's `SMCWriter` is a small addition to the existing struct layout — it does not need to duplicate the ABI.

---

## Common Pitfalls

### Pitfall 1: thermalmonitord overrides write immediately on M3+

**What goes wrong:** Helper writes `F0Md=1`, IOKit returns success, SMC firmware accepts it. But within the next thermalmonitord polling cycle (250–4000 ms) the daemon writes `F0Md=3` (System Mode), overriding the change. UI shows "手动已生效" prematurely.

**Why it happens:** The Ftst=1 unlock was not applied, or was released before the target RPM was written, or the unlock window was too short.

**How to avoid:** Keep Ftst=1 active for the entire write sequence (Ftst=1 → mode write → target write → Ftst=0). Read-back verification in the main app must wait 500 ms before reading mode, to survive one thermalmonitord polling cycle.

**Warning signs:** `F{i}Md` reads as `3` immediately after the helper reports success; `F{i}Ac` does not move toward target after 5–10 seconds.

### Pitfall 2: FS!  key absent on Mac15,9

**What goes wrong:** Code tries to write `FS! ` to set force-mode bitmask. The write fails silently (key not present), and mode is never changed. UI says "手动已生效" because the code only checks `FS! ` write result, not `F{i}Md`.

**Why it happens:** Intel-era fan control used `FS! ` (16-bit bitmask) to select which fans enter forced mode. Mac15,9 hardware probe confirmed `FS! ` reads as nil; this key is absent on this generation.

**How to avoid:** On Mac15,9, use `F{i}Md` (ui8) per-fan mode key, NOT `FS! `. Read-back verification checks `F{i}Md`, not `FS! `.

**Warning signs:** `FS!` key diagnostics return nil; writes appear to succeed but no RPM change observed.

### Pitfall 3: IOKit-success-only trust (false positive write confirmation)

**What goes wrong:** `IOConnectCallStructMethod` returns `kIOReturnSuccess` for the write call. Code treats this as write success, updates UI to manual mode. But `output.result` byte is `0x82` (SmcBadCommand) — the firmware rejected the write at the SMC level.

**Why it happens:** `kIOReturnSuccess` means the IPC call to the kernel was delivered successfully, not that the SMC firmware accepted it. The SMC output struct contains a separate `result` field that must be checked.

**How to avoid:** After every `IOConnectCallStructMethod` write call, inspect `output.result == 0` in addition to the IOKit return code. Only treat both checks passing as a write success.

**Warning signs:** Write returns IOKit success but read-back shows mode unchanged; RPM does not respond to target.

### Pitfall 4: SMAppService daemon requires System Settings approval — gate the UX

**What goes wrong:** User enables manual fan control toggle. App tries to register daemon. `SMAppService.daemon.register()` returns `.requiresApproval`. App shows nothing. User is confused because no fan control appears.

**Why it happens:** Modern macOS (13+) requires the user to explicitly allow a LaunchDaemon in System Settings > Login Items (General > Login Items & Extensions). This is a one-time step but the OS gives no automatic prompt — the app must inform the user.

**How to avoid:** After `register()` returns `.requiresApproval`, show a calm inline guide: "请在 系统设置 > 登录项 中允许 MacStatus 风扇控制助手". Provide a button that opens `System Settings` via `URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.Extension")`. Poll `SMAppService.daemon.status` after the user returns.

**Warning signs:** `status == .requiresApproval` after register; no daemon visible in `launchctl list`.

### Pitfall 5: F{i}Tg encoding — flt type, little-endian float

**What goes wrong:** Helper writes RPM using `fpe2` encoding (common on Intel Macs). Mac15,9 uses `flt` (32-bit IEEE-754 float, little-endian) for F{i}Tg (confirmed by probe: `F0Tg type=flt`). Written value is interpreted as garbage RPM by firmware.

**Why it happens:** RPM encoding varies by hardware generation. Phase 11 probe confirms `F0Tg type=flt` and `F1Tg type=flt` on Mac15,9.

**How to avoid:** Probe key type at runtime using the existing `readRawValue(key:).dataType` path before writing. If type is `flt`, use little-endian float encoding (same as existing `SMCReader.decodeNumeric` for `flt`). For write, pack `Float(rpm)` bitPattern into 4 bytes, little-endian.

```swift
// Source: [ASSUMED] — derives from SMCReader.swift flt decode pattern (line 213)
func encodeFloatRPM(_ rpm: Double) -> [UInt8] {
    let bits = Float(rpm).bitPattern
    return [
        UInt8(bits & 0xFF),
        UInt8((bits >> 8) & 0xFF),
        UInt8((bits >> 16) & 0xFF),
        UInt8((bits >> 24) & 0xFF)
    ]
}
```

### Pitfall 6: Read-back mode detection — FanReader.diagnosticReadings() needed, not just readValue()

**What goes wrong:** Read-back verification calls `fanReader.readValue()` which populates `FanReading.currentRPM / targetRPM` but does NOT currently expose the mode field (`F{i}Md`). So the code cannot confirm the fan is actually in manual mode — it only sees the target changed.

**Why it happens:** `FanReader.readValue()` was designed for read-only monitoring and does not return mode bytes. Mode confirmation requires calling `diagnosticReadings()` or adding `modeValue` to `FanReading`.

**How to avoid:** Either (a) extend `FanReading` to include `modeValue: Int?` (from `F{i}Md`), or (b) call `fanReader.diagnosticReadings()` specifically for post-write verification. Option (a) is cleaner for the planner to implement. Mode = 0 means auto; mode = 1 means manual; mode = 3 means thermalmonitord system control.

### Pitfall 7: Helper binary not added to Xcode target sources (false build success)

**What goes wrong:** `xcodebuild` succeeds, but `FanControlHelper` binary is not compiled into the app bundle because its files were not added to `project.pbxproj`. Helper is absent at runtime; daemon registration fails.

**Why it happens:** Phase 7 documented this exact false-positive. New Swift files added to Xcode but not registered in `project.pbxproj` do not compile even when `xcodebuild` reports success.

**How to avoid:** For every new Swift file in the helper target, verify `project.pbxproj` contains the file reference AND the PBXSourcesBuildPhase entry. Verify helper binary exists in built app: `find build/ -name FanControlHelper`.

---

## Code Examples

### SMC Write Command (Helper — runs as root)

```swift
// Source: [CITED: github.com/agoodkind/macos-smc-fan/docs/research.md]
// Derives from SMCReader.swift SMCParamStruct pattern [VERIFIED: local codebase]
// cmd=6 is the write command (SMCReader already uses cmd=5 for read, cmd=9 for key info)
private static let cmdWriteKey: UInt8 = 6  // kSMCWriteKey

func writeUI8(key: String, value: UInt8) throws {
    guard isOpen else { throw SMCWriteError.notOpen }

    // Step 1: get key info (same as read path)
    var info = SMCParamStruct()
    info.key = Self.fourCharCode(key)
    info.data8 = Self.cmdReadKeyInfo  // 9
    guard let infoOut = call(info), infoOut.result == 0 else {
        throw SMCWriteError.keyInfoFailed(key: key)
    }

    // Step 2: write
    var write = SMCParamStruct()
    write.key = Self.fourCharCode(key)
    write.keyInfo.dataSize = infoOut.keyInfo.dataSize
    write.keyInfo.dataType = infoOut.keyInfo.dataType
    write.data8 = Self.cmdWriteKey  // 6
    // Pack value into bytes field (ui8: 1 byte)
    withUnsafeMutableBytes(of: &write.bytes) { ptr in
        ptr[0] = value
    }

    guard let writeOut = call(write), writeOut.result == 0 else {
        throw SMCWriteError.writeFailed(key: key)
    }
}
```

### FanControlProtocol — minimal XPC interface

```swift
// Source: [ASSUMED] — standard NSXPCInterface pattern
@objc protocol FanControlProtocol: NSObjectProtocol {
    func setManualTarget(rpm: UInt16, reply: @escaping (Bool, Int32) -> Void)
    func restoreAutoControl(reply: @escaping (Bool) -> Void)
}
```

### safeControlAvailable Gate — when to flip to true

```swift
// Source: [ASSUMED] — derives from D-04, D-12 decisions and FanReader.reading(for:) pattern
// In FanReader.reading(for:), replace the hardcoded safeControlAvailable: false with:
let safeControlAvailable: Bool = {
    // Prerequisites from hardware probe + helper availability:
    // 1. RPM is readable
    // 2. Bounds (min/max) are readable and sane
    // 3. Mode key (F{i}Md) is readable
    // 4. FanControlHelper daemon is registered and status == .enabled
    let modeReadable = smcReader.readRawValue(key: "F\(index)Md") != nil
    let helperEnabled = (SMAppService.daemon(plistName: "com.macstatus.fancontrolhelper.plist").status == .enabled)
    return rpmReadable && boundsReadable && modeReadable && helperEnabled
}()
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| SMJobBless privileged helper | SMAppService.daemon | macOS 13 (Ventura) | SMJobBless deprecated; SMAppService is the supported API; no `AuthorizationRef` needed |
| FS! bitmask for fan force mode (Intel) | F{i}Md per-fan mode key (Apple Silicon) | Apple Silicon (M1+) | FS! absent on Mac15,9; use F{i}Md=1 for manual, F{i}Md=0 for auto |
| Direct in-process SMC write (old tools) | Privileged daemon + XPC | Apple Silicon + thermalmonitord protection | Root required; thermalmonitord blocks without Ftst unlock |
| Single-step SMC mode write | Ftst=1 → wait → mode write → Ftst=0 | M3+ firmware | thermalmonitord enforces System Mode; unlock sequence required |
| fpe2 encoding for fan RPM | flt (32-bit IEEE-754 LE) on Mac15,9 | Mac15,9 (M3 Max) | Confirmed by Phase 11 hardware probe |

**Deprecated/outdated:**
- `smcFanControl`: Intel-only, no Apple Silicon support. Do not model on this.
- `FS! ` key as the only fan-mode control: absent on Mac15,9. Use `F{i}Md`.
- `SMJobBless`: deprecated macOS 13. Use `SMAppService`.
- `AuthorizationExecuteWithPrivileges`: deprecated. Use daemon + XPC.

---

## Runtime State Inventory

> This is NOT a rename/refactor phase — fan control state is new runtime state, not a migration. Filling in the relevant categories:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | No stored fan-control state exists yet; `FanReader` / `FanSnapshot` are runtime-only. Phase 13 must NOT persist any "manual mode active" state to UserDefaults or SQLite. | Code: never write manual-mode flag to persistent storage |
| Live service config | None yet. Phase 13 registers a new LaunchDaemon (`com.macstatus.fancontrolhelper`). After registration, it appears in `launchctl list` and System Settings > Login Items. | One-time registration via SMAppService.daemon; user approves once |
| OS-registered state | After Phase 13 implementation, the LaunchDaemon plist will be registered in the OS (System Settings > Login Items > Allow in the Background). This persists across reboots once the user approves. | Unregistration not in scope for Phase 13; Phase 14 handles lifecycle |
| Secrets/env vars | None. No API keys, tokens, or environment variables are involved. | None |
| Build artifacts | New Xcode target `FanControlHelper` will produce a separate binary embedded in the app bundle. Must be added to `project.pbxproj`. | Add to pbxproj; verify binary appears in built bundle |

**Mac15,9 SMC runtime state at entry to Phase 13:**
- F0Md = 0 (auto), F1Md = 0 (auto) — confirmed by Phase 11 probe
- F0Tg = 1350.0 RPM (current target = minimum), F1Tg = 1458.0 RPM
- FS!  = nil (absent)
- Ftst = 0 (normal/unlocked state)
- safeControlAvailable = false (will be flipped to true once helper is verified)

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode (xcodebuild) | Build both targets | ✓ | 16.x (macOS 26.5.1 / BuildVersion 25F80 confirmed by Phase 11 probe) | — |
| ServiceManagement framework | SMAppService.daemon | ✓ | macOS 13+ (already imported in SettingsManager.swift) | — |
| IOKit framework | SMC read/write | ✓ | System (already in use) | — |
| Foundation / XPC | NSXPCConnection | ✓ | System | — |
| Developer ID certificate (for distribution) | Signing the helper for notarized distribution | [ASSUMED: not verified] | — | Development certificate works locally; distribution requires paid Developer ID |
| Admin approval by user (System Settings) | LaunchDaemon registration | Requires user action | — | If not approved: safeControlAvailable stays false, toggle hidden |

**Missing dependencies with no fallback:**
- None that block implementation. The main risk is the user declining to approve the daemon in System Settings — this is handled by the fail-closed gate (D-12): if `SMAppService.status != .enabled`, toggle stays hidden.

**Note on Developer ID:** For local development and testing on the developer's own machine, an Apple Development certificate (from a free or paid developer account) is sufficient. For distribution via App Store or direct download, a paid Developer ID is required. MacStatus is currently built with ad-hoc codesigning for Debug (confirmed in Phase 11 probe build output). Phase 13 implementation will work locally with development codesigning; distribution constraints are a Phase 14 / release concern.

---

## Validation Architecture

> `workflow.nyquist_validation` is `false` in `.planning/config.json`. Validation architecture section: SKIPPED.

---

## Security Domain

### Trust Boundaries Added by Phase 13

| Boundary | Description | New Risk |
|----------|-------------|----------|
| Main app → XPC → FanControlHelper | Main app calls bounded XPC protocol; helper runs as root | Privilege escalation surface; mitigated by protocol scope (only setManualTarget/restoreAutoControl) |
| FanControlHelper → AppleSMC IOKit | Helper writes F{i}Md, F{i}Tg, Ftst | Hardware mutation; mitigated by RPM clamping in main app before XPC call, and by Ftst=0 release after write |
| User opt-in flow → safeControlAvailable gate | User enabling toggle triggers daemon registration | Mitigation: gate on safeControlAvailable=false when helper not yet approved; one-time consent dialog |

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | Login item requires user-level OS approval, not app-level auth |
| V4 Access Control | Yes | XPC interface restricted to two named methods; no raw-key passthrough |
| V5 Input Validation | Yes | RPM clamped to [F{i}Mn, F{i}Mx] before XPC call; helper validates range independently |
| V6 Cryptography | No | No encryption needed; XPC uses OS-managed Mach ports |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| SMC write to arbitrary key | Tampering | XPC protocol names only `setManualTarget` and `restoreAutoControl`; no key-passthrough API |
| False "manual verified" UI state | Information Disclosure | Read-back verification required before showing "手动已生效"; SMC output.result byte checked |
| Fan stuck in manual after crash | Denial of Service | Phase 13 scope: write-then-readback + immediate restore-auto on failure; full lifecycle recovery in Phase 14 |
| Helper daemon not approved → silent failure | Denial of Service | SMAppService.status checked before use; control toggle hidden if status != .enabled |
| IOKit success ≠ firmware success | Tampering | Always check `output.result == 0` in addition to `kIOReturnSuccess` |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | SMAppService.daemon with a development (non-Developer-ID) certificate works for local testing on the developer's own machine | Environment Availability | If it doesn't work locally without paid Developer ID, Phase 13 cannot be tested — would require a different local-only bypass or paid membership |
| A2 | Mac15,9 (M3 Max) follows the same Ftst=1 unlock sequence documented for M4/M5 Max in macos-smc-fan research | Pitfall 1 / Pattern 3 | If M3 Max has a different thermalmonitord behavior, the unlock sequence may not work; safeControlAvailable would stay false per fail-closed rule |
| A3 | F0Md/F1Md mode key casing is uppercase `Md` (not lowercase `md`) on Mac15,9 | Pattern 3 | Phase 11 probe confirmed `F0Md type=ui8` — this is HIGH confidence, not assumed; listed here for traceability |
| A4 | The Ftst=1 unlock causes thermalmonitord to yield within 3–10 seconds on M3 Max under normal (not heavy thermal load) conditions | Pattern 3 / Code Examples | If the timeout is shorter or longer on M3 Max, the retry loop constants need adjustment; fail-closed behavior handles this correctly |
| A5 | FanControlHelper can be embedded in the MacStatus app bundle as a separate Xcode target without requiring a separate app in the App Store | Architecture | If Apple requires separate notarization or App Store submission for the helper, distribution path becomes more complex; local testing is unaffected |

---

## Open Questions

1. **Does the Ftst unlock work on M3 Max specifically (Mac15,9)?**
   - What we know: macos-smc-fan documented it for M4/M5 Max; stats issue #2928 confirms M3+ have thermalmonitord protection.
   - What's unclear: Whether the timing constants (4–6 s) and the mode transition `3 → 0` hold on M3 Max.
   - Recommendation: Phase 13 must include a local hardware write probe (a minimal test binary, NOT the production app) that attempts the Ftst unlock on Mac15,9 and records the outcome. If the probe fails, D-12 fail-closed applies and the toggle stays hidden. This probe is the concrete hardware UAT for Phase 13's write path (full UAT is Phase 14).

2. **How long does a newly registered SMAppService daemon take to become `.enabled` after user approval?**
   - What we know: Status transitions from `.requiresApproval` → `.enabled` after user enables it in System Settings. The transition is not instantaneous.
   - What's unclear: Whether the app needs to poll, use NotificationCenter, or re-check on next launch.
   - Recommendation: Poll `SMAppService.daemon.status` every 2 seconds after showing the "please enable in System Settings" message. Stop polling when status changes to `.enabled` or `.notRegistered`.

3. **Does the helper binary need Hardened Runtime entitlements, or does ad-hoc signing suffice for local development?**
   - What we know: Stats and AlDente helpers use Hardened Runtime + Developer ID for distribution.
   - What's unclear: For the Phase 13 development cycle, whether ad-hoc + SMAppService.daemon registration works on the developer's own machine without Gatekeeper intervention.
   - Recommendation: Treat as [ASSUMED: yes for local development]. If it doesn't work, the planner should add a Wave 0 task to investigate local codesigning requirements.

---

## Sources

### Primary (HIGH confidence)
- Phase 11 Hardware Probe (`11-HARDWARE-PROBE.md`) — F0Md ui8 = 0x00, F1Md ui8 = 0x00, FS! = nil, F0Tg/F1Tg flt confirmed on Mac15,9 [VERIFIED: local probe]
- `SMCReader.swift` — existing 80-byte SMCParamStruct ABI, cmd=5 read, cmd=9 key-info patterns [VERIFIED: local codebase]
- `FanReader.swift` — existing read-only FanCapabilities model, safeControlAvailable=false gate [VERIFIED: local codebase]
- `SettingsManager.swift` — SMAppService.mainApp already imported from ServiceManagement [VERIFIED: local codebase]
- Apple Developer Documentation: SMAppService [CITED: developer.apple.com/documentation/servicemanagement/smappservice]

### Secondary (MEDIUM confidence)
- macos-smc-fan research documentation — Ftst unlock sequence, privilege requirements, thermalmonitord mode enforcement, SMC write selector 6 [CITED: github.com/agoodkind/macos-smc-fan]
- stats issue #2928 — M3/M4+ fan control blocked by thermalmonitord System Mode [CITED: github.com/exelban/stats/issues/2928]
- PITFALLS.md and ARCHITECTURE.md — project prior research on SMC write risks, FanControlManager design, Ftst necessity [VERIFIED: local planning docs]

### Tertiary (LOW confidence — cross-referenced with secondary, elevated to MEDIUM for general architecture)
- ThermalForge, AlDente, smctl — all confirm privileged daemon requirement for SMC writes [WebSearch; cross-verified with macos-smc-fan primary research]
- macs-fan-control 1.5.18 changelog — restored M3/M4 fan control via updated thermalmonitord coordination [WebSearch]

---

## Metadata

**Confidence breakdown:**
- Write-mechanism finding (root required, helper mandatory): HIGH — cross-verified by 4+ independent projects + macos-smc-fan primary research
- Ftst unlock sequence on M3 Max specifically: MEDIUM — documented for M4/M5, plausibly extends to M3 Max; requires local write probe to confirm
- SMAppService daemon pattern (existing project precedent + Apple docs): HIGH
- F{i}Md key casing, F{i}Tg flt encoding, FS! absent on Mac15,9: HIGH — confirmed by Phase 11 local hardware probe
- RPM clamp behavior (F{i}Mn/F{i}Mx): HIGH — confirmed readable by Phase 11 probe

**Research date:** 2026-06-26
**Valid until:** Stable for ~60 days; Ftst sequence details may drift if Apple updates thermalmonitord in a future macOS release.
