---
phase: 11
slug: fan-read-only-rpm-capability-model
status: verified
threats_open: 0
asvs_level: 1
created: 2026-06-24
---

# Phase 11 — Security

> Per-phase security contract: plan-time threat register, accepted risks, and audit trail.

## SECURED

Phase 11 plan-time threat mitigations are verified against implementation code and phase evidence artifacts. No implementation files were modified during this audit.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| AppleSMC -> `SMCReader` | Undocumented raw SMC bytes, type strings, and absent keys enter the app. | Raw SMC bytes, 4-char keys, type strings, optional decoded numeric values |
| `SMCReader` -> `FanReader` | Optional decoded values must not become fake RPM, fake bounds, or control certainty. | Optional fan count/current/min/max/target RPM values |
| `FanReader` -> `MetricCollector` | Optional hardware telemetry enters the unified polling loop. | Current `FanSnapshot`, kept outside metric history/status bar schemas |
| `MetricCollector` -> `DashboardState` | Current fan snapshot becomes popover UI state without persistence. | Non-optional popover-only `FanSnapshot` |
| `UserDefaults` -> `SettingsManager` -> `DashboardView` | Local visibility preferences decide which row groups render. | `showFanSection` boolean visibility preference |
| `DashboardState` -> SwiftUI popover | Hardware capability and missing values become user-facing copy. | Numbered fan rows, `N/A`, range/target copy |
| Source grep gates -> phase signoff | Source-level absence of write/control/status/history surfaces determines fail-closed closure. | Source scan evidence over implementation paths |
| Phase artifact -> downstream phases | Later fan-control work will consume this read-only capability evidence; it must not imply safe control. | Hardware probe output and source-gate evidence |

---

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation / Acceptance | Status | Evidence |
|-----------|----------|-----------|-------------|-------------------------|--------|----------|
| T-11-01-T | Tampering | `SMCReader.decodeNumeric` | mitigate | Validate size/type before decoding; normalize only integer type whitespace; unknown formats return nil. | closed | `SMCReader.swift:209-252` checks `flt ` exactly, trims only integer type whitespace, enforces byte-count guards, and falls through to `nil`. |
| T-11-01-I | Information Integrity | `FanReader` capability model | mitigate | Keep `rpmReadable`, `boundsReadable`, `targetReadable`, and `safeControlAvailable` separate; never infer safe control from readable RPM. | closed | `FanReader.swift:10-14`, `FanReader.swift:151-172`, and `FanReader.swift:177-190` define independent booleans and keep `safeControlAvailable: false`. |
| T-11-01-D | Denial of Service | AppleSMC absent or malformed fan keys | mitigate | Return unsupported/unreadable snapshots with optional nil fields; no thrown errors or modal surfaces. | closed | `SMCReader.swift:105-148` returns `false`/`nil` on unavailable AppleSMC, invalid key info, or invalid size; `FanReader.swift:75-98` and `FanReader.swift:134-147` return unsupported/unreadable snapshots. Current grep found no `throw`, `throws`, `fatalError`, `NSAlert`, or `Alert(` in SMC/Fan/Dashboard paths. |
| T-11-01-E | Elevation of Privilege | AppleSMC write surface | mitigate | No write constants, write helpers, helper/XPC, or control classes. | closed | Current gate `! rg -n "cmdWriteBytes\|writeBytes\|writeValue\|writeRaw\|FanControl\|helper\|XPC\|FS!.*write\|F[0-9]Tg.*write" MacStatus/MacStatus` returned no matches. |
| T-11-02-T | Tampering | `showFanSection` UserDefaults | accept | Local visibility-only preference can hide/show rows but cannot write SMC keys or change fan behavior. | accepted | Accepted risk AR-11-02-T. `SettingsManager.swift:325-335` only persists a boolean and posts settings change; `SettingsView.swift:43-48` exposes only `Toggle("风扇区块", ...)`. |
| T-11-02-I | Information Integrity | `DashboardView` fan labels and copy | mitigate | Numbered labels without position evidence; nil as `N/A`; unsupported fan surfaces hidden quietly. | closed | `FanReader.swift:160-172` and `FanReader.swift:177-190` use `风扇 \(index + 1)`; current left/right grep returned no matches. `DashboardView.swift:69-76` and `DashboardView.swift:189-191` hide unsupported fan surfaces; `DashboardView.swift:251-253` renders nil RPM as `N/A`. |
| T-11-02-D | Denial of Service | Optional fan values in SwiftUI | mitigate | Non-optional `FanSnapshot` default and optional formatting keep rows stable without crashes. | closed | `FanReader.swift:28-39` provides `.unavailable()`, `DashboardView.swift:585-586` stores non-optional `@Published var fan: FanSnapshot = .unavailable()`, and `DashboardView.swift:251-270` formats optional RPM/range/target without force unwraps. |
| T-11-02-E | Elevation of Privilege | Fan control affordance in UI | mitigate | No buttons/sliders/mode controls/control promise; raw fan SMC keys absent from end-user UI. | closed | Current UI gates found no fan control strings, raw fan keys, fan buttons, or Dashboard sliders/steppers. `SettingsView.swift:43-48` contains only the visibility toggle; `DashboardView.swift:238-240` displays only fail-closed copy `边界可读，控制未启用`. |
| T-11-02-R | Repudiation | Settings-driven repaint | accept | `applyNow()` reuses cached snapshots; no extra SMC reads or side effects. | accepted | Accepted risk AR-11-02-R. `MetricCollector.swift:128-133` calls only `updateUI(sample:)`; `MetricCollector.swift:234-236` pushes cached `lastFanSnapshot`; new fan reads occur on start/tick at `MetricCollector.swift:76-85` and `MetricCollector.swift:179-182`. |
| T-11-03-I | Information Integrity | `11-HARDWARE-PROBE.md` | mitigate | Exact commands, outputs, model identity, missing optional key evidence, and final gates recorded. | closed | `11-HARDWARE-PROBE.md:8-62` records hardware/build/probe commands; `11-HARDWARE-PROBE.md:66-146` records exact probe output, model, optional missing keys, and values. |
| T-11-03-R | Repudiation | Hardware validation evidence | mitigate | Build and source gate results included in the same probe artifact. | closed | `11-HARDWARE-PROBE.md:24-47` records build gate and `BUILD SUCCEEDED`; `11-HARDWARE-PROBE.md:158-290` records final source gate commands/results in the same artifact. |
| T-11-03-E | Elevation of Privilege | Accidental SMC write/control scope | mitigate | Final source gates block write helpers/selectors, helper/XPC, control UI, and control promise copy. | closed | Current write/helper/XPC gate and UI control/raw-key gates returned no matches; probe artifact also records those gates at `11-HARDWARE-PROBE.md:162-220` and `11-HARDWARE-PROBE.md:236-247`. |
| T-11-03-T | Tampering | Fan data persistence/status-bar expansion | mitigate | Final source gates block fan/RPM tokens in Storage, StatusBarManager, and Metric surfaces. | closed | Current gate `! rg -n "fan\|Fan\|RPM\|风扇" MacStatus/MacStatus/Storage MacStatus/MacStatus/UI/StatusBarManager.swift MacStatus/MacStatus/Utils/Metric.swift` returned no matches. `MetricSample.swift:7-30`, `HistoryStore.swift:78-89`, `StatusBarManager.swift:82-113`, and `Metric.swift:12-18` have no fan field/segment/metric. |
| T-11-SC | Tampering | package installs | mitigate | No external packages installed in Phase 11. | closed | `git show --name-only` for Phase 11 commits listed only Swift/Xcode/planning files; `find` for npm/pip/cargo/SPM/CocoaPods/Carthage manifests and lockfiles returned no matches; plan summaries record `tech-stack.added: []`. |

