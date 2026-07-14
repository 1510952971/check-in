# Android 签名管理器

手册更新日期：2026-07-14

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

> 重要：不要把便携备份主密码、证书密码或 GitHub Secret 值发送到聊天、
> 邮件正文、Issue 或 Git 仓库。主密码只在工具窗口中输入。

## 你现在应该怎么做

当前电脑不是主力机时，按下面的顺序操作：

1. 打开 Android 签名管理器，确认列表中能看到 `Check in`。
2. 选中 `Check in`，点击“验证证书”。
3. 点击“导出便携套件”。
4. 把目标路径设置为 NAS 的实际共享文件夹或移动硬盘文件夹。
5. 输入两次便携备份主密码。
6. 等待“便携套件已创建并通过解密与 SHA-256 自检”的成功提示。
7. 在目标目录确认出现
   `Android-Signing-Manager-Portable-日期时间` 文件夹。
8. 把主密码保存到密码管理器，不要放在便携套件目录中。
9. 再把同一套件复制到另一块离线硬盘，形成第二份独立备份。
10. 在主力机执行本手册“在另一台电脑恢复”章节。
11. 主力机恢复并验证成功后，再决定是否清理当前电脑的本机证书库。

在主力机完成恢复前，不要删除项目中的 `.signing` 文件，也不要删除当前电脑的
`Android-Signing-Vault`。

## 四个核心概念

### 本机证书库

默认位置：

```text
%USERPROFILE%\Documents\Android-Signing-Vault
```

这里保存 `.p12` 证书、登记信息和证书指纹，不直接保存明文密码。

### Windows 凭据管理器

证书密码保存在当前 Windows 用户的凭据管理器中。它适合本机日常使用，但不会
随着普通文件复制自动迁移到另一台电脑。

### 便携套件

便携套件包含管理器脚本和
`vault-backup.asmvault.gpg`。加密包内部包含证书、登记信息和恢复密码，可以在
另一台 Windows 电脑恢复。

### 便携备份主密码

主密码只用于加密和解密 `.asmvault.gpg`。它不在备份包、源码、GitHub 或
Windows 凭据管理器中。主密码丢失后，无法恢复加密包。

## 主界面按钮说明

| 按钮 | 用途 | 什么时候使用 |
| --- | --- | --- |
| 新建证书 | 为一个全新的 Android 软件生成独立签名证书 | 新软件首次发布前 |
| 导入证书 | 登记已经存在的 `.p12` 或 `.pfx` 证书 | 接管旧项目或迁移现有软件 |
| 编辑登记 | 修改软件名称、仓库、版本和项目目录 | 仓库或本机目录变化后 |
| 验证证书 | 用本机密码读取证书并核对 SHA-256 指纹 | 发布前、恢复后、系统重装前 |
| GitHub Secrets | 生成 GitHub Actions 所需的四项 Secret | 首次配置自动发布或更换仓库 |
| 恢复记录 | 临时复制包含证书密码的文字记录 | 仅用于保存到密码管理器 |
| 导出便携套件 | 完整加密备份全部软件证书和管理器 | 每次新增证书、正式发布或迁移前 |
| 恢复便携备份 | 从 `.asmvault.gpg` 恢复证书库和本机凭据 | 新电脑、系统重装或灾难恢复 |
| 打开证书库 | 打开当前电脑的本机证书库目录 | 检查文件是否存在 |
| 刷新 | 重新读取证书库列表 | 外部文件发生变化后 |

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

主力机可以从 GitHub 仓库获取最新版工具：

```powershell
git clone https://github.com/1510952971/check-in.git
Set-Location ".\check-in\tools\android-signing-manager"
.\Start-AndroidSigningManager.cmd
```

也可以直接使用 NAS 便携套件目录中的
`Start-AndroidSigningManager.cmd`。便携套件中的脚本是创建该备份时的工具
版本；GitHub 仓库中的版本可能包含后续兼容修复。

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

### 新电脑的环境检查

打开 PowerShell，分别运行：

```powershell
keytool.exe -help
gpg.exe --version
```

如果 `keytool.exe` 找不到，安装 Java 17，或把 JDK 放入工具目录的
`runtime\jdk`。如果 `gpg.exe` 找不到，安装 Git for Windows 或 GnuPG，或把
GnuPG 放入 `runtime\gnupg`。

运行管理器不需要管理员权限。NAS 目标目录必须对当前 Windows 用户具有新建文件夹、
写入文件、重命名和删除临时文件的权限。

## 新建证书

