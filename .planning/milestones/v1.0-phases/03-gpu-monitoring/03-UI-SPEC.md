---
phase: 03
slug: gpu-monitoring
status: approved
shadcn_initialized: false
preset: none
created: 2026-05-14
---

# Phase 03 — UI Design Contract

> Visual and interaction contract for the menu bar display changes in Phase 3.

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

This is a menu bar text surface, not a page layout.

| Token | Value | Usage |
|-------|-------|-------|
| separator | ` | ` | Separates metric segments |
| inline gap | single space | Between label and value, e.g. `G 34%` |

Exceptions: macOS status bar padding is controlled by `NSStatusItem`.

---

## Typography

| Role | Size | Weight | Line Height |
|------|------|--------|-------------|
| Menu bar metric | `NSFont.smallSystemFontSize` | regular | system |

Rules:
- Use monospaced digits for all metric text.
- Do not scale font size with viewport or menu bar width.
- Keep text single-line with clipping, not wrapping.

---

## Color

| Role | Value | Usage |
|------|-------|-------|
| Default metric text | `NSColor.labelColor` | CPU, memory, network, separators |
| GPU normal pressure | `NSColor.systemGreen` | `G 34%` segment |
| GPU warning pressure | `NSColor.systemYellow` | `G 34%` segment |
| GPU critical pressure | `NSColor.systemRed` | `G 34%` segment |

Accent reserved for: GPU segment pressure only. CPU and memory coloring is deferred to Phase 4.

---

## Copywriting Contract

| Element | Copy |
|---------|------|
| Target combined format | `C 12% | G 34% | M OK | ↓2.1M ↑512K` |
| GPU unavailable | `G --` |
| CPU unavailable | `C --%` |
| Memory normal | `M OK` |
| Memory warning | `M WARN` |
| Memory critical | `M CRIT` |
| Memory unavailable | `M --` |

---

## Interaction Contract

- Phase 3 adds no popover, menu, settings window, or click behavior.
- Existing menu bar item remains the visible source of truth.
- GPU unavailable must not remove the GPU segment because segment removal changes width and can cause jitter.

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
