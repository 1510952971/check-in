# GitHub Release 与签名配置

需要按步骤操作时，请优先阅读：

- [新版本上传与发布操作手册](RELEASE_MANUAL.md)

本文保留签名和自动化发布的简要技术说明。

## 仓库要求

应用当前使用无令牌的 GitHub Releases API，因此更新仓库需要是公开仓库。
正式构建通过 Gradle 属性嵌入仓库地址：

```text
-PgithubUpdateRepo=owner/repository
```

GitHub Actions 已自动使用 `${{ github.repository }}`。
本仓库的 `gradle.properties` 已将默认值配置为 `1510952971/check-in`。

## 本地签名构建

运行：

```powershell
powershell.exe -ExecutionPolicy Bypass `
  -File .\scripts\bootstrap-and-build.ps1 -Release
```

首次执行会在 `.signing/` 下生成 `clockin-release.p12` 和本地签名配置。
脚本不会把真实口令写进受版本控制的文件。请安全备份整个 `.signing/`
目录；丢失证书后无法为已安装用户提供覆盖升级。

## 配置签名 Secrets

在 GitHub 仓库的 `Settings -> Secrets and variables -> Actions` 中创建：

```text
CLOCKIN_KEYSTORE_BASE64
CLOCKIN_KEYSTORE_PASSWORD
CLOCKIN_KEY_ALIAS
CLOCKIN_KEY_PASSWORD
```

在 Windows PowerShell 中生成证书的 Base64 文本：

```powershell
[Convert]::ToBase64String(
    [IO.File]::ReadAllBytes(".signing\clockin-release.p12")
) | Set-Clipboard
```

将剪贴板内容保存到 `CLOCKIN_KEYSTORE_BASE64`。签名文件和密码不得提交到
git；`.gitignore` 已排除 `.signing/`。

## 发布新版本

1. 在 `app/build.gradle` 增加 `versionCode` 并修改 `versionName`。
2. 本地运行调试构建、Lint、正式签名构建和模拟器测试。
3. 提交并推送代码。
4. 创建与 `versionName` 相同的标签，例如：

```powershell
git tag v1.3.0
git push origin v1.3.0
```

工作流会验证标签版本、构建同签名 APK、生成 SHA-256 文件并发布 Release。
标签与 `versionName` 不一致时会主动失败，避免客户端重复提示错误版本。

## 签名连续性

所有升级 APK 必须使用同一正式证书。证书丢失后，Android 不允许覆盖安装
现有应用。请在安全位置备份证书和密码，且不要通过聊天、Issue 或普通文件
分享。
