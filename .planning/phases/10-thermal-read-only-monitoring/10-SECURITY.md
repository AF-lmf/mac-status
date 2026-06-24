---
phase: 10
slug: thermal-read-only-monitoring
status: verified
threats_open: 0
asvs_level: 1
created: 2026-06-24
---

# Phase 10 - Security

Per-phase security contract for `10-thermal-read-only-monitoring`.

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| AppleSMC/IORegistry -> Reader | Undocumented hardware values can be absent, ambiguous, malformed, or stale. | SMC raw bytes, IORegistry battery properties, thermal state |
| Reader -> UI snapshot | Optional fields must not become fake user-facing certainty. | `ThermalSnapshot` optional values |
| Reader snapshot -> MainActor collector | Optional hardware values enter the unified app update loop. | Current thermal snapshot |
| DashboardState -> SwiftUI popover | Hardware absence or ambiguity becomes user-facing copy. | `CPU/SoC`, `系统状态`, `GPU`, `电池` labels/values |
| UserDefaults -> DashboardView | Local preference controls section visibility only. | `showThermalSection` |
| Hardware probe -> Phase signoff | Local hardware evidence determines whether CPU/SoC display is trusted or `N/A`. | Mac15,9 probe and diagnostics |

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation | Status |
|-----------|----------|-----------|-------------|------------|--------|
| T-10-01-T | Tampering | `SMCReader` decoded bytes | mitigate | Validate result bytes, size, type, and Celsius bounds; unknown formats return nil. | closed |
| T-10-01-I | Information Integrity | `ThermalReader` CPU/SoC source | mitigate | Mac15,9 CPU/SoC allowlist only; unsupported/unconfirmed sources return nil for UI `N/A`. | closed |
| T-10-01-D | Denial of Service | IORegistry/AppleSMC unavailable | mitigate | Probe-and-nil guards and optional casts; snapshot still returns nil fields. | closed |
| T-10-01-E | Elevation of Privilege | SMC write/control scope | mitigate | Fresh grep found no write constants, fan keys, helper/XPC, or generic writer. | closed |
| T-10-02-T | Tampering | `MetricCollector` thermal integration | mitigate | Thermal stays outside persistence/status-bar schemas and only current snapshot flows to dashboard. | closed |
| T-10-02-I | Information Integrity | `ThermalSectionView` labels | mitigate | Dedicated fields for `CPU/SoC`, `系统状态`, `GPU`, `电池`; no secondary promotion. | closed |
| T-10-02-D | Denial of Service | SwiftUI rendering with nil values | mitigate | Non-optional default snapshot and inline `N/A`/`未知` formatting keep stable rows. | closed |
| T-10-02-R | Repudiation | Settings-driven repaint behavior | accept | Accepted as local-only read-only repaint; source verifies no fresh SMC read in `applyNow()`. | closed |
| T-10-03-T | Tampering | `showThermalSection` UserDefaults value | accept | Accepted as local visibility-only preference; false hides section and does not alter read/control behavior. | closed |
| T-10-03-I | Information Integrity | `10-HARDWARE-PROBE.md` trust claim | mitigate | Probe records model, OS/build, diagnostic output, and trusted Mac15,9 catalog evidence. | closed |
| T-10-03-D | Denial of Service | Settings toggle repaint | mitigate | Dashboard reads `SettingsManager.shared`; cached UI repaint requires no fresh SMC read or relaunch. | closed |
| T-10-03-E | Elevation of Privilege | Fan/SMC write regression | mitigate | Fresh grep found no write APIs, fan keys/RPM, helper/XPC, or FanController symbols. | closed |
| T-10-SC | Tampering | npm/pip/cargo installs | mitigate | Package legitimacy audit says no package installation and no external package added. | closed |

## Threat Verification Evidence

| Threat ID | Evidence |
|-----------|----------|
| T-10-01-T | `SMCReader.swift:137`, `SMCReader.swift:141`, `SMCReader.swift:148`, `SMCReader.swift:167-172`, `SMCReader.swift:209-250` |
| T-10-01-I | `ThermalReader.swift:55-75`, `ThermalReader.swift:91-99`, `DashboardView.swift:183-185` |
| T-10-01-D | `SMCReader.swift:108`, `SMCReader.swift:131-148`, `ThermalReader.swift:35-43`, `ThermalReader.swift:86-101`, `ThermalReader.swift:146-153` |
| T-10-01-E | Fresh `rg` over `MacStatus/MacStatus` for write/fan/helper/XPC tokens returned no matches; recorded gate also at `10-HARDWARE-PROBE.md:100-112`. |
| T-10-02-T | `MetricCollector.swift:48-51`, `MetricCollector.swift:172-173`, `MetricCollector.swift:221-246`; fresh `rg` over Storage, StatusBarManager, and Metric for thermal tokens returned no matches. |
| T-10-02-I | `DashboardView.swift:146`, `DashboardView.swift:154-157`, `DashboardView.swift:188-195` |
| T-10-02-D | `ThermalReader.swift:35-43`, `DashboardView.swift:154-157`, `DashboardView.swift:183-185`, `DashboardView.swift:477`, `DashboardView.swift:567-570` |
| T-10-02-R | `MetricCollector.swift:123-126`, `MetricCollector.swift:142-145`, `MetricCollector.swift:221-223` |
| T-10-03-T | `SettingsManager.swift:86`, `SettingsManager.swift:115`, `SettingsManager.swift:311-320`, `SettingsManager.swift:490-494`, `SettingsView.swift:46`, `DashboardView.swift:69-71` |
| T-10-03-I | `10-HARDWARE-PROBE.md:17-22`, `10-HARDWARE-PROBE.md:55-96`, `ThermalReader.swift:55-75`, `ThermalReader.swift:91-99` |
| T-10-03-D | `DashboardView.swift:11`, `DashboardView.swift:69-71`, `MetricCollector.swift:123-126`, `MetricCollector.swift:221-223` |
| T-10-03-E | Fresh `rg` over `MacStatus/MacStatus` for write/fan/helper/XPC tokens returned no matches; recorded gate also at `10-HARDWARE-PROBE.md:100-112`. |
| T-10-SC | `10-RESEARCH.md:117-131`, `10-01-PLAN.md:113`, `10-01-SUMMARY.md:19`, `10-02-SUMMARY.md:18`, `10-03-SUMMARY.md:18` |

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-10-01 | T-10-02-R | Settings-driven repaint is local-only and read-only. `applyNow()` only reuses cached dashboard state and does not call `thermalReader.readValue()` or touch SMC/IORegistry. | gsd-security-auditor | 2026-06-24 |
| AR-10-02 | T-10-03-T | `showThermalSection` is a local visibility preference. Tampering can only hide/show the popover section; it does not add writes, control behavior, persistence schema changes, or status-bar output. | gsd-security-auditor | 2026-06-24 |

## Unregistered Flags

None. `10-01-SUMMARY.md`, `10-02-SUMMARY.md`, and `10-03-SUMMARY.md` each report no new unmapped threat surface in `## Threat Flags`.

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-06-24 | 13 | 13 | 0 | gsd-security-auditor |

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-06-24
