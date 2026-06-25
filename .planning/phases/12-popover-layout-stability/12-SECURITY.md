---
phase: 12
slug: popover-layout-stability
status: verified
threats_open: 0
asvs_level: 1
created: 2026-06-25
register_authored_at_plan_time: true
---

# Phase 12 — Security

> Per-phase security contract: plan-time threat register, accepted risks, and audit trail.

## SECURED

Phase 12 plan-time threat mitigations are verified against implementation code and phase evidence artifacts. No implementation files were modified during this audit.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| process/sensor text -> SwiftUI layout | Long process names, PID text, sensor labels, fan captions, and value strings enter constrained popover rows. | User/process-originated labels and dynamic metric strings |
| app source -> hardware readers | Layout work must not introduce fan control, SMC writes, helper/XPC, status-bar fan/thermal features, alerts, charts, or raw sensor browsing. | Source-level UI and hardware-access boundaries |
| debug/test support -> user UI | Deterministic fixture data and geometry probes must remain test/debug-only and not become user-facing debug surfaces. | Fixture values, probe anchors, and hosted XCTest state |
| UserDefaults -> layout tests | Local popover section visibility settings can hide sections; deterministic tests must force/restore settings. | Visibility booleans for battery, thermal, fan, and process sections |
| phase artifact -> downstream phases | Layout verification evidence is used to close jitter requirements and must be reproducible. | Test command output, frame measurements, and source gates |

---

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation / Acceptance | Status | Evidence |
|-----------|----------|-----------|-------------|-------------------------|--------|----------|
| T-12-01-DOS | Denial of Service | `DashboardView` label/value rows | mitigate | Fixed root width plus fixed value widths; labels/captions yield before values. | closed | `StableValueLayout.swift:6-22` defines `DashboardLayout.popoverWidth = 372` and value widths; `DashboardView.swift:140-141` applies the fixed root width; `StableValueLayout.swift:47-87` truncates labels and bounds captions. |
| T-12-01-I | Information Integrity | temperature/RPM/battery/network values | mitigate | Right-aligned monospaced fixed value cells sized for UI-SPEC worst cases. | closed | `StableValueLayout.swift:24-44` applies `.monospacedDigit()` and fixed trailing frames; `DashboardView.swift:167-173`, `DashboardView.swift:222-229`, `DashboardView.swift:433-449`, and `DashboardView.swift:355-363` route temperature, RPM, battery/power, and metric-card values through it. |
| T-12-01-T | Tampering | hardware control boundary | mitigate | No fan controls, SMC writes, helper/XPC, status-bar fan/thermal work, alerts, charts, network/API, or raw sensor browsing introduced. | closed | Current scope gate over Phase 12 touched files returned no matches for write/control/helper/XPC/network/alert/chart/raw-sensor patterns; `12-LAYOUT-VERIFICATION.md:70-88` records the same layout-only scope gate. |
| T-12-01-SC | Tampering | npm/pip/cargo installs | accept | No package-manager installs were planned or performed. | accepted | Accepted risk AR-12-01-SC. Phase 12 changed Swift/Xcode/planning files only; package manifest/lockfile gate over `fdeb343..HEAD` returned no matches. |
| T-12-02-DOS | Denial of Service | `ProcessMetricRow` | mitigate | Reserve fixed trailing width and force left process text truncation. | closed | `ProcessListView.swift:100-125` gives the left label `maxWidth: .infinity`, truncation, low priority, and fixed trailing width; `DashboardView.swift:562-573` reuses the same row for CPU/memory process values. |
| T-12-02-I | Information Integrity | `NetworkTrafficValueBlock` and process trailing metrics | mitigate | Keep existing formatter semantics while using fixed monospaced cells. | closed | `ProcessListView.swift:53-56` still uses `ByteFormatting.format(...)+"/s"`; `ProcessListView.swift:72-93` reserves a 148pt pair with two 68pt monospaced rate cells. |
| T-12-02-T | Tampering | `DashboardLayoutFixture` reachability | mitigate | Guard fixture declarations with `#if DEBUG` and keep live app paths from referencing fixture type. | closed | `DashboardLayoutFixtures.swift:1-5` is `#if DEBUG`; live-path grep for `DashboardLayoutFixture` under App/Collectors/UI Views/StatusBar/Utils returned no matches; tests reference it only in `DashboardLayoutStabilityTests.swift:97-109`. |
| T-12-02-SC | Tampering | npm/pip/cargo installs | accept | No package-manager installs were planned or performed. | accepted | Accepted risk AR-12-02-SC. Phase 12 package manifest/lockfile gate returned no matches. |
| T-12-03-R | Repudiation | Phase 12 verification evidence | mitigate | Record `xcodebuild test`, fixture coverage, frame measurements, and source gates in `12-LAYOUT-VERIFICATION.md`. | closed | `12-LAYOUT-VERIFICATION.md:7-21` records build/test commands and results; `12-LAYOUT-VERIFICATION.md:35-68` records fixed-size and frame evidence; `12-LAYOUT-VERIFICATION.md:70-88` records source gates and scope statement. |
| T-12-03-DOS | Denial of Service | `DashboardView` and `ProcessMetricRow` layout | mitigate | XCTest measures short/extreme fixtures and long process rows. | closed | `DashboardLayoutStabilityTests.swift:9-30` asserts fixed width and same height; `DashboardLayoutStabilityTests.swift:52-73` asserts long process rows preserve trailing position/width; `DashboardLayoutStabilityTests.swift:75-161` compares required value-column x/width frames. |
| T-12-03-T | Tampering | hardware/control boundary | mitigate | Source gates block fan control, SMC writes, helper/XPC, status-bar fan/thermal features, alerts, charts, and raw sensor browsing. | closed | Current scope gate over Phase 12 touched files returned no matches; `AppDelegate.swift:22-25` prevents layout test host from starting the status bar/collector path. |
| T-12-03-I | Information Integrity | deterministic fixture assertions | mitigate | Tests assert UI-SPEC constants and exact width/height tolerances instead of subjective visual inspection. | closed | `DashboardLayoutStabilityTests.swift:32-44` asserts the stable width contract; `DashboardLayoutStabilityTests.swift:97-121` hosts real `DashboardView` fixtures; `DashboardLayoutStabilityTests.swift:164-182` forces/restores all relevant section visibility settings. |
| T-12-03-SC | Tampering | npm/pip/cargo installs | accept | XCTest is part of Xcode; no package-manager installs were planned or performed. | accepted | Accepted risk AR-12-03-SC. Phase 12 package manifest/lockfile gate returned no matches. |

