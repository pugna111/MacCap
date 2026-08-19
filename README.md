# MacCap 长截图

MacCap 是一个原生 macOS 菜单栏长截图工具。框选应用中的滚动区域后，它会自动向下滚动、匹配相邻画面的重叠内容，并将结果保存为 PNG。全局快捷键、捕获间隔和最大帧数都可以在设置中调整。

> 当前交付包含完整源码、测试和构建脚本，但不包含已经在 macOS 上验证的安装包。仓库内的 GitHub Actions 可以生成 ad-hoc 测试 DMG；面向普通用户发布前，仍应在 Mac 上完成 Developer ID 签名、公证和实机测试。

## 功能

- 框选单个显示器中的纵向滚动区域
- 自动滚动并拼接成长 PNG
- 默认全局快捷键 `Control + Option + L`
- 在应用内重新录制全局快捷键
- 可调捕获间隔和最大帧数
- 待机采用事件驱动，不启动轮询、定时截图或常驻屏幕流
- 逐帧串行处理，不缓存全部截图帧
- 支持 Apple Silicon 与 Intel 的 Universal Binary
- 基于 AppKit、ScreenCaptureKit 和 Swift Package Manager，无第三方运行时依赖
- 截图只保存在本机，不上传内容

## 系统要求

- macOS 14 Sonoma 或更高版本
- Apple Silicon 或 Intel Mac
- 从源码构建：Xcode 15 或更高版本，Swift 5.9 或更高版本

## 安装

### 正式发布包

正式发行时，应从项目的 GitHub Releases 下载已经签名并公证的 `MacCap-<version>.dmg`：

1. 打开 DMG。
2. 将 `MacCap.app` 拖到 `Applications`。
3. 弹出 DMG，然后从“应用程序”目录启动 MacCap。

当前源码交付尚未包含这种正式 DMG，不应把源码 ZIP 当作安装包。

### Actions 测试包

仓库中的 `Build macOS DMG` 工作流生成 ad-hoc 测试包，仅适合开发和自测。它没有 Developer ID 签名或 Apple 公证，macOS 可能显示“无法验证开发者”。只有在确认文件来自你自己的工作流运行时，才可在“系统设置 → 隐私与安全性”中选择“仍要打开”；不要关闭 Gatekeeper。

完整步骤见 [上传 GitHub 与 Actions 构建](docs/GITHUB.md)。

## 使用方法

1. 先把目标页面滚动到希望开始截图的位置；MacCap 只会从当前位置向下滚动。
2. 启动 MacCap，菜单栏会出现截图图标。
3. 按 `Control + Option + L`，或从菜单选择“开始长截图”。
4. 按系统提示授予“屏幕与系统音频录制”和“辅助功能”权限。
5. 框选应用内的可滚动内容区，并让选区中心落在实际滚动区域内。尽量避开工具栏、侧栏和悬浮控件。
6. 捕获期间不要手动滚动、缩放、移动窗口或切换显示器。
7. 静态页面滚动到底且画面不再变化时会自动停止。也可以再次按快捷键或点击浮窗“停止”。
8. 在保存面板中选择 PNG 的保存位置。

框选时按 `Esc` 可以取消。准备阶段再次按快捷键会取消任务，捕获阶段再次按快捷键会停止并尝试保存已经可靠拼接的部分。

## 设置

从菜单栏选择“设置…”：

| 设置 | 默认值 | 范围或要求 |
| --- | --- | --- |
| 全局快捷键 | `Control + Option + L` | 必须包含 `Command` 或 `Control` |
| 捕获间隔 | `0.35 秒` | `0.15–1.00 秒` |
| 最大帧数 | `300` | `10–2000` |

若新快捷键与其他应用冲突，MacCap 会保留原快捷键。录制快捷键时按 `Esc` 表示取消录制。

## 资源控制

MacCap 的待机路径只保留菜单栏、全局快捷键和系统通知监听，没有轮询、常驻定时器或持续运行的 ScreenCaptureKit 流。开始长截图后，截图、滚动和匹配严格串行执行，不会同时堆积多帧任务。

捕获阶段采用以下固定边界：

- 单帧选区最多 `1000 万像素`；更大的选区会在开始前被拒绝。
- 最终输出最多 `2000 万像素`，高度同时不超过 `30,000 px`。
- 单次捕获最长 `120 秒`，并继续受设置中的最大帧数限制。
- 只长期保留已拼接输出、上一帧和匹配所需的灰度数据，不缓存所有原始帧。
- 截图直接写入拼接像素缓冲，并复用上一帧灰度结果，减少逐帧内存复制和 CPU 计算。

这些是代码中的图像规模和执行时间边界，不等于进程 RSS 的精确上限。CGImage、Retina 截图、数组扩容和 PNG 编码仍会使用临时内存；实际峰值必须在 Mac 上用 Instruments 或“活动监视器”测量后才能给出。

## 权限与隐私

长截图需要两项 macOS 权限：

- 屏幕与系统音频录制：读取所选区域的像素。
- 辅助功能：向目标应用发送滚动事件。

