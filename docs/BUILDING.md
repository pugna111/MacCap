# 源码构建说明

## 环境

- macOS 14 或更高版本
- Xcode 15 或更高版本
- Swift 5.9 或更高版本
- 构建 Universal Binary 时需要同时可用 arm64 与 x86_64 macOS SDK 工具链

先确认开发工具：

```bash
xcodebuild -version
xcrun swift --version
```

如果安装了多个 Xcode，可先通过 `xcode-select` 选择正确版本。

## 运行测试

```bash
xcrun swift test
```

测试使用合成图像验证像素转换、纵向位移匹配、重复纹理拒绝、到底识别和最大高度限制。

## 开发构建

```bash
xcrun swift build
xcrun swift run MacCap
```

`swift run` 的路径可能随构建变化，macOS 权限会因此难以复用。需要测试屏幕录制和辅助功能权限时，优先组装固定 Bundle ID 的 App：

```bash
bash scripts/build-app.sh
open dist/MacCap.app
```

`build-app.sh` 会运行测试、分别构建 arm64 和 x86_64、使用 `lipo` 合并、生成图标并签名 App。未设置签名身份时使用 ad-hoc 签名。

## 生成测试 DMG

```bash
bash scripts/create-dmg.sh
```

当前版本的产物：

```text
dist/MacCap.app
dist/MacCap-1.0.0.dmg
```

重新构建会替换这两个产物及 `build/` 中的中间文件。`dist/`、`build/` 和 `.build/` 均不会提交到 Git。

## 运行验证建议

至少验证：

- Safari 或 Chrome 的静态长页面
- Finder 和 Preview 中的可滚动内容
- Apple Silicon；发布 Universal 包时还应验证 Intel Mac
- Retina 屏和外接非 Retina 屏
- 权限首次拒绝、重新授权和重启 App
- 快捷键冲突、更换快捷键和捕获中停止
- 固定顶部/底部控件、动态内容和页面底部
- 在“活动监视器”或 Instruments 中观察待机、捕获、PNG 保存和保存完成后的内存变化

自动化测试不能替代这些真实应用场景。

## 资源边界

当前默认策略固定为：

```text
单帧选区：最多 10,000,000 像素
最终输出：最多 20,000,000 像素且不高于 30,000 px
捕获时长：最多 120 秒
匹配采样：每个候选位移目标不超过约 1,024 个灰度样本
捕获间隔：默认 0.35 秒，最低 0.15 秒
```

拼接器逐帧工作，不保留全部历史截图；它会保留最终 RGBA 输出、上一帧及灰度匹配数据。PNG 保存阶段仍需要 CGImage、Data 和 ImageIO 临时内存，因此 `20,000,000 × 4` 字节只是最终 RGBA 像素缓冲的理论大小，不是进程峰值 RSS。

实机验收时至少观察：

1. 待机数分钟时 CPU 应接近空闲，内存不应持续增长。
2. 连续捕获时不会出现并发帧堆积，达到像素、时长或帧数上限后能够停止。
3. 保存 PNG 后临时编码内存应被释放，应用回到稳定待机状态。
4. 取消框选、停止捕获和取消保存后不应留下继续运行的截图或编码任务。

在没有真实 Mac 测量结果前，不应对外承诺固定 RSS 数值或特定内存容量机型“无压力”。

## 常见构建问题

**脚本提示只能在 macOS 构建**  
AppKit、ScreenCaptureKit、`codesign` 和 `hdiutil` 只在 macOS/Xcode 环境可用，Windows 或 Linux 不能生成可运行的 MacCap App。

**权限每次构建后丢失**  
优先使用 `scripts/build-app.sh` 生成固定 Bundle ID 和路径的 App，不要反复用不同临时路径运行 `swift run`。

**x86_64 构建失败**  
确认当前 Xcode 仍包含 Intel macOS 构建支持，并检查 `xcode-select -p` 是否指向预期的 Xcode。