1. 点击“新建证书”。
2. 填写软件名称、Android 包名、GitHub 仓库和 Secret 前缀。
3. 工具生成 100 年有效期的 RSA 2048 位 PKCS12 证书。
4. 工具自动生成随机密码并保存到 Windows 凭据管理器。
5. 工具立即读取证书并记录 SHA-256 指纹。
6. 新证书创建后，立刻执行一次“导出便携套件”。

Android 包名创建后不可修改。已经发布的软件也不得更换签名证书，否则旧用户
无法安装后续更新。

### 新建证书字段说明

| 字段 | 示例 | 说明 |
| --- | --- | --- |
| 软件名称 | `Check in` | 列表中显示的名称 |
| Android 包名 | `com.example.app` | 必须与 Android 项目的 `applicationId` 一致 |
| GitHub 仓库 | `owner/repository` | 不要填写完整网址 |
| Secret 前缀 | `MYAPP` | 只用大写字母、数字和下划线 |
| 证书别名 | `release` | 创建后不要随意修改 |
| 当前版本 | `1.0.0` | 仅用于登记和查找 |
| 项目目录 | `D:\Projects\MyApp` | 可留空，换电脑后可以重新编辑 |

Secret 前缀为 `MYAPP` 时，工具会生成：

```text
MYAPP_KEYSTORE_BASE64
MYAPP_KEYSTORE_PASSWORD
MYAPP_KEY_ALIAS
MYAPP_KEY_PASSWORD
```

## 导入已有证书

点击“导入证书”，填写：

- 软件名称和 Android 包名
- GitHub 仓库，格式为 `所有者/仓库`
- GitHub Actions Secret 前缀
- 证书别名
- `.p12` 或 `.pfx` 文件
- 证书密码和密钥密码

工具会先使用密码读取证书并计算 SHA-256，验证通过后才登记。

导入前先确认以下信息：

1. `.p12` 或 `.pfx` 文件来自正式发布使用的原始证书。
2. 证书别名与原项目配置一致。
3. 密钥库密码和密钥密码正确。
4. Android 包名与已发布应用完全一致。
5. 如果已经知道旧证书指纹，导入结果必须与旧记录一致。

对于 Check in，当前正式证书 SHA-256 应为：

```text
a2898c5c80d7661db0e6e1c5cfc3ac1eeebe579c12483aeabc3e11661abaec35
```

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

### 路径填写规则

| 输入 | 是否有效 | 原因 |
| --- | --- | --- |
| `E:\Android-Backup` | 有效 | 移动硬盘或本地磁盘的实际目录 |
| `\\192.168.1.10\backup\Android` | 有效 | 具体到 NAS 共享文件夹的 UNC 路径 |
| `smb://192.168.1.10/backup/Android` | 有效 | 会自动转换为 UNC 路径 |
| `此电脑` | 无效 | Windows 虚拟位置，不是文件系统路径 |
| `网络` | 无效 | Windows 虚拟位置 |
| `NAS` | 无效 | 只有设备名，没有共享目录 |
| `NAS:\backup` | 无效 | 不是合法盘符或 UNC 路径 |
| `https://nas/backup` | 无效 | HTTP 地址不是 SMB 文件共享 |

如果 NAS 路径是：

```text
\\NAS名称\共享文件夹
```

建议先在 Windows 文件资源管理器中打开该地址，确认可以手动新建和删除一个测试
文件夹，再把完整路径粘贴到工具中。

也可以先把 NAS 映射成盘符，例如 `Z:`，再使用：

```text
Z:\Android-Signing-Backup
```

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

### 主密码要求

- 至少 12 个字符，建议 16 个字符以上。
- 至少包含三类字符，例如大小写字母、数字、符号或中文。
- 不允许包含换行。
- 不要复用 GitHub、Windows、NAS 或邮箱密码。
- 两次输入必须完全一致。

推荐由密码管理器生成随机密码，并在密码管理器中添加以下备注：

```text
用途：Android 签名管理器便携备份
备份位置：NAS 路径和离线硬盘位置
首次创建日期：年-月-日
```

### 如何确认导出成功

必须同时满足以下条件：

1. 工具显示“便携套件已创建并通过解密与 SHA-256 自检”。
2. 目标目录出现新的时间戳文件夹。
3. 文件夹内存在 `vault-backup.asmvault.gpg`。
4. 文件夹内存在 `CHECKSUMS.sha256`。
5. `.asmvault.gpg` 文件大小不是 0。
6. 没有残留 `.partial-...gpg` 或 `.tmp-android-signing-manager-...`。
7. NAS 或移动硬盘重新连接后仍能看到这些文件。

