# Phase 3: GPU Monitoring - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-14
**Phase:** 3-GPU Monitoring
**Areas discussed:** GPU menu bar display

---

## Discussion Scope

| Option | Description | Selected |
|--------|-------------|----------|
| All key areas | Covers GPU data source/spike, fallback display, polling/recovery, and status-bar integration. | |
| Risk only | Focuses on GPU pressure feasibility, sandbox risk, and graceful degradation. | |
| Display only | Focuses on menu-bar text behavior while leaving implementation details to research/planning. | ✓ |

**User's choice:** Display only.
**Notes:** Technical implementation details are intentionally delegated to research/planning.

---

## GPU Normal Display

| Option | Description | Selected |
|--------|-------------|----------|
| `GPU 34%` | Consistent with `CPU 12%` and `MEM OK`; clearest label. | |
| `G 34%` | Shorter and saves menu bar width. | ✓ |
| `34%` | Shortest, but lacks context. | |

**User's choice:** `G 34%`.
**Notes:** User also asked to record matching short labels: change `CPU` to `C` and `MEM` to `M`.

---

## GPU Unavailable Display

| Option | Description | Selected |
|--------|-------------|----------|
| `G --` | Consistent fallback format; clearly indicates GPU unavailable. | ✓ |
| Hide GPU segment | Shorter, but changes menu width and can cause jitter. | |
| `G N/A` | Clear semantics, but wider than `--`. | |

**User's choice:** `G --`.
**Notes:** GPU segment should remain visible even when data is unavailable.

---

## GPU Pressure Display

| Option | Description | Selected |
|--------|-------------|----------|
| Color `G 34%` segment | Green/yellow/red pressure indicator without adding width. | ✓ |
| `G 34% OK/WARN/CRIT` | Most explicit text, but wider. | |
| Do not show pressure in Phase 3 | Only GPU percentage; pressure deferred. | |

**User's choice:** Color the `G 34%` segment.
**Notes:** User also asked to color CPU and MEM. That broader display rule was deferred to Phase 4.

---

## Segment Order

| Option | Description | Selected |
|--------|-------------|----------|
| `C 12% | M OK | ↓2.1M ↑512K | G 34%` | Append new GPU metric at the end. | |
| `C 12% | G 34% | M OK | ↓2.1M ↑512K` | Put CPU/GPU compute metrics together. | ✓ |
| `C 12% | M OK | G 34% | ↓2.1M ↑512K` | Keep network as the final dynamic segment. | |

**User's choice:** Put GPU after CPU.
**Notes:** Target display format: `C 12% | G 34% | M OK | ↓2.1M ↑512K`.

---

## Agent's Discretion

- GPU data source, pressure threshold mapping, polling cadence, sandbox handling, and fallback implementation details are delegated to research/planning.

## Deferred Ideas

- Color CPU and MEM segments as part of Phase 4 Combined Display + Formatting.
