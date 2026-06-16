# Pitfalls Research — v2.0 洞察与可定制

**Domain:** macOS 菜单栏系统资源监控应用（新增：逐进程 Top-N、电池/电源、设置窗口）
**Researched:** 2026-06-16
**Confidence:** HIGH

> 范围说明：本文件只覆盖 **v2.0 三个新功能（逐进程 Top-N CPU/内存、电池与电源、设置窗口+可定制）** 引入的新陷阱。v1.0 已建立的陷阱（NSStatusItem 幽灵图标、休眠唤醒冻结、高频轮询功耗、LSUIElement 窗口生命周期、网络接口枚举、固定宽度抖动、32-bit 网络计数器回绕、`freeifaddrs()` in defer、IOKit PerformanceStatistics 字段名因 GPU 型号而异、macOS 26 菜单栏隐私门）见 `.planning/milestones/v1.0-research/PITFALLS.md`，**不在此重复**，但在适用处会引用以提醒复用既有模式。
>
> 关键分发前提（影响多个陷阱）：MacStatus 以 **Developer ID 签名 + 公证（notarized）+ DMG 分发，不上架 App Store，不启用 App Sandbox**。这一前提决定了逐进程采样的可行性——见 Critical Pitfall 1。

---

## Critical Pitfalls

### Pitfall 1: 误用 `task_for_pid` 做逐进程采样，破坏公证/硬化运行时姿态

**What goes wrong:**
开发者想读取「每个进程的 CPU%」时，第一反应是 Mach 的 `task_for_pid()` + `task_info(TASK_BASIC_INFO/TASK_THREAD_TIMES_INFO)`。在 Apple Silicon + 现代 macOS 上，`task_for_pid()` 对非自身、非子进程的目标会返回 `KERN_FAILURE`(5)，除非进程拥有 `com.apple.security.cs.debugger`（或目标带 `get-task-allow`），而调试器类 entitlement 与 Hardened Runtime 公证审查相冲突，且无法读取其他用户/系统进程。结果是要么读不到数据，要么为了「能跑」而打开危险 entitlement，污染公证姿态。

**Why it happens:**
绝大多数「macOS 取 CPU 占用」的旧教程都用 `task_for_pid`（来自 root 工具/调试器时代）。开发者不知道存在不需要任何特权的 `<libproc.h>` 路径。

**How to avoid:**
- **完全不要用 `task_for_pid`。** 用 libproc 家族（非沙盒应用无需任何 entitlement）：
  - `proc_listpids(PROC_ALL_PIDS, 0, buffer, size)` 枚举 PID（先传 `nil` buffer 取所需大小，再分配）。
  - `proc_pid_rusage(pid, RUSAGE_INFO_V4, &rusage)` 取 `ri_user_time + ri_system_time`（纳秒，**累计** CPU 时间）和内存（`ri_resident_size` / `ri_phys_footprint`）。
  - 名称用 `proc_name()` / `proc_pidpath()`。
- 保持 **Hardened Runtime 开启、不增加 `cs.debugger`/`task_for_pid-allow` 等 entitlement** —— libproc 路径对其余进程只会返回它有权看到的子集（见 Pitfall 4），不会触发公证问题。
- 在 entitlements 与 Info.plist 中做一次显式检查：构建脚本断言不含 debugger/allow-jit 等条目。

**Warning signs:**
- 取其他用户/系统进程时 `task_for_pid` 返回 5；只有自身进程有数据。
- 为「修复」而往 entitlements 里加 `com.apple.security.cs.debugger` —— 这是错误方向。
- `codesign -d --entitlements - MacStatus.app` 出现 debugger 相关条目。

**Phase to address:**
逐进程 Top-N 阶段（Per-Process Sampling Phase）—— 第一根技术钉子就要用 libproc 验证「能在公证签名构建里读到其他进程」。

**Evidence:**
- Apple Dev Forums「Getting process info for other processes?」「task_for_pid error 5」：官方建议用 `<libproc.h>` 而非 `task_for_pid`，后者「只对开发工具有用」。HIGH。
- Apple Hardened Runtime 文档：`cs.debugger` 属调试能力 entitlement。HIGH。

---

### Pitfall 2: 把 `proc_pid_rusage` 的**累计** CPU 时间当成瞬时占用率显示

**What goes wrong:**
`ri_user_time`/`ri_system_time` 是进程自启动以来的**累计** CPU 纳秒数。若直接用「累计时间 / 进程已运行时间」或直接显示该值，长寿命进程（如 WindowServer、浏览器）会永远排在 Top，而真正此刻在烧 CPU 的进程排不上来——与 Activity Monitor 的「% CPU」（瞬时）完全不符。

**Why it happens:**
rusage 字段名没有「rate」字样，看起来像即时值；CPU% 必须由两次快照求差得出，但这一步常被略过。

**How to avoid:**
- 维护 `pid -> 上一轮累计 CPU 纳秒` 的字典。每轮：
  `cpuPercent = (cumNow - cumPrev) / (wallΔ_ns) * 100`，其中 `wallΔ_ns` 是两次采样的真实墙钟间隔（用 `clock_gettime(CLOCK_MONOTONIC)` 或 `DispatchTime`，**不要**假设 == 配置的刷新间隔，定时器会抖动/被节流）。