导出过程会先创建临时文件，再加密、解密自检和校验；任何一步失败都不会把未验证
的文件夹当作成功备份。

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

### 主力机首次恢复后的检查

恢复成功后不要立刻删除旧电脑的数据。依次检查：

1. 主界面中所有软件数量与旧电脑一致。
2. 每个软件的包名、仓库、别名和指纹一致。
3. 逐个点击“验证证书”，全部显示验证成功。
4. 点击“GitHub Secrets”，确认可以生成四项 Secret 名称。
5. 对正在维护的 Android 项目执行一次正式签名构建。
6. 用 `apksigner verify --print-certs` 或现有构建脚本核对 APK 证书指纹。
7. 在主力机重新导出一份新的便携套件。
8. 把新套件保存到 NAS，并复制到离线硬盘。

只有这些步骤全部通过，才说明主力机已经具备独立发布和灾难恢复能力。

### 旧电脑可以删除什么

主力机恢复完成并至少有两份独立便携备份后，可以删除旧电脑的本机证书库和
Windows 凭据，但这不是必须操作。

不要删除：

- NAS 中的便携套件
- 离线硬盘中的便携套件
- 密码管理器中的主密码
- 项目仍在使用的 `.signing` 目录，除非确认构建已经改用其他安全来源

## 新软件从创建到发布的标准流程

每增加一个 Android 软件，按下面的顺序执行：

1. 在 Android 项目中确定最终 `applicationId`。
2. 在管理器中点击“新建证书”。
3. 软件名称填写用户看到的产品名称。
4. Android 包名填写最终 `applicationId`。
5. GitHub 仓库填写 `所有者/仓库`。
6. 为该软件设置独立 Secret 前缀。
7. 创建证书后立即点击“验证证书”。
8. 点击“GitHub Secrets”，把四项值配置到对应仓库。
9. 在项目构建脚本中使用这四项 Secret。
10. 构建第一个正式 APK。
11. 核对 APK 证书指纹与管理器记录一致。
12. 安装 APK 并完成升级测试。
13. 发布 GitHub Release。
14. 回到管理器更新当前版本信息。
15. 导出新的便携套件到 NAS。
16. 把新套件复制到离线硬盘。

不同软件应使用不同证书和不同 Secret 前缀。不要为了省事让所有软件共用同一份
签名证书。

## 每次发布新版本前后的操作

发布前：

1. 在管理器中选择对应软件。
2. 点击“验证证书”。
3. 确认证书 SHA-256 与上一个正式版本一致。
4. 确认 Android 项目的包名和证书别名没有变化。
5. 确认 GitHub Actions Secrets 仍然存在。

发布后：

1. 下载 GitHub Release 中的正式 APK。
2. 验证 APK 的 SHA-256 和签名证书。
3. 在已安装旧版本的手机上覆盖升级测试。
4. 在管理器中更新当前版本。
5. 导出新的便携套件。

Check in 的完整版本发布步骤见仓库中的：

```text
docs\RELEASE_MANUAL.md
```

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

### 建议保留多少代

- 主力机：最近 2 代
- NAS：最近 3 至 5 代
- 离线硬盘：最近 2 代，其中一代在重要版本发布后创建

不要每次导出后立刻覆盖上一代。新备份至少完成一次恢复验证或文件读取检查后，再
删除过旧版本。

### 手动检查文件哈希

进入便携套件目录后运行：

```powershell
Get-FileHash `
  -LiteralPath ".\vault-backup.asmvault.gpg" `
  -Algorithm SHA256
```

`CHECKSUMS.sha256` 中也记录了便携套件各文件的 SHA-256。复制到另一块硬盘后，
可以再次计算哈希，确认传输没有损坏。

## GitHub Actions Secrets

选择软件后点击“GitHub Secrets”，工具会生成四项值：

```text
<PREFIX>_KEYSTORE_BASE64
<PREFIX>_KEYSTORE_PASSWORD
<PREFIX>_KEY_ALIAS
<PREFIX>_KEY_PASSWORD
```

值只会临时复制到剪贴板，60 秒后自动清除。不要把这些值提交到源码。

配置 GitHub Secrets 后，GitHub 页面不会再次显示完整值。因此：

- GitHub Secrets 不能替代本地证书备份。
- 删除 Secret 前要确认便携套件可用。
- 更换仓库时可以从管理器重新生成相同证书对应的四项值。
- 不要因为忘记 Secret 值而新建证书，应从便携备份恢复原证书。

