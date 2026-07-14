# Android 签名管理器

这是一个面向 Windows 的 Android 软件签名证书管理工具，用来集中管理多个
Android 应用的 `.p12` 证书、证书密码、GitHub Actions Secrets 名称和证书
SHA-256 指纹。

工具的设计目标是：

- 每个 Android 应用使用独立签名证书。
- 日常使用时，密码保存在当前 Windows 用户的凭据管理器中。
- 可导出完整加密便携套件，复制到 NAS、移动硬盘或其他电脑。
- 换电脑恢复时，自动重建证书库和 Windows 凭据。
- 备份和恢复都会校验证书指纹以及每个文件的 SHA-256。
- 真实证书、密码和 Base64 内容不得提交到 GitHub。

## 快速启动

双击：

```text
Start-AndroidSigningManager.cmd
```

也可以在 PowerShell 中运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA `
  -File .\AndroidSigningManager.ps1
```

默认证书库位于：

```text
%USERPROFILE%\Documents\Android-Signing-Vault
```

如需使用其他本机证书库，可设置环境变量：

```powershell
$env:ANDROID_SIGNING_VAULT = "D:\Android-Signing-Vault"
```

## 依赖

工具会自动查找以下软件：

1. Java 17 的 `keytool.exe`
2. GnuPG 的 `gpg.exe`

安装 Git for Windows 后通常已经带有 GnuPG。Java 可以来自系统 `PATH`、
Android Studio，或 Check in 项目下的 `.tools\jdk`。

需要完全离线携带运行环境时，可以在工具目录中准备：

```text
runtime\
├─ jdk\...\bin\keytool.exe
└─ gnupg\bin\gpg.exe
```

工具会优先检测这些相对目录，因此整个文件夹移动后仍然有效。

## 新建证书

1. 点击“新建证书”。
2. 填写软件名称、Android 包名、GitHub 仓库和 Secret 前缀。
3. 工具生成 100 年有效期的 RSA 2048 位 PKCS12 证书。
4. 工具自动生成随机密码并保存到 Windows 凭据管理器。
5. 工具立即读取证书并记录 SHA-256 指纹。
6. 新证书创建后，立刻执行一次“导出便携套件”。

Android 包名创建后不可修改。已经发布的软件也不得更换签名证书，否则旧用户
无法安装后续更新。

## 导入已有证书

点击“导入证书”，填写：

- 软件名称和 Android 包名
- GitHub 仓库，格式为 `所有者/仓库`
- GitHub Actions Secret 前缀
- 证书别名
- `.p12` 或 `.pfx` 文件
- 证书密码和密钥密码

工具会先使用密码读取证书并计算 SHA-256，验证通过后才登记。

## 导出便携套件

点击“导出便携套件”后：

1. 输入或选择 NAS、移动硬盘或其他安全目录。
2. 输入两次便携备份主密码。
3. 工具检查证书库中的每个证书和本机密码。
4. 工具把所有证书、登记信息和恢复密码写入临时 ZIP。
5. GnuPG 使用 AES-256 和主密码把 ZIP 加密为 OpenPGP 文件。
6. 工具立即重新解密刚生成的文件。
7. 工具逐文件核对 SHA-256、长度、应用数量和证书指纹。
8. 只有完整自检通过后，便携套件才会出现在目标目录。
9. 明文临时文件在 `finally` 清理流程中删除。

支持的目标路径形式：

```text
E:\Android-Backup
\\NAS\共享目录\Android-Backup
smb://NAS/共享目录/Android-Backup
```

`smb://` 地址会自动转换为 Windows UNC 路径。路径必须具体到实际共享文件夹，
不能只选择“此电脑”“网络”或 NAS 设备名称。

便携套件目录示例：

```text
Android-Signing-Manager-Portable-20260714-220000\
├─ AndroidSigningManager.ps1
├─ SigningVault.psm1
├─ Start-AndroidSigningManager.cmd
├─ strings.zh-CN.json
├─ README.md
├─ CHECKSUMS.sha256
└─ vault-backup.asmvault.gpg
```

`vault-backup.asmvault.gpg` 是关键数据文件，内部包含：