- 多核语义对齐 Activity Monitor：单核满载 = 100%，不要除以核数（除非明确要 0–100% 归一化，需在 UI 标注）。
- 首轮没有 `cumPrev`，该进程本轮显示「—」或跳过，不要用 0 误导排序。
- 内存直接取 `ri_phys_footprint`（更接近 Activity Monitor 的 Memory 列）或 `ri_resident_size`，二者择一并固定。

**Warning signs:**
- Top-N 长期被同一批长寿命进程占据，跑满 CPU 的临时进程进不了榜。
- 数值远大于 100×核数，或始终是个位数。
- 切换刷新间隔后 CPU% 跳变（说明用了固定间隔常量而非真实墙钟差）。

**Phase to address:**
逐进程 Top-N 阶段（Per-Process Sampling Phase）。

**Evidence:**
- Apple Dev Forums「Obtaining CPU usage by process」：需对 thread/proc 时间求差。HIGH。
- osquery #7459：Apple Silicon 上部分进程 user/system time 字段异常——再次说明需校验并以差值口径处理。MEDIUM。

---

### Pitfall 3: 快照间 PID 消失/复用导致负值、崩溃或张冠李戴

**What goes wrong:**
两次采样之间进程退出，`proc_pid_rusage(deadpid, ...)` 返回错误（-1/ESRCH），若不检查返回码会用到未初始化结构体得出垃圾数据。更隐蔽的是 **PID 复用**：旧 PID 退出后系统把同号 PID 分配给新进程，用旧的 `cumPrev` 减新进程的 `cumNow` 得到负的或暴涨的 CPU%。

**Why it happens:**
开发者把「PID→上一轮值」字典当成稳定主键，忽略 PID 是会被回收的短期标识。

**How to avoid:**
- **每次** 调用都检查返回码：`proc_pid_rusage` 返回 0 才有效，非 0 立即从本轮结果与缓存字典中剔除该 PID。
- delta 必须 `max(cumNow - cumPrev, 0)`（沿用 v1.0 网络计数器的 `max(delta,0)` 模式）；若出现负值，视为 PID 复用/重启，丢弃本轮该进程的百分比（显示「—」）。
- 可选加固：缓存键用 `(pid, 进程启动时间)` 复合键——`proc_pidinfo(PROC_PIDTBSDINFO)` 的 `pbi_start_tvsec` 变了即认定是新进程，清除旧累计值。
- 每轮结束后**修剪**缓存字典，删除本轮不再出现的 PID，避免字典随长时间运行无限增长。

**Warning signs:**
- 偶发出现 CPU% 为负或瞬间几千%。
- 缓存字典 size 随运行时长单调增长（内存缓慢泄漏）。
- 某进程名对应的数值「跳到」另一个不相关进程。

**Phase to address:**
逐进程 Top-N 阶段（Per-Process Sampling Phase）。

---

### Pitfall 4: 误以为「读不到全部进程」是 bug，或盲目追求完整进程列表

**What goes wrong:**
非 root、非沙盒进程对**其他用户/系统较高权限进程**的 rusage 可能返回 EPERM 或字段截断（拿不到名字/路径或拿到 0）。开发者把这当成需要修复的缺陷，进而引入特权 helper（SMJobBless/root daemon），既违背「零依赖、轻量」原则，又带来代码签名校验、安全面扩大等一连串 v1.0 已警示的安全陷阱。

**Why it happens:**
期望与 `sudo` 下的 Activity Monitor 对齐（Activity Monitor 自带特权 helper），但本应用是普通用户态非特权进程。

**How to avoid:**
- **接受权限边界**：Top-N 只在「当前用户可见的进程」范围内排序，这对「哪个进程在吃我的资源」场景完全够用。
- 对取不到名字的 PID 用 `proc_pidpath` 兜底，再不行显示 PID 号，不要因个别项失败而整榜失败。
- 明确把「完整可排序全进程列表 / 跨用户监控」列入 Out of Scope（PROJECT.md 已有「不与 Activity Monitor 重叠」决策），**不引入特权 helper**。
- 注意：本应用不开 App Sandbox，所以**不会**遇到 `process-info-listpids` 沙盒拒绝（那是沙盒应用专属、且无 entitlement 可解的死路）；保持非沙盒即可。

**Warning signs:**
- 准备写 `SMJobBless` / LaunchDaemon 只为读进程列表。
- Console 出现 `process-info-listpids` deny（=不小心开了沙盒，回退）。

**Phase to address:**
逐进程 Top-N 阶段（Per-Process Sampling Phase）。

**Evidence:**
- Apple Dev Forums「How to avoid sandbox violation for process-info-listpids」：沙盒下 `proc_listpids` 被拒且**无 entitlement 可绕过**。HIGH。
- v1.0 PITFALLS「Sandbox vs IOKit」「Security Mistakes/SMJobBless」：本项目既定非沙盒 DMG 分发、避免特权 helper。HIGH。

---

### Pitfall 5: 在 @MainActor 上每周期枚举/采样全部 PID，造成卡顿与 Swift 6 并发违规

