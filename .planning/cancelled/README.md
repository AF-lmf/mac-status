# Cancelled Work

存放已撤销但保留作历史参考的规划产物（未执行、无代码落地）。

## 13-safe-fan-control-gate-write-path （取消于 2026-06-30）

- **原 Phase 13**: Safe Fan Control Gate & Write Path — 手动风扇控制的硬件写入路径。
- **连带取消的 Phase 14**: Lifecycle Recovery & Hardware UAT — 仅服务于风扇控制的生命周期恢复与真机 UAT（无独立目录，仅在 ROADMAP 中规划）。
- **原因**: 用户决定取消风扇硬件改动功能。
- **状态**: 从未执行（0 个 SUMMARY，仅有 `docs(13)` 规划提交，无任何写入路径代码落地）。Phase 10–12 的只读温度/风扇监控不受影响。
- **撤销的需求**: FCTRL-01..06、UAT-01/02/03（详见 REQUIREMENTS.md，已标为 Descoped）。
- **里程碑**: v3.0 保持开放，未收口。

如需恢复，把本目录移回 `.planning/phases/`，并在 ROADMAP.md 重新登记 Phase 13/14。
