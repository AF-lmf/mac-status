---
status: in-progress
slug: macstatus-position-cache
quick_id: 260529-3a7
---

# Plan

修复 MacStatus 在 macOS 26.5 (Liquid Retina XDR / notch) 上启动后菜单栏完全不显示的根因：`autosaveName="com.macstatus.network"` 把上次的 `Preferred Position = 1000` 缓存了下来，重启后 AppKit 把状态项放进了刘海/系统右侧菜单遮挡的不可见区域。前次 `260529-1th` 任务的 SUMMARY 声称已经移除 autosaveName，但代码里实际只更新了注释，源码行没动。

## 根因证据

- `defaults read com.macstatus.app` → `"NSStatusItem Preferred Position com.macstatus.network" = 1000;`
- `StatusBarManager.swift:167` 仍有 `networkStatusItem?.autosaveName = "com.macstatus.network"`
- 进程在跑 (`pgrep MacStatus` 返回 PID 28831)，单实例守卫工作正常 → 不是启动/崩溃，是定位/渲染
- 用户报告菜单栏干净 → 不需要靠 620pt 占位 padding 抢位置，前次的宽度黑魔法是错误方向

## 步骤

1. 真删 `autosaveName` 行
2. `applicationDidFinishLaunching` 早期 `UserDefaults.standard.removeObject(forKey: "NSStatusItem Preferred Position com.macstatus.network")`，让本次启动从干净位置开始
3. 回滚 320pt 固定宽度 + 620pt 占位 padding → 改回 `NSStatusItem.variableLength`，去掉 `button.alignment = .left`，去掉 `updateCombinedStatus` 里的 `length =` 覆盖
4. 恢复 `combinedAttributedString()`（彩色 C/G/M 告警）作为 `attributedTitle`
5. macOS 26 提示 alert 改成只在 `isVisible == false` 时弹（前次去掉了这个判断变成无条件弹）
6. 保留 `enforceSingleInstance`（合理改动）
7. 构建并杀掉旧实例重启验证