**What goes wrong:**
`proc_listpids` + 对几百个 PID 逐个 `proc_pid_rusage`/`proc_name` 是几百次系统调用。若放在 `@MainActor`（沿用 v1.0 Reader 在主线程更新 UI 的习惯）每 1–2s 跑一次，会在打开 Popover、滚动、设置窗口交互时产生可感卡顿；且 v1.0 是聚合单次调用，开发者会想当然地照搬到「全 PID 循环」。同时 Swift 6 strict concurrency 下，把 C 结构体/指针缓存跨 actor 传递会触发 Sendable 报错。

**Why it happens:**
v1.0 的 host_statistics 是 O(1) 廉价调用，逐进程是 O(进程数) 且开销高一个量级；直接复制旧 Reader 模式会把重活压在主线程。

**How to avoid:**
- 把逐进程采样放进**独立的 `actor`（或 detached Task / 专用串行队列）**，主线程只接收已排好序、已截断为 Top-N 的 **Sendable 值类型**（如 `struct ProcSample: Sendable { let pid; let name; let cpu; let mem }` 数组）。C 指针/`rusage_info_v4` 不跨 actor 传，只在采样 actor 内消费。
- **Top-N 采样独立、低频**：进程榜对实时性要求低，间隔设 **3–5s**（比状态栏 1–2s 慢），且**只在 Popover 可见时才采样**——Popover 关闭时停掉这个最贵的 Reader（v1.0 高频轮询功耗陷阱的延伸）。
- 排序后**只保留 Top-5**，不要把全量进程数组送到主线程或 SwiftUI（否则 diffing 几百行）。
- 沿用 v1.0 `TimerReader<T>` 基类，但为进程 Reader 单独配置间隔/可见性门控，不要与状态栏共用一个定时器。

**Warning signs:**
- 打开 Popover 时主线程卡顿、动画掉帧。
- Instruments 显示 `proc_*` 系统调用占据主线程时间。
- Swift 6 编译报 `Non-sendable type ... crossing actor boundary`。
- Popover 关闭后 Activity Monitor 仍显示本应用 CPU 偏高。

**Phase to address:**
逐进程 Top-N 阶段（Per-Process Sampling Phase）+ Swift 6 并发整改贯穿全 milestone。

---

### Pitfall 6: 电池剩余时间 `-1`（kIOPSTimeRemainingUnknown）被当成真实读数显示

**What goes wrong:**
刚唤醒、刚插拔电源、或刚开机时，`IOPSGetTimeRemainingEstimate()` 返回 `kIOPSTimeRemainingUnknown`（-1.0），power source 字典里 `kIOPSTimeToEmptyKey`/`TimeToFullCharge` 也常为 -1 或缺失。直接格式化就会显示「-1 分钟」「剩余 -0:01」或荒谬的时间，用户立刻失去信任。还有 `kIOPSTimeRemainingUnlimited`(-2.0) 表示「接电源、无限」，不是错误。

**Why it happens:**
系统在睡眠/插拔造成的电量不连续后，需要一段「校准窗口」才发布可信估计；开发者没区分「未知」「无限」「有效正数」三态。

**How to avoid:**
- 三态判定：`== kIOPSTimeRemainingUnknown(-1)` → 显示「计算中…」/隐藏时间项；`== kIOPSTimeRemainingUnlimited(-2)` 或交流供电 → 显示「已接电源」/不显示时间；`> 0` → 才格式化为 `h:mm`。
- 唤醒/插拔后**延迟 ~5s 再信任**估计（沿用 v1.0 didWake 后延迟恢复模式），期间保留上一个有效值或显示占位。
- 用 `IOPSNotificationCreateRunLoopSource` 监听电源状态变化做事件驱动刷新，而不是高频轮询去「等」有效值。

**Warning signs:**
- 唤醒后短暂出现「-1 分钟 / 剩余 -0:01」。
- 接上电源瞬间剩余时间显示负数或跳变。

**Phase to address:**
电池与电源阶段（Battery & Power Phase）。

**Evidence:**
- Apple 文档 `kIOPSTimeRemainingUnknown` / `IOPSGetTimeRemainingEstimate`；PowerManagement 源码 `BatteryTimeRemaining.c` 在 wake 后记录不连续、延迟发布估计、`kIOPMPSInvalidWakeSecondsKey` 标记不可信窗口。HIGH。

---

### Pitfall 7: 充放电功率(W)/电流的符号与单位约定误判

**What goes wrong:**
要显示「实时充放电功率 W」，需从 IORegistry `AppleSmartBattery` 读 `InstantAmperage`、`Amperage`、`Voltage`（或 `BatteryData` 里的功率/电流）。这些字段：(1) **符号约定不统一**——放电为负、充电为正（或反之），且部分机型用 64-bit 无符号存储负电流（需按二进制补码重解释为有符号，否则放电时得到一个接近 2^64 的巨值）；(2) 单位是 mA / mV，需 `W = (mA/1000) * (mV/1000)` 换算；(3) 与 `IOPSCopyPowerSourcesInfo` 的公开字典字段不完全一致。

**Why it happens:**
公开 `IOPowerSources` API 不直接给「瞬时瓦特」，开发者转去读 IORegistry 私有键，但这些键无文档、符号/位宽随机型变化。

