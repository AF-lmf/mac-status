# MacStatus

MacStatus 是一个轻量级 macOS 菜单栏系统监控应用。它把 CPU、GPU、内存压力/使用率和网络上下行速率直接显示在菜单栏里，适合希望不打开窗口也能持续观察系统状态的开发者、运维和重度 macOS 用户。

![MacStatus menu bar preview](docs/images/menubar-preview.png)

## 功能

- 菜单栏实时展示 CPU、GPU、内存和网络状态。
- 内存显示采用 `M OK 68%` 这种格式，同时保留压力等级和使用百分比。
- CPU、GPU、内存会按阈值上色，方便快速发现资源压力。
- 网络显示实时下行/上行速率。
- 纯菜单栏应用，无 Dock 图标。
- 支持登录时启动。
- 支持睡眠/唤醒后的自动恢复刷新。
- 无第三方运行时依赖，核心数据来自 macOS 系统 API。

当前菜单栏格式示例：

```text
C 12%  G 34%  M OK 68%  ↓2.1M ↑512K
```

## 系统要求

- macOS 14 Sonoma 或更高版本
- Xcode 26 或更高版本用于源码构建

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

## 使用方式

1. 启动 `MacStatus.app`。
2. 菜单栏会出现系统状态文本，例如 `C 12% G 34% M OK 68% ↓2.1M ↑512K`。
3. 右键点击菜单栏项目可以退出应用。
4. 应用会尝试注册为登录项，之后登录 macOS 时自动启动。

如果使用本机源码构建出来的未公证包，传到其他 Mac 后可能会被 Gatekeeper 拦截并提示“Apple 无法验证 MacStatus.app”。公开分发请使用下面的 Developer ID 签名和公证流程。

## Release 包

直接把 `build.noindex/Build/Products/Release/MacStatus.app` 压成 zip 只适合本机调试。要让其他 Mac 正常打开，需要 Apple Developer Program 的 `Developer ID Application` 证书，并完成 notarization 和 staple。

首次发布前，先把 Apple 公证凭据保存到钥匙串：

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
VERSION=1.0 \
scripts/package-release.sh
```

发布到 GitHub Releases 的文件应使用脚本输出的 `dist/MacStatus-1.0.zip`。Release 用户下载后，解压并把 `MacStatus.app` 拖到 `/Applications` 即可。

如果只是把自己构建的包临时放到自己的另一台 Mac 上测试，并且确认来源可信，可以在那台 Mac 上移除隔离标记后打开：

```bash
xattr -dr com.apple.quarantine /Applications/MacStatus.app
open /Applications/MacStatus.app
```

## 数据来源

- CPU：Mach `host_statistics`
- 内存：Mach VM statistics 与 memory pressure level
- GPU：IOKit `IOAccelerator` performance statistics，读取不到时会降级显示
- 网络：BSD `getifaddrs` 网络接口计数器

## 说明

MacStatus 目前定位为小而直接的状态栏工具。GPU 数据在部分机器或系统版本上可能不可用，会以降级状态显示；内存百分比是基于物理内存页统计估算的使用率，不等同于 Activity Monitor 的完整内存压力算法。
