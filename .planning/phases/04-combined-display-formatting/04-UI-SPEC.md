---
phase: 04
slug: combined-display-formatting
status: approved
shadcn_initialized: false
preset: none
created: 2026-05-14
---

# Phase 04 — UI Design Contract

> Visual and interaction contract for the final v1 menu bar combined display.

---

## Design System

| Property | Value |
|----------|-------|
| Tool | none |
| Preset | not applicable |
| Component library | AppKit `NSStatusItem` / `NSStatusBarButton` |
| Icon library | none |
| Font | `NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)` |

---

## Spacing Scale

This is a single-line menu bar text surface, not a page layout.

| Token | Value | Usage |
|-------|-------|-------|
| separator | ` | ` | Separates metric segments |
| inline gap | single space | Between label and value, e.g. `C 12%` |
| width | `300` status item points | Fixed visible menu bar item width |

Exceptions: macOS controls outer status bar padding.

---

## Typography

| Role | Size | Weight | Line Height |
|------|------|--------|-------------|
| Menu bar metric | `NSFont.smallSystemFontSize` | regular | system |
| Label | same as metric | regular | system |
| Value/status | same as metric | regular | system |

Rules:
- Use monospaced digits for all metric text.
- Do not scale font size with viewport or status item width.
- Keep text single-line with clipping, not wrapping.

---

## Color

| Role | Value | Usage |
|------|-------|-------|
| Default text | `NSColor.labelColor` | Labels, separators, network, normal/default values |
| Warning value | `NSColor.systemYellow` | CPU/GPU values `60...84%`, memory `WARN` |
| Critical value | `NSColor.systemRed` | CPU/GPU values `>=85%`, memory `CRIT` |

Accent reserved for: CPU/GPU numeric values and memory status words only. Labels `C`, `G`, `M`, separators, and network text stay default. GPU normal no longer uses green.

---

## Copywriting Contract

| Element | Copy |
|---------|------|
| Target combined format | `C 12% | G 34% | M OK | ↓2.1M ↑512K` |
| CPU unavailable | `C --%` |
| GPU unavailable | `G --` |
| Memory normal | `M OK` |
| Memory warning | `M WARN` |
| Memory critical | `M CRIT` |
| Memory unavailable | `M --` |
| Network unavailable | `↓-- ↑--` |

---

## Interaction Contract

- Phase 4 adds no popover, menu, settings window, or click behavior.
- The existing combined `networkStatusItem` remains the only visible source of truth.
- Unavailable metrics stay visible using their fallback text so the segment order and width stay stable.

---

## Registry Safety

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| none | none | not required |

---

## Checker Sign-Off

- [x] Dimension 1 Copywriting: PASS
- [x] Dimension 2 Visuals: PASS
- [x] Dimension 3 Color: PASS
- [x] Dimension 4 Typography: PASS
- [x] Dimension 5 Spacing: PASS
- [x] Dimension 6 Registry Safety: PASS

**Approval:** approved 2026-05-14