**How to avoid:**
- 优先用 `InstantAmperage`/`InstantTimeToEmpty` 等「瞬时」键；读取后**做符号 sanity check**：充电状态(`IsCharging==true`)时功率应为一个方向、放电时为另一方向，据此统一为「正=充电、负=放电」（或你选定的约定）并在 UI 标注。
- 对疑似无符号存的负电流：若值 > `Int64.max` 量级，按 `Int64(bitPattern:)` 重解释。
- 用 `abs()` 显示功率数值 + 单独的充/放电图标/符号，避免把符号直接塞进数字让用户困惑。
- 把瓦特换算和符号归一封装在 reader 内并写单元/手测用例（充电中、放电中、满电维持三态各验一次）。

**Warning signs:**
- 放电时功率显示为 ~1.8e19 这类天文数字（无符号误读）。
- 充电/放电时符号方向相反于直觉。
- 瓦特值差 1000 倍（mA/mV 未换算）。

**Phase to address:**
电池与电源阶段（Battery & Power Phase）。

**Evidence:**
- RehabMan AppleSmartBattery 驱动源码、SocPowerBuddy、macsmc-power 驱动补丁：电流/功率符号与位宽随实现变化，放电/充电约定需按机型校正。MEDIUM。

---

### Pitfall 8: 电池健康字段（CycleCount/MaxCapacity/DesignCapacity）在不同机型存在/键名不一致，及非笔记本机型未优雅降级

**What goes wrong:**
「电池健康度 = MaxCapacity/DesignCapacity」依赖 `AppleSmartBattery` 的 `CycleCount`、`AppleRawMaxCapacity`、`DesignCapacity`、`MaxCapacity` 等键。这些键：在 Intel 与 Apple Silicon 上键名/单位不同（Apple Silicon 上 `MaxCapacity` 一度是百分比而非 mAh，健康度真实值在 `AppleRawMaxCapacity`/`NominalChargeCapacity`），在 **台式机（Mac mini/Studio/Pro/无电池 iMac）上整个 `AppleSmartBattery` 服务不存在**。若硬取键并强解包 → 台式机崩溃或显示「健康度 0%」「100%/100% 一直充电」等假数据。

**Why it happens:**
开发机通常是一台 MacBook，开发者只在「有电池且键齐全」的环境测试，键名/机型差异在台式机或异代芯片上才暴露（与 v1.0「IOKit 字段名因 GPU 型号而异」同类）。

**How to avoid:**
- **先探测有无电池**：`IOPSCopyPowerSourcesList` 为空 **或** `IOServiceGetMatchingService(AppleSmartBattery)` 取不到 → 判定为台式机/无电池，**整段电池 UI 优雅降级**（隐藏，而非显示空值），与 v1.0「部分指标不可用时优雅降级」一致。
- 健康度键做**多键回退**（沿用 v1.0 GPU 多键尝试模式）：优先 `AppleRawMaxCapacity`/`NominalChargeCapacity` ÷ `DesignCapacity`；缺失则回退；全缺失则不显示健康度但仍显示电量/充电状态。
- 所有键用可选解包 + 范围 sanity（健康度裁剪到 0–100%，>100% 视为单位误判而隐藏）。
- 真机矩阵测试：至少 1 台 Apple Silicon 笔记本 + 1 台台式 Mac（无电池）+（可得则）1 台 Intel 笔记本。

**Warning signs:**
- 台式 Mac 上崩溃，或电池段显示「0%/计算中/100% 充电中」。
- 健康度显示 >100% 或恒为 100%。
- Apple Silicon 与 Intel 上健康度数量级差异大（mAh vs %）。

**Phase to address:**
电池与电源阶段（Battery & Power Phase），降级路径在该阶段的成功标准里。

**Evidence:**
- AppleSmartBattery 字段（CurrentCapacity/MaxCapacity/CycleCount）社区文档；Apple Silicon `MaxCapacity` 单位差异为已知社区报告。MEDIUM。v1.0「IOKit 字段名因型号而异 + 优雅降级」模式复用。HIGH。

---

### Pitfall 9: 设置「每指标刷新间隔」实时改值时泄漏旧定时器 / 重配错 Reader

**What goes wrong:**
用户在设置里把「CPU 刷新间隔」从 2s 改为 5s，代码新建一个定时器却没 invalidate 旧的——两个定时器同时在跑（旧的还在以 2s 烧 CPU），或闭包 `self` 强引用导致 Reader 永不释放（v1.0 已警示 Timer→self 循环引用）。更糟的是重配时改错了 Reader（把网络 Reader 的间隔应用到 CPU Reader）。

**Why it happens:**
v1.0 定时器在启动时一次性配置、生命周期与 app 等长；v2.0 首次出现「运行时重配」，原 `TimerReader` 可能没有幂等的 `reconfigure(interval:)` 路径。

**How to avoid:**
- 给 `TimerReader<T>` 增加幂等 `func setInterval(_:)`：内部先 `timer?.invalidate(); timer = nil` 再以新间隔重建；闭包用 `[weak self]`。
- 每个指标一个独立 Reader 实例 + 稳定标识（enum MetricKind），设置变更通过 `kind -> reader` 映射精确路由，避免张冠李戴。
- 间隔值做下限钳制（如 ≥1s），防止用户设 0/0.1s 导致 CPU 飙升。
- 设置变更走单一入口（应用 PreferencesStore 的 observer），统一触发 reconfigure，避免多处散落的修改路径。

