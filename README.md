# diyplay

<p align="center"><img src="app/AppIcon-1024.png" width="128" alt="Diyplay icon"></p>

A tiny macOS menu-bar app that does the one BetterDisplay job that actually matters for many setups:

1. **Identify** the connected display (name, vendor/product, current pixels)
2. **Set physical resolution** when EDID is lying (PBP, TVs, cropped panes)
3. **Offer HiDPI sizes** derived from that physical size
4. **虚拟屏 HiDPI**: intermediate HiDPI sizes the panel cannot offer, by rendering on a 2× virtual display and mirroring it onto the pane
5. **手机远程**: switch the desktop to a phone-shaped portrait resolution
6. **远程伴侣**: ask before switching when UU Remote comes to the foreground

Not affiliated with [BetterDisplay](https://github.com/waydabber/BetterDisplay). No XDR, DDC, PIP, or connection-mode matrix. A temporary virtual display is used for the phone-remote preset and for 虚拟屏 HiDPI.

Apple Silicon is the intended target. Tested on an M4 Mac mini + INNOCN 32C1U in PBP.

---

菜单栏小工具。核心不是某一台 32C1U，而是：**认屏 → 必要时改物理像素 → 再选「看起来多大」**。

## Menu

```
32C1U  ·  正常
识别  2824×2160    物理  2824×2160
────────────────
物理分辨率
  用识别到的 2824×2160
  Phone 右窗    2824×2160     (32C1U preset)
  对半 1:1      1920×2160     (32C1U preset)
  整屏 4K       3840×2160     (32C1U preset)
  自定义…
────────────────
  手机远程     720×1560（竖屏）
  更锐 / 日常 / …
────────────────
  ✓ UU 远程伴侣（打开时询问）
  启动 UU 并进入手机场景
────────────────
  重新应用    登录时启动    退出
```

Other monitors skip the 32C1U presets and get a generic HiDPI ladder from whatever physical size you set. Diyplay follows the current macOS main display, checks its real CoreGraphics mode table, and hides calculated choices that the display does not expose instead of failing after selection.

If you change the monitor OSD (for example PBP Phone → 1:1), change **physical resolution** in diyplay to match. Then sleep or unplug HDMI once if the HiDPI list does not update.

## 手机远程

选择 **手机远程 720×1560（竖屏）**，当前桌面会按手机竖屏重新布局，以 1440×3120 HiDPI 渲染、60 Hz 输出。19.5:9 的比例贴近 [iPhone 15](https://support.apple.com/zh-cn/111831)，也适合 [Xiaomi 14](https://www.mi.com/uk/support/faq/details/KA-243580/)；两款手机按比例完整显示时，理论画面利用率都超过 97%（不计远程软件工具栏、圆角和安全区域）。

- **选“日常”“更锐”等原有档位即可退出竖屏，并切到所选分辨率。** 重复点击“手机远程”保持当前档位。
- 实体显示器与临时竖屏显示器显示同一桌面，横放的实体屏会有左右留白。原来的窗口会受 macOS 的桌面尺寸调整影响。
- 手机远程模式不改写物理像素 override，也不覆盖平时记住的分辨率。正常退出应用会恢复进入前的显示设置；重新启动应用时默认使用普通桌面。
- 此模式使用 macOS 私有 `CGVirtualDisplay` 接口。实际切换失败时会尝试恢复原设置并显示错误。已通过 UU 手机端实测；如果 UU 选中了另一个显示源，可选“Diyplay 手机远程”。

验证：`swift test` 检查两款手机的比例适配。先退出已运行的 Diyplay，再执行 `DIYPLAY_LIVE_DISPLAY_TEST=1 swift test`，可实测竖屏、重复选择、自动修复不覆盖竖屏、通过“日常”退出及物理 override 保持不变；测试结束会恢复原分辨率。

### UU 远程伴侣

“UU 远程伴侣（打开时询问）”默认启用。把 UU 远程切到前台时，Diyplay 会显示一个不抢焦点的提示，可选择切换到 720×1560 手机竖屏或保持当前分辨率；选择保持后 15 分钟内不会重复提示。已经处于手机远程模式时不提示。

“启动 UU 并进入手机场景”是确定性入口：先完成竖屏切换，再打开 UU 远程。伴侣只监听 UU 主应用的前台激活，不用其常驻进程、网络连接、私有 XPC 或专有日志猜测手机会话状态。

本机 E2E 证据见 [`docs/evidence/2026-10-18-uu-companion-e2e.json`](docs/evidence/2026-10-18-uu-companion-e2e.json)：真实激活 UU、提示与冷却、保持当前、720×1560 切换及恢复均已验证。

### 手机上找不到菜单栏图标时

在 Spotlight 中搜索并打开 **Diyplay**，会弹出独立的分辨率选择面板。应用已经运行时，再次打开会唤起同一个面板，不会增加菜单栏图标。面板提供“手机远程”和原有显示大小档位，选择“日常”等档位即可退出竖屏。

菜单栏中也可选择 **分辨率面板…** 打开它。关闭面板不改变当前分辨率；登录时启动仍在后台运行。

## Install

macOS 14+, Xcode / Swift 6 toolchain.

Prebuilt Apple Silicon apps are available in [Releases](https://github.com/Coraia/diyplay/releases/latest), with SHA-256 checksums. The app bundle is ad-hoc signed and is not notarized. Source installation below also sets up write access for physical-resolution overrides.

```bash
git clone https://github.com/Coraia/diyplay.git
cd diyplay
make install
```

That builds `~/Applications/Diyplay.app`, opens the menu-bar extra, and (once, with sudo) gives your user write access to `/Library/Displays/Contents/Resources/Overrides` so later native changes do not need sudo.

Check **登录时启动** in the menu if you want it back after login.

```bash
diyplay doctor          # after install, or: .build/release/diyplay doctor
diyplay displays
diyplay native 2824x2160
diyplay res 1920x1469
```

## Status (this machine)

On an M4 mini + INNOCN 32C1U PBP Phone pane, with BetterDisplay uninstalled:

- Switching HiDPI sizes: OK
- Phone remote: 720×1560 HiDPI / 60 Hz, return through normal resolution options, and UU phone-side use verified
- Sleep / wake: OK
- Unplug / replug: OK
- Reboot: OK — WindowServer restores 2824×2160 physical + 1920×1469 HiDPI from the override alone
- Forcing HDMI connection mode (the BetterDisplay Pro `connectionMode` lever): **not implemented**. If the OS falls back to 1080p TV timing, diyplay cannot currently push 2824×2160@60 by itself.

## Warning

Writing `DisplayPixelDimensions` is a real display override. A wrong native size (2560 vs 2824, 2824×1080 vs 2824×2160) looks like a tiny sharp corner or a blurry stretch. Set physical size to the **visible pane**, not the panel’s marketing 4K.

`make install` changes ownership of the system Overrides directory so the app can write. That is a personal-machine tradeoff, not something to run on a managed set.

## HiDPI 的现实边界（2026-10-28 实测，32C1U 对半 pane）

- 面板在 PBP 对半后只有 1920×2160 像素。macOS 只肯为「2× 后台尺寸 ≤ 面板约 1.07 倍」的尺寸生成 HiDPI：这张 pane 上到 **1024×1152（后台 2048×2304）** 为止，`1280×1440`（后台 2560×2880）、`1536×1728`、`1920×2160`（后台 3840×4320）都不会出现。
- 所以「字小 + HiDPI」在物理上不存在：**像素严格 1:1 的只有两档**——`1920×2160` 1×（最小字）和 `960×1080`/`1024×1152` 2×（大字）。中间档（`1600×1800`、`1280×1440`）只有 1×，是把画布插值放大到面板，会比两端软。
- **override 里的 `default-resolution` 会当作模式表上限**：写成比物理尺寸小的值，重连后比它大的模式全部消失（症状是 `1920×2160` 从 `CGDisplayCopyAllDisplayModes` 里不见、最大只剩 1600×1800，然后就切不回 1:1 了）。所以 diyplay 写 override 时固定把 `default-resolution` 设成物理尺寸，日常档位只靠 `apply` 设置，不写进 plist。
- 菜单里的 1× 档位来自 `NativePreset.extras`，只展示、不写 override；写 override 的只有 HiDPI ladder（`overrideSlider`）。

## Handoff

[2026-10-12 项目交接与冷备恢复入口](docs/handoffs/2026-10-12.md)：当前交付、本机保留范围、NAS 恢复方式及验证边界。

## License

MIT. See [LICENSE](LICENSE).
