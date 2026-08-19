# 上传 GitHub 与 Actions 构建

这份说明用于把 MacCap 源码上传到 GitHub，并通过 macOS runner 生成 ad-hoc 测试 DMG。

## 1. 准备仓库内容

解压 `MacCap-source-1.0.0.zip`，上传解压后的文件和目录，不要只上传 ZIP。必须包含隐藏目录：

```text
.github/workflows/build-macos.yml
.github/workflows/ci.yml
```

`dist/`、`build/` 和 `.build/` 已在 `.gitignore` 中排除，不应提交构建产物。

## 2. 首次推送

先在 GitHub 创建一个空仓库，不要让网页自动生成 README 或 LICENSE。然后在源码根目录执行：

```bash
git init
git add .
git commit -m "Initial MacCap source"
git branch -M main
git remote add origin https://github.com/<your-account>/MacCap.git
git push -u origin main
```

将 `<your-account>` 替换为自己的 GitHub 用户名或组织名。如果目录原本已经是 Git 仓库，请不要再次运行 `git init`，只需核对远程地址后推送。

## 3. 自动检查

推送 `main` 或创建 Pull Request 后，`macOS CI` 会执行：

- `swift build`
- `swift test`
- `plutil -lint Resources/Info.plist`
- Bash 脚本语法检查

首次上传后应先确认该工作流通过。它验证编译和测试，但不代替真实应用的权限、滚动和多显示器测试。

## 4. 手动生成测试 DMG

手动工作流文件必须已经存在于仓库默认分支。操作步骤：

1. 打开 GitHub 仓库的 **Actions**。
2. 在左侧选择 **Build macOS DMG**。
3. 点击 **Run workflow**，选择默认分支并确认运行。
4. 等待任务变为绿色成功状态。
5. 打开本次运行，在 **Artifacts** 下载 `MacCap-DMG`。
6. 解压浏览器下载的 artifact ZIP，里面才是 `MacCap-1.0.0.dmg`。

参考 GitHub 官方文档：[手动运行工作流](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow) 和 [下载工作流产物](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts)。

## 5. 测试包与正式发布的区别

`Build macOS DMG` 不读取 Developer ID 证书或公证凭据。它生成的 App 使用 ad-hoc 签名，DMG 没有正式发行签名和 Apple 公证，因此：

- 仅适合开发者自测。
- Gatekeeper 可能阻止首次打开。
- Actions artifact 会过期，并且下载权限受仓库权限约束。
- 不应把 artifact 当作面向普通用户的长期下载地址。

只有确认文件来自你自己的工作流运行时，才可按 Apple 的 [打开来自身份不明开发者的 App](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac) 指引，在“系统设置 → 隐私与安全性”中选择“仍要打开”。不要关闭 Gatekeeper。

面向普通用户发布时，请在持有证书的 Mac 上按照 [正式发布说明](RELEASING.md) 生成已签名、公证并装订票据的 DMG，再把它上传到 GitHub Release。

## 6. 发布源码和二进制

建议每个正式版本的 GitHub Release 包含：

- 已签名并公证的 `MacCap-<version>.dmg`
- DMG 的 SHA-256
- GitHub 自动生成的 Source code 压缩包
- 简短的版本说明和已知限制

不要上传证书、私钥、Apple ID 密码、notarytool 配置文件或本机钥匙串内容。
