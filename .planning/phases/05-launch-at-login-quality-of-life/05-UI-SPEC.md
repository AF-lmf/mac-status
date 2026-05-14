---
phase: 05
slug: launch-at-login-quality-of-life
status: approved
shadcn_initialized: false
preset: none
created: 2026-05-14
---

# Phase 05 — UI Design Contract

> Visual and interaction contract for the right-click quality-of-life menu.

---

## Design System

| Property | Value |
|----------|-------|
| Tool | none |
| Component library | AppKit `NSStatusItem` / `NSStatusBarButton` / `NSMenu` |
| Icon library | none |
| Font | macOS system menu font |

---

## Interaction Contract

| Interaction | Result |
|-------------|--------|
| Left click status item | No-op |
| Right click status item | Opens a native AppKit menu |
| Select `Quit MacStatus` | Terminates the app through `NSApp.terminate(nil)` |

Rules:
- The right-click menu attaches to the existing combined status bar item.
- Do not create a second visible menu bar item.
- Do not add a popover, settings panel, or about panel in Phase 5.
- Do not change the combined metric title or Phase 4 color rules.

---

## Copywriting Contract

| Element | Copy |
|---------|------|
| Quit item | `Quit MacStatus` |

---

## Visual Contract

- Use native `NSMenu` rendering.
- Use standard AppKit menu spacing, highlight, and keyboard equivalent behavior.
- The menu has no custom colors or custom drawing.

---

## Checker Sign-Off

- [x] Dimension 1 Copywriting: PASS
- [x] Dimension 2 Visuals: PASS
- [x] Dimension 3 Color: PASS
- [x] Dimension 4 Typography: PASS
- [x] Dimension 5 Spacing: PASS
- [x] Dimension 6 Registry Safety: PASS

**Approval:** approved 2026-05-14