*Status: closed · open · accepted*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-12-01-SC | T-12-01-SC | Phase 12 introduced no external dependency or package-manager installation surface; this risk is accepted as no-op supply-chain scope. | Plan-time threat register | 2026-06-25 |
| AR-12-02-SC | T-12-02-SC | Phase 12 introduced no external dependency or package-manager installation surface; this risk is accepted as no-op supply-chain scope. | Plan-time threat register | 2026-06-25 |
| AR-12-03-SC | T-12-03-SC | Phase 12 used hosted XCTest from the existing Xcode toolchain and introduced no package-manager installation surface. | Plan-time threat register | 2026-06-25 |

*Accepted risks do not resurface in future audit runs unless the trust boundary changes.*

---

## Threat Flags

`12-01-SUMMARY.md`, `12-02-SUMMARY.md`, and `12-03-SUMMARY.md` all recorded `## Threat Flags` as none. The summaries report no new network endpoint, auth path, file-access boundary, SMC write/control path, helper/XPC path, status-bar surface, alert, chart, raw sensor browser, or dependency install.

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Accepted | Open | Run By |
|------------|---------------|--------|----------|------|--------|
| 2026-06-25 | 13 | 10 | 3 | 0 | Codex security audit |

### Verification Commands

| Gate | Command / Evidence | Result |
|------|--------------------|--------|
| Plan-time threat model presence | `rg -n "<threat_model>|threat_id|Threat Flags" .planning/phases/12-popover-layout-stability` | PASS: all three plan files contain threat models; all three summaries contain threat flag sections. |
| Stable layout controls | `rg -n "DashboardLayout\\.popoverWidth|StableValueText|StableValueRow|StableCaptionText|ProcessMetricRow|NetworkTrafficValueBlock" MacStatus/MacStatus/UI/Views/...` | PASS: fixed-width helpers and process row surfaces are wired. |
| Fixture live-path isolation | `rg -n "DashboardLayoutFixture" MacStatus/MacStatus/App MacStatus/MacStatus/Collectors MacStatus/MacStatus/UI/Views MacStatus/MacStatus/UI/StatusBarManager.swift MacStatus/MacStatus/Utils` | PASS: no matches. |
| DEBUG fixture/probe boundaries | `rg -n "#if DEBUG|DashboardLayoutFixture" MacStatus/MacStatus/UI/Fixtures/DashboardLayoutFixtures.swift MacStatus/MacStatusTests/DashboardLayoutStabilityTests.swift` | PASS: fixture file is DEBUG-gated and referenced by tests. |
| Hardware/control/network/UI scope absence | `rg -n "cmdWriteBytes|writeBytes|writeValue|writeRaw|FanControl|手动|恢复自动|静音|风扇控制|控制可用|即将支持|F[0-9]Tg|FS!|helper|XPC|NSXPC|URLSession|NWListener|NSAlert|Alert\\(|Chart\\(|原始传感器|raw sensor" <Phase 12 touched files>` | PASS: no matches. |
| Package install surface | `git diff --name-only fdeb343..HEAD | rg -n "Package\\.swift|Package\\.resolved|Podfile|Cartfile|Gemfile|package\\.json|package-lock\\.json|pnpm-lock\\.yaml|yarn\\.lock|requirements\\.txt|pyproject\\.toml|Cargo\\.toml|Cargo\\.lock"` | PASS: no matches. |
| Deterministic layout evidence | `12-LAYOUT-VERIFICATION.md` and `DashboardLayoutStabilityTests.swift` | PASS: fixed width, same-height, value-column frame, process trailing, and width-contract checks are recorded. |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-06-25