两项权限都必须开启。若刚授权屏幕录制后仍提示未授权，请完整退出并重新启动 MacCap。MacCap 不会绕过系统权限，也不会上传截图或页面内容。

## 在 Mac 上生成测试 DMG

在源码根目录运行：

```bash
bash scripts/create-dmg.sh
```

脚本会运行单元测试，分别构建 arm64 和 x86_64，合成 Universal Binary，生成应用图标，执行 ad-hoc 签名并创建 DMG。当前版本 `1.0.0` 的输出为：

```text
dist/MacCap-1.0.0.dmg
```

更完整的环境检查和开发命令见 [源码构建说明](docs/BUILDING.md)。

## 使用 GitHub Actions 生成测试 DMG

将解压后的源码内容提交到 GitHub 默认分支，并确认隐藏目录 `.github/workflows/` 也已上传。然后：

1. 打开仓库的 **Actions** 页面。
2. 选择 **Build macOS DMG**。
3. 点击 **Run workflow**。
4. 等待任务成功，在运行摘要的 **Artifacts** 中下载 `MacCap-DMG`。
5. 浏览器下载的是 artifact ZIP；再次解压后可得到 `MacCap-1.0.0.dmg`。

该工作流不会读取签名证书或公证凭据，只生成 ad-hoc 测试包。Actions artifact 会过期，也不能替代 GitHub Release。详细说明见 [GitHub 上传与构建指南](docs/GITHUB.md)。

## 正式签名与公证

正式发布必须在联网的 Mac 上进行，并满足：

- 已安装 Xcode。
- 钥匙串中已有 `Developer ID Application` 证书及其私钥。
- 已加入 Apple Developer Program，并准备好公证凭据。

仓库的 `scripts/release.sh` 会签名 App 和 DMG、启用 Hardened Runtime、提交 Apple 公证、装订公证票据并执行 Gatekeeper 校验。当前 GitHub Actions 不执行正式发布流程。

```bash
export MACCAP_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"

xcrun notarytool store-credentials "MacCap-notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID"

export MACCAP_NOTARY_PROFILE="MacCap-notary"
bash scripts/release.sh
```

`notarytool` 会安全地提示输入 Apple ID 的 app-specific password；不要把密码或证书写入仓库。完整发布清单见 [正式发布说明](docs/RELEASING.md)。

## 开发与测试

项目使用 Swift Package Manager：

```bash
swift test
swift build
swift run MacCap
```

直接 `swift run` 适合开发，但系统权限可能绑定到临时可执行文件路径。测试屏幕录制和辅助功能权限时，建议运行 `bash scripts/build-app.sh`，使用固定 Bundle ID 的 `dist/MacCap.app`。

推送到 `main` 或创建 Pull Request 时，`macOS CI` 工作流会在 macOS runner 上执行构建、单元测试、Plist 和脚本语法检查。

## 源码结构

```text
.github/workflows/      macOS CI 与手动 DMG 构建
Resources/              Info.plist
Sources/MacCap/         菜单栏应用、截图、权限、快捷键和界面
Sources/MacCapCore/     像素匹配及长图拼接算法
Tests/MacCapCoreTests/  合成图像单元测试
docs/                   GitHub、构建和发布文档
scripts/                App、DMG、签名和公证脚本
```

## 已知边界

- 只支持单个显示器内的纵向向下滚动，不支持跨屏或横向长截图。
- 选区必须至少为 `24 × 24 pt`。
- 静态页面不再变化时可以自动识别底部；动态元素、懒加载和无限列表可能改为因匹配失败、最大帧数或输出上限而停止。
- DRM 或受保护内容可能被 macOS 截成黑色。
- 视频、动态广告、固定悬浮层和大面积重复纹理会降低拼接可靠性。
- 某些应用不会接受合成滚轮事件。
- 单帧选区、输出像素和捕获时长受“资源控制”中的固定预算限制；选区越宽、Retina 分辨率越高，可拼接高度越短。
- 匹配器会通过置信度和唯一性检查拒绝部分不可靠结果，但像素算法无法保证所有页面都正确，保存后仍应检查长图。

## 常见问题

**授予屏幕录制权限后仍然无法截图？**  
完整退出 MacCap 后重新启动，并在“系统设置 → 隐私与安全性”中确认两项权限均已开启。

**页面没有滚动？**  
确认选区中心位于目标应用的实际滚动内容中，并检查“辅助功能”权限。部分应用不接受合成滚轮事件。

**为什么提前停止？**  
可能是画面匹配置信度不足、页面包含动态内容、达到最大帧数或触发输出尺寸上限。MacCap 会让你保存已经接受的部分。

## 当前验证状态

本次源码交付是在 Windows 工作区完成的。该环境没有 AppKit、macOS SDK、`codesign` 或 `hdiutil`，因此尚未生成、签名或在 macOS 实机验证 `MacCap-1.0.0.dmg`。当前交付只包含源码归档；上传 GitHub 后请先让 `macOS CI` 通过，再生成测试 DMG，并在发布前完成 Mac 实机验证。

## 许可证

仓库当前未附带开源许可证。公开可见源码并不自动授予复制、修改或再分发权；公开发布前应由仓库所有者选择并添加合适的 `LICENSE`。
