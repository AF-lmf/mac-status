# Phase 5: Launch at Login + Quality of Life - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-14
**Phase:** 05-launch-at-login-quality-of-life
**Areas discussed:** launch-at-login policy, right-click menu scope, sleep/wake recovery

---

## Launch at Login

| Option | Description | Selected |
|--------|-------------|----------|
| 默认启用 | App 启动时用 `SMAppService.mainApp.register()` 注册登录项。 | ✓ |
| 设置开关 | 增加设置 UI，让用户手动开关登录自启。 | |
| 只实现 API 不启用 | 保留实现但不主动注册。 | |

**User's choice:** 用户要求“按你的推荐来，不讨论了，持续执行”。
**Notes:** 推荐默认启用以直接满足 Phase 5 成功标准。设置 UI 延后，避免扩大范围。

---

## Right-Click Menu Scope

| Option | Description | Selected |
|--------|-------------|----------|
| 最小 Quit 菜单 | 右键只显示 `Quit MacStatus`。 | ✓ |
| Quit + Settings/About | 同时加入设置和关于入口。 | |
| 左键弹菜单 | 改变默认点击行为。 | |

**User's choice:** 用户授权采用推荐默认。
**Notes:** Phase 5 需求只要求至少 Quit；最小菜单降低 UI 和测试面。

---

## Sleep/Wake Recovery

| Option | Description | Selected |
|--------|-------------|----------|
| 停止并重启 readers | 睡前 stop，醒后 start，复用现有 TimerReader。 | ✓ |
| 只在醒后重启 | 不处理睡前状态。 | |
| 重建所有 reader 实例 | 醒后重新创建 readers。 | |

**User's choice:** 用户授权采用推荐默认。
**Notes:** 现有 `TimerReader` 已有 start/stop 原语，优先复用。醒后立即采样由 `TimerReader.start()` 的 `.now()` 行为保证。

---

## Deferred Ideas

- Settings window and launch-at-login toggle.
- About menu item.
- Rich popover or detailed metrics panel.
- Full 30+ minute CPU soak can be tracked as manual UAT if the implementation session cannot reasonably wait.