- 所有应用的 `.p12` 证书
- 所有 `metadata.json` 登记信息
- 所有证书和密钥密码
- 证书 SHA-256 指纹
- 逐文件完整性清单

主密码不在便携套件中，也不会写入 Windows 凭据管理器、GitHub、脚本参数或日志。

## 在另一台电脑恢复

1. 从 NAS 或移动硬盘复制整个便携套件目录。
2. 确保新电脑有 Java 17 和 GnuPG，或在 `runtime` 中放入便携运行环境。
3. 双击 `Start-AndroidSigningManager.cmd`。
4. 点击“恢复便携备份”。
5. 选择套件中的 `vault-backup.asmvault.gpg`。
6. 输入创建备份时使用的主密码。
7. 工具先验证 OpenPGP 解密和归档 SHA-256。
8. 工具逐个验证证书密码和证书指纹。
9. 工具把证书恢复到新电脑的证书库。
10. 工具把每个应用的密码重新写入新电脑的 Windows 凭据管理器。
11. 恢复完成后，在列表中逐个点击“验证证书”。
12. 再导出一份新的便携套件，确认新电脑具备完整备份能力。

如果目标证书库已经有相同包名：

- 证书 SHA-256 和别名一致时，不覆盖本地文件，只恢复密码并重新验证。
- 指纹或别名不一致时立即停止，防止错误证书覆盖正式证书。

## 主密码管理

主密码是便携备份的唯一解密钥匙。忘记主密码后，工具和 GitHub 都无法恢复
加密包中的密码。

建议：

1. 使用不少于 16 位的随机主密码。
2. 保存到可靠的密码管理器。
3. 在独立位置保存一份应急恢复记录，例如密封纸质记录。
4. 不要把主密码放在与备份包相同的文本文件中。
5. 不要通过聊天、邮件正文或 Git 仓库传输主密码。

## 备份策略

建议执行 3-2-1 备份：

1. 保留至少 3 份便携套件。
2. 使用至少 2 种介质，例如 NAS 和移动硬盘。
3. 至少 1 份离线保存，平时不连接电脑。

推荐实际布局：

```text
主力机：最近两代便携套件
NAS：最近三代便携套件
离线移动硬盘：每次发布正式版本后更新一份
密码管理器：主密码
```

以下情况必须立即重新备份：

- 新建或导入一个签名证书后
- 修改证书登记信息后
- 发布新的正式 Android 软件后
- 更换 NAS、硬盘或主力电脑前
- 系统重装前

只复制 `.p12` 文件不等于完整备份，因为恢复还需要证书别名、密码、包名、指纹和
GitHub Secret 前缀。应优先保存完整的 `.asmvault.gpg` 便携备份。

## GitHub Actions Secrets

选择软件后点击“GitHub Secrets”，工具会生成四项值：

```text
<PREFIX>_KEYSTORE_BASE64
<PREFIX>_KEYSTORE_PASSWORD
<PREFIX>_KEY_ALIAS
<PREFIX>_KEY_PASSWORD
```

值只会临时复制到剪贴板，60 秒后自动清除。不要把这些值提交到源码。

## 文件说明

```text
SigningVault.psm1
```

证书库、Windows 凭据、GnuPG 加密、便携备份和恢复的核心模块。

```text
AndroidSigningManager.ps1
```

WinForms 图形界面和命令行入口。

```text
Start-AndroidSigningManager.cmd
```

以 STA 和 `ExecutionPolicy Bypass` 启动图形界面。

```text
strings.zh-CN.json
```

中文界面文本。PowerShell 源码保持 ASCII，避免 Windows PowerShell 5.1 的
编码兼容问题。

```text
tests\SmokeTest.ps1
```

使用临时测试证书执行新建、验证、便携导出、清空、跨目录恢复和再次验证。

## 安全边界

- 工具不会上传证书或密码。
- 工具不会自动修改 GitHub Secrets。
- 工具不会删除 Check in 项目原有的 `.signing` 文件。
- Windows 凭据只对当前 Windows 用户和当前系统生效。
- `.asmvault.gpg` 可跨电脑移动，但必须知道主密码。
- 任何介质都有损坏或丢失风险，因此不能只保留一份备份。