## 常见问题排查

### 提示“路径形式不合法”

原因通常是选择了 Windows 虚拟位置，或者路径没有具体到 NAS 共享目录。

使用以下任一种形式：

```text
E:\Android-Backup
\\NAS\共享目录\Android-Backup
smb://NAS/共享目录/Android-Backup
```

不要使用：

```text
此电脑
网络
NAS
NAS:\backup
https://nas/backup
```

### 提示“拒绝访问”或无法创建文件夹

1. 在文件资源管理器中打开同一路径。
2. 手动新建一个测试文件夹。
3. 确认当前 Windows 用户已经登录 NAS。
4. 检查共享权限和文件夹权限是否都允许写入。
5. 检查移动硬盘是否只读或剩余空间不足。
6. 不要直接写入需要管理员权限的系统目录。

### NAS 路径暂时不可用

1. 确认电脑和 NAS 在同一网络或 VPN 中。
2. 使用 IP 地址代替主机名测试。
3. 先在文件资源管理器打开 `\\IP地址\共享目录`。
4. 检查 NAS 是否要求 SMB2 或 SMB3。
5. 重新登录 NAS 凭据后再导出。

### 找不到 GnuPG

错误中会提示 `GnuPG was not found`。

解决方法：

1. 安装 Git for Windows。
2. 或安装 GnuPG。
3. 或把 `gpg.exe` 放到 `runtime\gnupg\bin`。
4. 重新启动管理器。

### 找不到 Java keytool

错误中会提示 `Java keytool was not found`。

解决方法：

1. 安装 Java 17。
2. 或安装 Android Studio。
3. 或把 JDK 放到 `runtime\jdk`。
4. 在 PowerShell 中运行 `keytool.exe -help` 验证。

### 主密码错误

错误密码不会破坏备份包。关闭提示后重新输入。

注意：

- 区分大小写。
- 检查输入法是否输入了全角字符。
- 检查密码管理器是否复制了前后空格。
- 不要反复修改备份包文件名内部结构。

### 便携包损坏

如果出现 OpenPGP 解密、文件长度或 SHA-256 不一致：

1. 不要覆盖其他正常备份。
2. 从 NAS 的上一代套件恢复。
3. 从离线硬盘复制另一份。
4. 检查硬盘健康状态和 NAS 存储池。
5. 恢复成功后立即重新导出新套件。

### 已存在相同包名但证书不同

工具会停止恢复，防止覆盖。

先分别核对：

- Android 包名
- 证书别名
- 证书 SHA-256
- 软件是否确实是同一个已发布应用

不要删除现有记录后强行导入，除非已经确认哪一份证书才是正式证书。

### Windows 凭据丢失

如果证书文件还在，但点击验证提示凭据不存在：

1. 点击“恢复便携备份”。
2. 选择最近的 `.asmvault.gpg`。
3. 输入主密码。
4. 工具会为匹配的证书重新写入 Windows 凭据。

### 忘记便携备份主密码

加密包无法绕过主密码恢复。可以尝试：

1. 从密码管理器查找。
2. 检查应急纸质记录。
3. 在仍能正常验证证书的旧电脑上重新导出，并设置新的主密码。

如果没有任何仍可用的本机凭据，也没有主密码或恢复记录，证书密码无法恢复。

## 灾难恢复场景

### 主力机损坏，但 NAS 正常

1. 在新电脑安装 Java 17 和 Git for Windows。
2. 从 NAS 复制最近的便携套件。
3. 启动管理器并恢复。
4. 验证所有证书。
5. 重新导出一份套件到 NAS 和离线硬盘。

### NAS 损坏，但主力机正常

1. 不要删除主力机证书库。
2. 连接新的移动硬盘或 NAS。
3. 立即导出新的便携套件。
4. 建立至少两份独立副本。

### 主力机和 NAS 同时损坏

使用离线硬盘中的便携套件恢复。离线硬盘平时不连接电脑，可以降低误删除、
勒索软件和电源故障同时影响所有副本的风险。

### 只剩项目 `.signing` 文件

如果 `.p12` 和属性文件中的密码都还在，可以使用“导入证书”重新登记，然后立即
导出便携套件。

### 只剩 `.p12`，没有密码

无法使用该证书签名，也无法从证书文件反推出密码。应继续寻找密码管理器、
Windows 凭据、旧电脑、便携备份或恢复记录。

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
