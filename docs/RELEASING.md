# 正式发布说明

正式发布只能在联网的 Mac 上完成。当前 GitHub Actions 只生成 ad-hoc 测试包，不会处理发布证书或公证凭据。

## 前置条件

- Xcode 15 或更高版本
- 有效的 Apple Developer Program 会员资格
- `Developer ID Application` 证书及私钥已经安装到钥匙串
- Apple ID 的 app-specific password，用于配置 notarytool

确认签名身份：

```bash
security find-identity -v -p codesigning
```

## 版本号

发布前更新 `Resources/Info.plist`：

- `CFBundleShortVersionString`：用户可见版本，例如 `1.0.0`；同时决定 DMG 文件名。
- `CFBundleVersion`：构建号，每次发布都应递增。

如果手工创建源码归档，还要同步源码 ZIP 的文件名。

## 保存公证凭据

```bash
xcrun notarytool store-credentials "MacCap-notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID"
```

命令会交互式要求 app-specific password。不要把密码写在命令、脚本、GitHub 仓库或日志中。

## 构建、签名与公证

```bash
export MACCAP_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export MACCAP_NOTARY_PROFILE="MacCap-notary"
bash scripts/release.sh
```

脚本执行以下流程：

1. 运行单元测试。
2. 构建 arm64 和 x86_64 并合成 Universal App。
3. 使用 Hardened Runtime 和 Developer ID 签名 App。
4. 创建并签名 DMG。
5. 使用 `notarytool` 提交并等待 Apple 公证。
6. 使用 `stapler` 装订并验证公证票据。
7. 使用 Gatekeeper 执行最终校验。

成功产物为：

```text
dist/MacCap-<version>.dmg
```

## 发布清单

1. 确认 `swift test` 通过。
2. 确认两个版本字段正确。
3. 运行 `bash scripts/release.sh` 并确认所有校验成功。
4. 在受支持的 Apple Silicon 和 Intel Mac 上完成安装、权限和长截图测试。
5. 计算 SHA-256：

   ```bash
   shasum -a 256 dist/MacCap-<version>.dmg
   ```

6. 创建与用户版本一致的 Git tag，例如 `v1.0.0`。
7. 创建 GitHub Release，上传正式 DMG，附上 SHA-256、版本说明和已知限制。

不要把 Actions 生成的 ad-hoc artifact 误标为正式发行包。