*Status: closed · open · accepted*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-11-02-T | T-11-02-T | `showFanSection` is a local visibility-only preference. UserDefaults tampering can hide/show fan rows but cannot write SMC keys, alter fan behavior, or expose a control path. | Plan-time threat register | 2026-06-24 |
| AR-11-02-R | T-11-02-R | Settings-driven repaint reuses cached `lastFanSnapshot` through `applyNow()` and `updateUI(sample:)`; it does not force extra SMC reads or introduce side effects. | Plan-time threat register | 2026-06-24 |

*Accepted risks do not resurface in future audit runs unless the trust boundary changes.*

---

## Threat Flags

No `## Threat Flags` sections were present in `11-01-SUMMARY.md`, `11-02-SUMMARY.md`, or `11-03-SUMMARY.md`.

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Accepted | Open | Run By |
|------------|---------------|--------|----------|------|--------|
| 2026-06-24 | 14 | 12 | 2 | 0 | Codex security audit |

### Verification Commands

| Gate | Command / Evidence | Result |
|------|--------------------|--------|
| SMC write/helper/XPC absence | `! rg -n "cmdWriteBytes\|writeBytes\|writeValue\|writeRaw\|FanControl\|helper\|XPC\|FS!.*write\|F[0-9]Tg.*write" MacStatus/MacStatus` | PASS: no matches |
| Reader/modal DoS absence | `! rg -n "throw\|throws\|fatalError\|NSAlert\|Alert\(" MacStatus/MacStatus/Readers/SMCReader.swift MacStatus/MacStatus/Readers/FanReader.swift MacStatus/MacStatus/UI/Views/DashboardView.swift` | PASS: no matches |
| Fan control/raw-key UI absence | `! rg -n "控制可用\|手动\|恢复自动\|静音\|风扇控制\|即将支持\|F0Ac\|FNum\|FS!\|F0Tg\|Button\(\".*风扇" MacStatus/MacStatus/UI/Views/DashboardView.swift MacStatus/MacStatus/UI/Views/SettingsView.swift` | PASS: no matches |
| Dashboard fan slider/stepper absence | `! rg -n "Slider\(\|Stepper\(" MacStatus/MacStatus/UI/Views/DashboardView.swift` | PASS: no matches |
| Left/right label absence | `! rg -n "左风扇\|右风扇" MacStatus/MacStatus/UI/Views/DashboardView.swift MacStatus/MacStatus/Readers/FanReader.swift` | PASS: no matches |
| Storage/status/metric fan absence | `! rg -n "fan\|Fan\|RPM\|风扇" MacStatus/MacStatus/Storage MacStatus/MacStatus/UI/StatusBarManager.swift MacStatus/MacStatus/Utils/Metric.swift` | PASS: no matches |
| Summary threat flags | `rg -n "^## Threat Flags\|Threat Flags\|threat" 11-01-SUMMARY.md 11-02-SUMMARY.md 11-03-SUMMARY.md` | PASS: no matches |
| Package install surface | `git show --name-only` for Phase 11 commits; `find` for package manifests/lockfiles | PASS: no dependency files changed; no package manifests/lockfiles found |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-06-24
