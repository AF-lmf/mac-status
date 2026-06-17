# MacStatus

MacStatus 是一个轻量级 macOS 菜单栏系统监控应用。CPU / GPU / 内存 / 网络实时显示在菜单栏；点开弹窗还能看到电池全貌、实时功率和最吃 CPU/内存的进程；并提供独立设置窗口，指标开关、拖动排序、告警阈值、配色、文字模式都能**即时**定制。纯菜单栏应用、零第三方运行时依赖，数据全部来自 macOS 系统 API。

![MacStatus menu bar preview](docs/images/menubar-preview.png)

## 功能

### 菜单栏（常驻）

- 实时展示 CPU、GPU、内存压力/使用率、网络上下行速率。
- 按阈值给数值上色，资源压力一眼可见。
- 三种文字模式：**详细 / 紧凑 / 百分比**，可在设置中切换。
- 纯菜单栏应用（无 Dock 图标），支持登录时启动、睡眠/唤醒后自动恢复刷新。

紧凑模式示例：

```text
C 12%  G 34%  M OK 68%  ↓2.1M ↑512K
```

### 弹窗仪表盘（点击菜单栏项）

- CPU / 内存 / 网络 / GPU 四张卡片，各带最近 60 个采样点的趋势 sparkline。
- **电池区（笔记本）** —— 台式机无电池时整区优雅隐藏：
  - 电量百分比、充电状态（充电中 / 电源接入 / 已充满 / 使用电池）、剩余时间 / 距充满、健康度与循环数。
  - **电池功率**：放电时用 SMC `PPBR` 实时传感器（跟手），充电时用电量计的真实充电功率。
  - **整机功耗**：SMC `PSTR` 系统总功率，接入电源时也能看到。
- **进程 Top 5** —— CPU 占用、内存占用各一组。仅在弹窗打开时按需采样，关闭即停，**没有 7×24 常驻开销**。

### 设置窗口（右键菜单栏项 → 偏好设置）

- 指标开关 + 拖动排序，改动**即时**反映到菜单栏。
- 弹窗区块开关（电池区 / 进程区）。
- 每指标告警阈值（警告 / 严重）。
- 每指标配色（ColorPicker，警告色 / 严重色，可一键恢复默认）。
- 刷新间隔、登录时启动。
- 所有改动即时生效并跨重启持久化，无需重新启动应用。

## 系统要求

- macOS 14 Sonoma 或更高版本。
- 从源码构建需 Xcode 26 或更高版本。

## 从源码构建

```bash
git clone https://github.com/AF-lmf/mac-status.git
cd mac-status
xcodebuild -project MacStatus/MacStatus.xcodeproj \
  -scheme MacStatus \
  -configuration Release \
  -derivedDataPath build.noindex \
  build
open build.noindex/Build/Products/Release/MacStatus.app
```

也可以直接用 Xcode 打开：

```bash
open MacStatus/MacStatus.xcodeproj
```

构建并直接安装到 `/Applications` 再重启（本机日常使用）：

```bash
scripts/install-local.sh
```

## 使用方式

1. 启动 `MacStatus.app`，菜单栏出现系统状态文本。
2. **左键**点击菜单栏项 → 弹出仪表盘（卡片趋势、电池、功率、进程 Top 5）。
3. **右键**点击菜单栏项 → 偏好设置 / 退出。
4. 在设置窗口里开关指标、拖动排序、调阈值与配色、切换文字模式，改动立即生效。
5. 应用会尝试注册为登录项，之后登录 macOS 时自动启动。

## 给别人使用（无证书 / 无开发者账号）

**可以。** 不需要付费 Apple Developer 账号，也不需要 Developer ID 证书，就能把 app 压成 zip 发给别人。Xcode 构建时默认做 ad-hoc 签名（“Sign to Run Locally”），这让 app 能在别人的 Apple Silicon Mac 上运行。

构建并打包：

```bash
xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus \
  -configuration Release -derivedDataPath build.noindex build
ditto -c -k --keepParent \
  build.noindex/Build/Products/Release/MacStatus.app \
  MacStatus.zip
```

**代价**：因为没有 Developer ID 签名、也没经过 Apple 公证，别人下载后（尤其经浏览器 / AirDrop / 邮件传输，文件会被打上 `com.apple.quarantine` 隔离标记）首次打开会被 Gatekeeper 拦截，提示“Apple 无法验证 MacStatus 不包含恶意软件”。接收方**手动放行一次**即可，三选一：

- **右键打开**：在 Finder 里右键 `MacStatus.app` → 打开 → 在弹窗里再次点“打开”。
- **系统设置**：系统设置 → 隐私与安全性 → 下方“仍要打开”。
- **终端**移除隔离标记：

  ```bash
  xattr -dr com.apple.quarantine /path/to/MacStatus.app
  open /path/to/MacStatus.app
  ```

这种方式适合发给同事、朋友小范围使用。若要面向不特定用户公开分发、做到**双击即开、零警告**，则需要下面的签名 + 公证流程。

## 公开分发（Developer ID 签名 + 公证）

要让任意 Mac 用户下载后无障碍打开，需要 Apple Developer Program（$99/年）的 `Developer ID Application` 证书，并完成 notarization 与 staple。

首次发布前，把公证凭据保存到钥匙串：

```bash
xcrun notarytool store-credentials MacStatusNotaryProfile \
  --apple-id "you@example.com" \
  --team-id "YOURTEAMID" \
  --password "app-specific-password"
```

之后用发布脚本构建、签名、公证、staple 并生成最终 zip：

```bash
TEAM_ID=YOURTEAMID \
SIGNING_IDENTITY="Developer ID Application: Your Name (YOURTEAMID)" \
NOTARY_PROFILE=MacStatusNotaryProfile \
VERSION=2.0 \
scripts/package-release.sh
```

脚本输出 `dist/MacStatus-2.0.zip`，即可上传到 GitHub Releases。用户下载解压后把 `MacStatus.app` 拖进 `/Applications` 即可，不会有 Gatekeeper 提示。

## 数据来源

- **CPU**：Mach `host_statistics`。
- **内存**：Mach VM statistics 与 memory pressure level。
- **GPU**：IOKit `IOAccelerator` performance statistics，读取不到时降级显示。
- **网络**：BSD `getifaddrs` 网络接口计数器。
- **电池状态**：IOKit Power Sources（电量、充电状态、时间估算）+ `AppleSmartBattery` IORegistry（健康度、循环数、充电功率）。
- **功率**：SMC（System Management Controller）键 —— `PSTR`（整机总功率）、`PPBR`（电池放电功率）。无需任何额外权限（entitlement）。
- **进程 Top-N**：`libproc`（`proc_listpids` + `proc_pid_rusage`），无需 `task_for_pid`、无额外权限。

## 说明

MacStatus 定位为小而直接的状态栏工具：

- GPU 数据在部分机型或系统版本上可能不可用，会以降级状态显示；内存百分比基于物理内存页统计估算，不等同于 Activity Monitor 的完整内存压力算法。
- 电池区与整机功耗位于弹窗电池区内，**仅在有电池的机型（笔记本）显示**；台式机无电池时整区隐藏。
- 电池功率读数：放电方向用 SMC 实时传感器，跟手；充电方向用电池电量计，准确但更新较慢（充电功率本就缓慢变化）。