**Warning signs:**
- 改间隔后 Activity Monitor 显示 CPU 不降反升（旧定时器没停）。
- 多次改间隔后内存缓慢上涨（Reader/Timer 泄漏，deinit 不触发）。
- 改 A 指标间隔影响了 B 指标。

**Phase to address:**
设置与可定制阶段（Settings & Customization Phase）。

**Evidence:**
- v1.0 PITFALLS「循环引用 Timer→self」「refresh interval setting does not work (Stats #2407)」。HIGH。

---

### Pitfall 10: 开关/拖动排序指标时重建状态栏导致闪烁、丢失固定宽度

**What goes wrong:**
用户在设置里隐藏 GPU、把网络拖到 CPU 前面。若实现为「拆掉整个 NSStatusItem 重建」，会出现菜单栏图标闪烁、位置跳动（v1.0 已警示抖动），甚至重建后忘了重设 `statusItem.length` 固定宽度→又开始抖动；极端情况下旧 item 没 remove→幽灵图标（v1.0 Critical Pitfall 1 复发）。

**Why it happens:**
把「内容/顺序变化」误当「需要新 status item」，而非「同一个 item 内重排已渲染的段（segments）」。

**How to avoid:**
- **复用同一个 `NSStatusItem`**，只更新其 `button` 内的 attributed string / 自绘视图的段顺序与可见性；绝不为重排而 remove/add status item。
- 排序/开关后**重算固定宽度**：按当前启用指标集合的最宽组合重设 `statusItem.length`（紧凑/详细模式各算一次），保持 `.monospacedDigit()`。
- 用值类型的「布局描述（ordered enabled metrics）」驱动渲染，变化时只 diff 段，不重建容器。
- 若确需多 NSStatusItem 方案，严格沿用 v1.0：重建前先 `removeStatusItem`，且不在 SwiftUI `@State` 集合里管理。

**Warning signs:**
- 改顺序/开关时菜单栏整体闪一下或宽度跳动。
- 隐藏某指标后宽度没收缩（或留白）。
- 多次开关后菜单栏出现重复图标。

**Phase to address:**
设置与可定制阶段（Settings & Customization Phase）；固定宽度复用 v1.0 菜单栏 UI 阶段成果。

**Evidence:**
- v1.0 PITFALLS「可变宽度抖动」「NSStatusItem 幽灵图标」。HIGH。

---

### Pitfall 11: UserDefaults 偏好无 schema 版本，键增长后迁移失败/读到旧类型崩溃

**What goes wrong:**
v2.0 偏好键迅速膨胀（每指标开关、顺序数组、各自间隔、阈值、配色、紧凑/详细模式）。无版本号时，未来改键名/改结构（如阈值从单值变成 {warn,crit}）会让老用户的本地 UserDefaults 与新代码不匹配：强类型解码崩溃、或静默回到默认丢失用户配置。SwiftUI `@AppStorage` 直接绑原始键更易把结构演进焊死。

**Why it happens:**
首版偏好少，直接散落写 `UserDefaults.standard.set(...)`，没人想到第二版要迁移。

**How to avoid:**
- 引入单一 `PreferencesStore`（Codable 模型 + 一个 `schemaVersion: Int` 键）作为偏好的唯一入口；启动时读 version，按需跑迁移链（v1→v2…），写回新 version。
- 解码全部容错：缺键/类型不符→回落默认值而非崩溃；用 `decodeIfPresent`。
- 顺序/开关存稳定 metric 标识字符串数组，**新增指标**时迁移逻辑把未知/缺失指标按默认顺序补到末尾（向后/向前兼容）。
- 谨慎使用 `@AppStorage`：UI 绑定经 PreferencesStore 暴露的属性，便于集中迁移与校验，而非散绑裸键。
- 对配色/阈值等做范围校验，损坏值回默认。

**Warning signs:**
- 升级后用户配置「丢了」或应用启动即崩。
- 改偏好结构时不得不保留一堆旧键名兼容。
- `@AppStorage` 键散落在多个 View 里，无法集中迁移。

**Phase to address:**
设置与可定制阶段（Settings & Customization Phase）—— schemaVersion 与迁移框架应在写入任何新键之前就位。

---

### Pitfall 12: LSUIElement 应用的 SwiftUI Settings 窗口不显示 / app 不激活

**What goes wrong:**
LSUIElement(.accessory) 应用打开独立设置窗口时，常见：窗口在后台不前置、应用不抢焦点导致输入无效、或 `Settings {}` scene 的 `⌘,` 在无主菜单的 accessory 应用里根本触发不了；点设置菜单项「没反应」。这是 v1.0「LSUIElement + 窗口生命周期」陷阱在「现在真的需要一个窗口」时的正面遭遇。

**Why it happens:**
accessory 应用没有常规主菜单与激活路径；SwiftUI `Settings` scene 依赖标准 ⌘, 入口，在 menu-bar-only 应用里行为不可靠。

**How to avoid:**
- 打开设置时显式：`NSApp.activate(ignoringOtherApps: true)` + 窗口 `makeKeyAndOrderFront(nil)`，**不要**为显示窗口而切换 `.regular/.accessory`（v1.0 已警示切换非原子、闪 Dock 图标）。
- 用专用 `NSWindowController`（或 SwiftUI 内容托管在一个由我们控制的 NSWindow）托管设置 UI，从 Popover/状态栏菜单点击入口直接 order-front，而非依赖系统 ⌘,。
- 窗口设 `isReleasedWhenClosed = false` 并复用单例，避免重复打开多个/关闭后再开崩溃。
- 全屏 space 下打开设置体验差：参考 v1.0 安全建议，必要时用 `requestUserAttention` 替代强弹窗。

**Warning signs:**
- 点「设置」无反应或窗口藏在其他应用后面。
- 设置窗口里输入框无法获得键盘焦点。
- 反复打开关闭设置后崩溃或出现多个窗口。

**Phase to address:**
设置与可定制阶段（Settings & Customization Phase）。

**Evidence:**
- v1.0 PITFALLS「LSUIElement / 激活策略与窗口生命周期」、Apple Dev Forums「Menu Bar App's Menu Not Working」。HIGH。

---

### Pitfall 13: 新 Reader 跨 actor 的 Sendable/@MainActor 违规，与睡眠唤醒未恢复

**What goes wrong:**
新增的进程 Reader、电池 Reader 在 Swift 6 strict concurrency 下，把 C 结构体（`rusage_info_v4`、CF 字典、IOService 句柄）从后台采样上下文传到 `@MainActor` UI 时触发「non-Sendable crossing actor boundary」。同时，新 Reader 若未接入 v1.0 既有的 `didWakeNotification` 恢复链，唤醒后电池估计停在 -1、进程榜冻结（v1.0 休眠冻结陷阱对新数据源复发）。

**Why it happens:**
v1.0 Reader 早于 strict concurrency 收紧期成型；新 Reader 直接套旧模板会把非 Sendable 类型暴露过界，且新 Reader 容易被遗漏在睡眠/唤醒回调之外。

**How to avoid:**
- 采样层（actor/串行队列）只向主线程输出 **Sendable 值类型快照**；CF/IOKit/C 句柄一律不出采样层。`@unchecked Sendable` 仅在确有保护时谨慎使用并注释原因。
- 统一让**所有** Reader（含新两个）实现一个 `prepareForSleep()/recoverFromWake()` 协议方法，集中注册到 v1.0 的 `willSleep/didWake` 监听；唤醒后电池 reader 重开 IOService、进程 reader 清空 `cumPrev` 缓存（避免跨睡眠的累计差爆值）、延迟 ~5s 再信任电池估计。
- CI/编译以 Swift 6 language mode 全开 strict concurrency，把 Sendable 告警当错误。

**Warning signs:**
- Swift 6 编译大量 `Non-sendable type ... cannot cross actor boundary`。
- 唤醒后电池显示 -1/进程榜不刷新。
- 唤醒后第一帧进程 CPU% 异常暴涨（跨睡眠累计差未清）。

**Phase to address:**
贯穿三个新功能阶段；睡眠唤醒恢复并入各 Reader 的成功标准（复用 v1.0 系统监控引擎阶段模式）。

**Evidence:**
- v1.0 PITFALLS「休眠/唤醒传感器冻结」、PROJECT 约束 Swift 6。HIGH。

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| 用 `task_for_pid`+`task_info` 取进程 CPU（照搬旧教程） | 旧示例多、易抄 | 需危险 entitlement、读不到他进程、污染公证姿态 | Never — 用 libproc |
| Top-N 采样跑在 @MainActor 且与状态栏共用定时器 | 复用 v1.0 Reader 省事 | Popover/设置交互卡顿、Popover 关了还在采样耗电 | Never — 独立 actor + 可见性门控 |
| 直接显示 `proc_pid_rusage` 累计时间当占用率 | 少存一份上一轮快照 | Top 榜被长寿命进程霸占，与 Activity Monitor 不符 | Never — 求差 |
| 电池剩余时间不判 -1/-2 直接格式化 | 代码短 | 唤醒/插拔后显示「-1 分钟」失信 | Never — 三态判定 |
| UserDefaults 散写裸键、无 schemaVersion | 首版最快 | 偏好结构演进即丢配置/崩溃 | 仅一次性 spike，正式版必须有版本+迁移 |
| 排序/开关靠 remove+add NSStatusItem 重建 | 实现直观 | 闪烁、丢固定宽度、幽灵图标 | Never — 复用同一 item 重排段 |
| 电池只在 MacBook 上测、键强解包 | 开发机就是笔记本 | 台式 Mac 崩溃/假数据、异代芯片单位错 | Never — 先探测有无电池 + 多键回退 |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| libproc (`proc_listpids`/`proc_pid_rusage`) | 不先用 nil buffer 探长度；不检查每次返回码 | 两段式取长度+缓冲；逐项校验返回 0，失败剔除该 PID |
| libproc CPU 时间 | 当瞬时值；用固定刷新间隔当墙钟差 | 两快照求差 / CLOCK_MONOTONIC 真实间隔；`max(delta,0)` |
| IOPowerSources | `IOPSGetTimeRemainingEstimate` 不判 -1/-2 | 三态：Unknown(-1)/Unlimited(-2)/正数；事件驱动用 `IOPSNotificationCreateRunLoopSource` |
| IORegistry AppleSmartBattery | 私有键强解包、符号/位宽硬编码 | 多键回退 + 可选解包 + 符号 sanity；负电流按补码重解释；mA·mV→W |
| 无电池机型 | 假设 AppleSmartBattery 必存在 | 先 `IOPSCopyPowerSourcesList` 空检测/服务缺失检测 → 整段降级 |
| UserDefaults / @AppStorage | 散绑裸键无版本 | 单一 Codable PreferencesStore + schemaVersion + 迁移链 |
| NSStatusItem 重排 | remove+add 重建 | 复用 item，仅重排/重隐渲染段，重算固定宽度 |
| Swift 6 actors | CF/C 结构体跨 actor 传递 | 只传 Sendable 值快照，句柄留在采样层 |
| 设置窗口（LSUIElement） | 依赖系统 ⌘, / 切 activationPolicy | 专用 NSWindowController + activate + makeKeyAndOrderFront |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| 每周期对全部 PID 逐个系统调用 | 打开 Popover 卡顿，本应用 CPU 升高 | Top-N 间隔 3–5s + 仅 Popover 可见时采样 + 后台 actor | 进程多（>300）/频繁开 Popover |
| Top-N 缓存字典只增不减 | 长跑后内存缓慢上涨 | 每轮修剪消失的 PID | 运行数小时后 |
| 电池高频轮询 | Energy 排名上升 | 事件驱动 `IOPSNotificationCreateRunLoopSource`，避免秒级轮询 | 持续运行 |
| 改间隔泄漏旧定时器 | 改间隔后 CPU 不降反升 | reconfigure 先 invalidate 旧 timer | 用户调间隔后 |
| 全量进程数组送 SwiftUI | 列表 diff 卡顿 | 只送 Top-5 值类型 | 进程多时立即 |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| 为读他进程加 `cs.debugger`/`task_for_pid-allow` entitlement | 扩大攻击面、公证审查风险、被滥用 | 用 libproc，零特权 entitlement |
| 为「完整进程列表」引入 SMJobBless/root helper | root 提权面、helper 被替换风险（v1.0 已警示） | 接受用户态权限边界，列入 Out of Scope |
| 误开 App Sandbox 后试图绕过 process-info-listpids | 无解的沙盒拒绝，逼出更糟的架构 | 保持非沙盒 DMG 分发，构建脚本断言无 sandbox entitlement |
| 偏好迁移时信任本地损坏数据 | 越界/类型混淆导致崩溃 | decodeIfPresent + 范围校验 + 回落默认 |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| 进程名显示原始可执行路径/截断 | 看不懂是哪个 app | 优先 `proc_name`，回退 `proc_pidpath` basename，再回退 PID |
| 唤醒/插拔瞬间显示「-1 分钟」「剩余 -0:01」 | 失去信任 | 三态判定，过渡期显示「计算中…」/保留上一有效值 |
| 充放电用裸符号塞进数字（如「-12.3W」歧义） | 看不出在充还是放 | abs() 数值 + 独立充/放电图标，UI 标注约定 |
| 台式机显示空电池段或假 100% | 困惑/不信任 | 无电池则整段隐藏（优雅降级），不留空壳 |
| 改设置后状态栏闪烁/宽度跳 | 廉价感 | 同一 item 重排段 + 固定宽度，无闪烁 |
| 设置窗口打不开/藏在后面 | 以为坏了 | activate + makeKeyAndOrderFront，确保前置可输入 |

## "Looks Done But Isn't" Checklist

- [ ] **逐进程 Top-N:** 在**公证签名构建**（非 Debug 直跑）里能读到其他进程吗？→ 用 `codesign` 签好后运行验证，别只在 Xcode Run 里测
- [ ] **逐进程 CPU%:** 与 Activity Monitor 同口径吗？→ `yes>/dev/null&` 跑满一核，看该进程是否≈100% 且排到 Top
- [ ] **逐进程:** PID 退出/复用不出负值或暴涨吗？→ 反复启停一个进程观察
- [ ] **逐进程:** Popover 关闭后停止采样吗？→ 关 Popover 后看 Activity Monitor 本应用 CPU 回落
- [ ] **电池:** 唤醒/插拔后没有「-1 分钟」吗？→ 合盖唤醒、插拔电源各测一次
- [ ] **电池:** 充放电功率符号/单位对吗？→ 充电、放电、满电维持三态对照系统读数（如 `pmset -g` / Activity Monitor 能耗页）
- [ ] **电池:** 台式 Mac（无电池）整段优雅降级吗？→ 在 Mac mini/Studio 或无电池设备验证不崩、不显假值
- [ ] **电池:** Apple Silicon 与 Intel 健康度都正确吗？→ 双芯片真机各验一次
- [ ] **设置-间隔:** 改间隔后旧定时器停了吗？→ 改间隔后 Activity Monitor CPU 不升；长时间反复改不漏内存
- [ ] **设置-排序/开关:** 状态栏无闪烁、固定宽度保留吗？→ 拖动排序+开关，观察无抖动、无幽灵图标
- [ ] **设置-持久化:** 退出重开配置还在吗？schemaVersion 迁移过吗?→ 改完退出重开；模拟旧版偏好升级
- [ ] **设置窗口:** LSUIElement 下窗口前置且可输入吗？→ 从全屏 app 切回打开设置验证
- [ ] **Swift 6:** strict concurrency 全开零告警吗？→ Swift 6 language mode 编译
- [ ] **睡眠唤醒:** 新的进程/电池 Reader 唤醒后恢复吗？→ 睡眠 30 分钟唤醒，两者均在 5s 内恢复

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| 误用 task_for_pid | MEDIUM | 改写采样层为 libproc，移除 debugger entitlement，重新签名公证 |
| rusage 累计值当占用率 | LOW | 加「上一轮快照」字典 + 墙钟差求 delta |
| PID 消失/复用脏数据 | LOW | 每项查返回码 + `max(delta,0)` + (pid,starttime) 复合键 |
| 主线程全 PID 采样卡顿 | MEDIUM | 迁采样到 actor，输出 Sendable 快照，Popover 可见性门控 |
| 电池 -1 直接显示 | LOW | 加三态判定 + 唤醒延迟信任 |
| 电池符号/单位错 | LOW | 符号 sanity + 补码重解释 + mA·mV→W 封装 |
| 台式机电池崩/假值 | LOW | 加无电池探测 + 整段降级 |
| 改间隔泄漏定时器 | LOW | TimerReader 加幂等 setInterval（invalidate 旧后重建，[weak self]） |
| 状态栏重建闪烁/幽灵图标 | MEDIUM | 改为复用 item 重排段；重建处补 removeStatusItem |
| 无 schemaVersion 迁移崩溃 | MEDIUM | 引入 PreferencesStore+version+迁移链，decodeIfPresent 容错 |
| 设置窗口不显示 | LOW | NSWindowController + activate + makeKeyAndOrderFront，不切 activationPolicy |
| 新 Reader Sendable 违规 | MEDIUM | 采样层只出值类型快照，句柄不过界 |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| task_for_pid 破坏公证 | Per-Process Sampling | 公证签名构建里读到他进程；entitlements 无 debugger |
| rusage 累计当占用率 | Per-Process Sampling | 跑满一核的进程≈100% 且上榜，与 Activity Monitor 一致 |
| PID 消失/复用 | Per-Process Sampling | 反复启停进程无负值/暴涨；缓存不无限增长 |
| 权限边界/特权 helper | Per-Process Sampling | 不引入 root helper；非沙盒、可见进程内排序够用 |
| 主线程全 PID 采样 + Sendable | Per-Process Sampling + 贯穿 | Swift 6 零告警；Popover 交互不卡；关 Popover 停采样 |
| 电池 -1/-2 | Battery & Power | 唤醒/插拔无「-1 分钟」 |
| 充放电符号/单位 | Battery & Power | 三态对照系统读数，符号/瓦特正确 |
| 健康键差异 + 台式降级 | Battery & Power | 台式机整段降级不崩；AS/Intel 健康度均对 |
| 改间隔泄漏定时器 | Settings & Customization | 改间隔 CPU 不升、长跑不漏内存、不串指标 |
| 排序/开关重建闪烁 | Settings & Customization | 拖排/开关无闪烁、固定宽度保留、无幽灵图标 |
| UserDefaults 无版本迁移 | Settings & Customization | 旧版偏好升级不丢不崩；schemaVersion 生效 |
| LSUIElement 设置窗口 | Settings & Customization | 窗口前置可输入；全屏切回可打开 |
| 新 Reader 睡眠唤醒恢复 | 贯穿（并入各 Reader 成功标准） | 睡眠 30min 唤醒后进程/电池 5s 内恢复 |

## Sources

- **Apple Developer Forums**:「Getting process info for other processes?」「task_for_pid error 5」「Obtaining CPU usage by process」「How to avoid sandbox violation for process-info-listpids」—— libproc 优于 task_for_pid、沙盒下 listpids 无 entitlement 可绕过。HIGH/MEDIUM。
- **Apple Developer Documentation**: `IOPSGetTimeRemainingEstimate`、`kIOPSTimeRemainingUnknown`、`IOPSCopyPowerSourcesInfo`、Hardened Runtime。HIGH。
- **PowerManagement (aosm/opensource-apple) `BatteryTimeRemaining.c`**: wake 后剩余时间不连续、延迟发布、`kIOPMPSInvalidWakeSecondsKey`。HIGH。
- **RehabMan AppleSmartBattery 驱动 / SocPowerBuddy / macsmc-power 补丁**: 电流/功率符号与位宽、Apple Silicon 容量单位差异。MEDIUM。
- **osquery #7459**: Apple Silicon 进程 user/system time 字段异常。MEDIUM。
- **v1.0 PITFALLS.md（本仓库）**: NSStatusItem 幽灵图标、休眠唤醒冻结、高频轮询功耗、LSUIElement 窗口、固定宽度抖动、IOKit 多键回退、`max(delta,0)`、`freeifaddrs` defer、非沙盒 DMG 分发、Timer→self 循环引用。HIGH（复用既有结论）。
- **本仓库 RETROSPECTIVE.md / PROJECT.md**: TimerReader 基类、Reader-Manager-AppDelegate 分层、零依赖、Swift 6、优雅降级既定模式。HIGH。

---
*Pitfalls research for: MacStatus v2.0（逐进程 Top-N / 电池电源 / 设置可定制）*
*Researched: 2026-06-16*
