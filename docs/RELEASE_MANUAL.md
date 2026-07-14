# Check in 新版本上传与发布操作手册

本文适用于以下项目：

- 本地目录：`C:\Users\TCS\Documents\上下班打卡`
- GitHub 仓库：`1510952971/check-in`
- 自动发布工作流：`.github/workflows/release.yml`
- 手册首次编写时的基准版本（2026-07-14）：
  `versionName 1.3.0`、`versionCode 5`

正常情况下，只需要修改版本号、完成测试、推送代码，再推送版本标签。
GitHub Actions 会自动构建同签名 APK、生成 SHA-256 校验文件并发布
GitHub Release。

## 一、发布前必须理解的规则

1. `versionCode` 必须是不断增加的整数。
   Android 使用它判断新 APK 是否可以覆盖旧版本，不能重复或减小。
2. `versionName` 是用户看到的版本号，建议使用三段式版本：
   `主版本.次版本.修订版本`，例如 `1.3.1`。
3. Git 标签必须是字母 `v` 加上完整的 `versionName`。
   例如 `versionName "1.3.1"` 对应标签 `v1.3.1`。
4. 每次更新必须继续使用同一份正式签名证书。
   换证书后，Android 会拒绝覆盖安装现有版本。
5. 不要重复使用已经发布过的版本号或标签。
   已发布版本需要修复时，应继续增加版本号。
6. 正式 APK 必须作为 GitHub Release 资产上传。
   应用会寻找扩展名为 `.apk` 的资产，并优先选择名称以
   `check-in-` 开头的 APK。

以初始公开版 `1.3.0 / versionCode 5` 为例，下一个修复版本建议设置为：

```groovy
versionCode 6
versionName "1.3.1"
```

对应标签：

```text
v1.3.1
```

## 二、首次使用自动发布前的一次性准备

这一部分只需要完成一次。以后每次发布可以直接从第三节开始。

### 2.1 备份正式签名文件

需要同时备份以下两个文件：

```text
.signing\clockin-release.p12
.signing\clockin-release.properties
```

建议至少保留两份加密备份，例如一个加密移动硬盘备份和一个离线备份。
不要把它们放入 Git、聊天记录、GitHub Issue 或公开网盘。

GitHub Secrets 不能替代本地备份，因为保存后无法从 GitHub 页面重新读取
完整值。

当前正式证书的 SHA-256 指纹应为：

```text
a2898c5c80d7661db0e6e1c5cfc3ac1eeebe579c122483aeabc3e11661abaec35
```

每次正式构建完成后，签名验证输出中的证书 SHA-256 应与这个值一致。
如果不一致，停止发布，不要卸载手机上的正式版本来绕过签名错误。

### 2.2 在 PowerShell 中读取本地签名配置

打开 PowerShell，进入项目目录：

```powershell
Set-Location "C:\Users\TCS\Documents\上下班打卡"
```

将本地配置加载到内存，不会在屏幕上显示口令：

```powershell
$Signing = ConvertFrom-StringData (
  Get-Content `
    -LiteralPath ".signing\clockin-release.properties" `
    -Raw `
    -Encoding UTF8
)
```

### 2.3 打开 GitHub Actions Secrets 页面

1. 打开仓库 `1510952971/check-in`。
2. 点击仓库顶部的 `Settings`。
3. 在左侧找到 `Secrets and variables`。
4. 点击 `Actions`。
5. 在 `Repository secrets` 区域点击 `New repository secret`。

需要创建以下四个 Secret，名称必须完全一致：

| Secret 名称 | 值的来源 |
| --- | --- |
| `CLOCKIN_KEYSTORE_BASE64` | `clockin-release.p12` 的 Base64 内容 |
| `CLOCKIN_KEYSTORE_PASSWORD` | 本地配置中的 `keystorePassword` |
| `CLOCKIN_KEY_ALIAS` | 本地配置中的 `keyAlias` |
| `CLOCKIN_KEY_PASSWORD` | 与当前 `keystorePassword` 相同 |

### 2.4 创建 `CLOCKIN_KEYSTORE_BASE64`

运行下面的命令，将证书转换为 Base64 并直接放入剪贴板：

```powershell
[Convert]::ToBase64String(
  [IO.File]::ReadAllBytes(
    (Resolve-Path ".signing\clockin-release.p12")
  )
) | Set-Clipboard
```

然后在 GitHub 中：

1. 点击 `New repository secret`。
2. `Name` 填写 `CLOCKIN_KEYSTORE_BASE64`。
3. `Secret` 输入框中粘贴剪贴板内容。
4. 点击 `Add secret`。

不要把 Base64 内容粘贴到聊天、README、Issue 或代码文件中。Base64 不是
加密，任何拿到它的人都可以还原证书文件。

### 2.5 创建三个签名参数 Secret

复制证书口令到剪贴板：

```powershell
$Signing.keystorePassword | Set-Clipboard
```

使用同一份剪贴板内容分别创建：

```text
CLOCKIN_KEYSTORE_PASSWORD
CLOCKIN_KEY_PASSWORD
```

复制证书别名到剪贴板：

```powershell
$Signing.keyAlias | Set-Clipboard
```

创建：

```text
CLOCKIN_KEY_ALIAS
```

完成后，GitHub 页面应列出四个名称。GitHub 不会再次显示 Secret 的完整值，
这是正常现象。

## 三、以后每次发布新版本的完整步骤

下面以从 `1.3.0` 发布 `1.3.1` 为例。实际发布时请替换成目标版本。

### 第 1 步：进入项目并同步主分支

```powershell
Set-Location "C:\Users\TCS\Documents\上下班打卡"
git status --short --branch
git pull --ff-only origin main
```

正常状态应显示当前分支为 `main`，且没有未提交文件。

如果 `git status` 显示修改内容，不要使用 `git reset --hard` 或直接删除。
先确认这些修改是否是正在开发的新功能，并在发布提交中正确保留。

### 第 2 步：完成准备发布的功能修改

完成代码、界面、文档或适配修改。至少检查：

- 定时任务是否仍能保存和重新排程。
- 锁屏或密码拦截时，未完成通知是否持续存在。
- 解锁并成功打开企业微信后，通知是否正确消失。
- 小米自启动、电池策略、后台弹出界面和无障碍入口是否仍可打开。
- 不同屏幕宽度下是否存在文字截断、重叠或按钮无法点击。
- “检查更新”是否仍指向 `1510952971/check-in`。

### 第 3 步：修改版本号

打开：

```text
app\build.gradle
```

找到：

```groovy
versionCode 5
versionName "1.3.0"
```

修改为：

```groovy
versionCode 6
versionName "1.3.1"
```

修改规则：

- 小修复：`1.3.0` 改为 `1.3.1`。
- 新增一组功能：可以改为 `1.4.0`。
- 存在不兼容的大改动：可以改为 `2.0.0`。
- 无论 `versionName` 如何变化，`versionCode` 都至少增加 `1`。

检查结果：

```powershell
Select-String `
  -Path ".\app\build.gradle" `
  -Pattern "versionCode|versionName"
```

### 第 4 步：构建调试版本

```powershell
powershell.exe `
  -NoProfile `
  -ExecutionPolicy Bypass `
  -File ".\scripts\bootstrap-and-build.ps1"
```

调试 APK 输出到：

```text
app\build\outputs\apk\debug\app-debug.apk
```

构建失败时不要继续创建版本标签。先修复编译错误并重新运行。

### 第 5 步：运行 Lint

已配置 Java 17 和 Android SDK 35 的环境中运行：

```powershell
.\gradlew.bat lint
```

Lint 报告通常位于：

```text
app\build\reports\lint-results-debug.html
```

优先处理 `Error`。对于保留的 `Warning`，确认它不会影响闹钟、通知、更新、
签名或 Android 新系统兼容性。

### 第 6 步：生成正式签名 APK

```powershell
powershell.exe `
  -NoProfile `
  -ExecutionPolicy Bypass `
  -File ".\scripts\bootstrap-and-build.ps1" `
  -Release
```

以 `1.3.1` 为例，正式 APK 输出到：

```text
app\build\outputs\apk\release\check-in-1.3.1.apk
```

脚本完成时必须看到：

```text
Verified using v2 scheme: true
Verified using v3 scheme: true
```

同时检查证书 SHA-256 指纹与第二节记录的正式证书指纹一致。

### 第 7 步：计算并记录 APK 的 SHA-256

```powershell
$Version = "1.3.1"
$Apk = Resolve-Path (
  ".\app\build\outputs\apk\release\check-in-$Version.apk"
)
Get-FileHash -Algorithm SHA256 -LiteralPath $Apk
```

保留这个哈希值，用于发布后核对 GitHub 上的文件。

### 第 8 步：在模拟器或手机上覆盖安装测试

连接模拟器或开启 USB 调试的测试手机后运行：

```powershell
$Version = "1.3.1"
& ".\.tools\android-sdk\platform-tools\adb.exe" `
  install -r `
  ".\app\build\outputs\apk\release\check-in-$Version.apk"
```

必须使用 `install -r` 覆盖旧版本进行测试，这可以提前发现签名不一致问题。

安装后至少测试：

1. 打开 Check in，确认原有时间与开关设置没有丢失。
2. 点击“立即测试打开企业微信”。
3. 安排一次 1 分钟后的息屏测试并锁屏。
4. 确认锁屏拦截时出现未完成通知。
5. 解锁后确认企业微信打开，并且完成通知被移除。
6. 打开操作手册、权限面板和检查更新页面。
7. 在小屏和常规屏幕尺寸下检查主要页面。

任何一项失败，都应修复后重新构建，不要继续发布标签。

### 第 9 步：检查准备提交的文件

```powershell
git status --short
git diff --check
git diff -- app\build.gradle
```

确认以下内容没有被加入：

```text
.signing\
.tools\
.gradle\
app\build\
任何密码、Base64 证书内容或访问令牌
```

### 第 10 步：提交并推送代码

```powershell
git add -A
git status --short
git commit -m "Release Check in 1.3.1"
git push origin main
```

推送完成后，打开 GitHub 仓库的 `main` 分支，确认最新提交就是准备发布的
版本提交。

### 第 11 步：创建版本标签

先再次确认本地版本：

```powershell
Select-String `
  -Path ".\app\build.gradle" `
  -Pattern "versionName"
git log -1 --oneline
```

创建带说明的标签：

```powershell
git tag -a v1.3.1 -m "Check in v1.3.1"
```

检查标签：

```powershell
git show v1.3.1 --no-patch
```

推送单个标签：

```powershell
git push origin v1.3.1
```

不要使用与 `versionName` 不一致的标签。工作流会去掉开头的 `v`，然后将
标签版本与 `app/build.gradle` 中的 `versionName` 比较。

### 第 12 步：观察 GitHub Actions

1. 打开 GitHub 仓库。
2. 点击顶部 `Actions`。
3. 打开名为 `Release APK` 的最新运行记录。
4. 等待所有步骤变为绿色。

正常执行顺序：

1. `Check out source`
2. `Set up Java 17`
3. `Restore signing key`
4. `Verify tag matches app version`
5. `Build signed release`
6. `Prepare release files`
7. `Publish GitHub Release`

不要在工作流仍运行时重复推送同一标签。
工作流会根据提交记录自动生成 Release notes，并使用
`Check in v版本号` 作为发布标题。

### 第 13 步：核对 GitHub Release

在仓库右侧或 `Releases` 页面打开新版本，确认：

- 标签是 `v1.3.1`。
- 页面显示为 `Latest`。
- 提交与本次发布提交一致。
- 存在 `check-in-1.3.1.apk`。
- 存在 `check-in-1.3.1.apk.sha256`。
- APK 不是带有 `unsigned` 字样的文件。

下载 APK 后重新计算哈希：

```powershell
Get-FileHash `
  -Algorithm SHA256 `
  -LiteralPath "$env:USERPROFILE\Downloads\check-in-1.3.1.apk"
```

结果应与 Release 页面和 `.sha256` 文件一致。

### 第 14 步：验证应用内更新

使用仍安装旧版本的模拟器或测试手机：

1. 打开旧版 Check in。
2. 点击“检查更新”。
3. 确认显示 `1.3.1`。
4. 点击下载并安装。
5. 第一次可能需要允许 Check in“安装未知应用”。
6. 安装完成后重新打开 Check in。
7. 确认版本更新且原有时间、权限提示和开关状态正常。

如果测试设备已经安装 `1.3.1`，检查更新只会提示当前已是最新版。要验证
升级弹窗，需要先保留一个较旧的正式版本。

## 四、常见失败及处理方法

### 4.1 标签版本与应用版本不一致

工作流提示类似：

```text
Tag version 1.3.2 does not match app version 1.3.1
```

如果 Release 尚未创建，可以删除错误标签：

```powershell
git tag -d v1.3.2
git push origin :refs/tags/v1.3.2
```

然后确认 `versionName`，创建正确标签并重新推送。

### 4.2 `Restore signing key` 失败

重点检查：

- `CLOCKIN_KEYSTORE_BASE64` 名称是否完全正确。
- Base64 是否完整粘贴。
- Secret 中是否混入额外说明文字。
- 本地 `.p12` 文件是否损坏。

重新复制 Base64 时，使用第二节的 PowerShell 命令，不要手动分段。
更新 Secret 后，如果代码和标签本身没有问题，可以在失败的 Actions 运行
页面选择 `Re-run jobs`，不需要重新创建标签。

### 4.3 正式构建提示密码或别名错误

重点检查：

- `CLOCKIN_KEYSTORE_PASSWORD`
- `CLOCKIN_KEY_ALIAS`
- `CLOCKIN_KEY_PASSWORD`

当前项目生成的证书使用同一个值作为 keystore password 和 key password。
`CLOCKIN_KEY_ALIAS` 应取自本地 `keyAlias`。
修正 Secret 后，可以直接重新运行失败的工作流。

### 4.4 发布步骤提示权限不足

确认工作流文件仍包含：

```yaml
permissions:
  contents: write
```

同时检查仓库：

```text
Settings -> Actions -> General -> Workflow permissions
```

如果组织或仓库策略禁止写入 Release，需要调整对应 GitHub Actions 权限后
重新运行失败的工作流。

### 4.5 标签或 Release 已存在

已经正式发布并被用户下载的版本，不要删除后替换同名 APK。应增加
`versionCode` 和 `versionName`，发布一个新版本，例如从 `1.3.1` 改为
`1.3.2`。

只有在工作流失败、Release 从未成功生成、标签也没有被用户使用时，才适合
删除错误标签后重建。

### 4.6 APK 无法覆盖安装

常见原因：

- `versionCode` 没有增加。
- APK 使用了不同证书。
- 安装的是调试 APK，而手机上是正式 APK。
- APK 下载不完整。

不要为了让错误签名的 APK 装上而卸载正式应用。先核对证书指纹和版本号，
否则会破坏后续升级连续性。

### 4.7 应用提示没有可下载的更新

检查：

- Release 是否为正式发布，而不是 Draft。
- Release 标签版本是否高于手机当前 `versionName`。
- Release 是否包含扩展名为 `.apk` 的资产。
- APK 名称是否建议使用 `check-in-版本号.apk`。
- 仓库是否仍为公开仓库。
- 应用中的更新仓库是否为 `1510952971/check-in`。

## 五、GitHub Actions 暂时不可用时的手动发布

手动发布只作为备用方案。必须上传本地脚本生成的同签名正式 APK。

### 5.1 构建并生成校验文件

```powershell
$Version = "1.3.1"

powershell.exe `
  -NoProfile `
  -ExecutionPolicy Bypass `
  -File ".\scripts\bootstrap-and-build.ps1" `
  -Release

$ApkPath = (
  Resolve-Path (
    ".\app\build\outputs\apk\release\check-in-$Version.apk"
  )
).Path
$ChecksumPath = "$ApkPath.sha256"
$Hash = (
  Get-FileHash -Algorithm SHA256 -LiteralPath $ApkPath
).Hash.ToLowerInvariant()
"$Hash  $(Split-Path -Leaf $ApkPath)" |
  Set-Content -LiteralPath $ChecksumPath -Encoding ASCII
```

### 5.2 在 GitHub 页面创建 Release

1. 先提交并推送代码到 `main`。
2. 创建并推送与 `versionName` 对应的标签。
3. 打开仓库的 `Releases` 页面。
4. 点击 `Draft a new release` 或 `Create a new release`。
5. 选择已经推送的标签，例如 `v1.3.1`。
6. 标题填写 `Check in v1.3.1`。
7. 填写本次更新内容和测试说明。
8. 上传 `check-in-1.3.1.apk`。
9. 上传 `check-in-1.3.1.apk.sha256`。
10. 不要选择 `Set as a pre-release`，除非这是内部测试版。
11. 点击 `Publish release`。
12. 按第三节第 13、14 步完成下载哈希和应用内更新测试。

手动发布时不要上传：

```text
app-release-unsigned.apk
clockin-release.p12
clockin-release.properties
任何密码或 GitHub 访问令牌
```

## 六、发布完成后的最终清单

发布结束前逐项确认：

- [ ] `versionCode` 已增加。
- [ ] `versionName` 已更新。
- [ ] 调试构建成功。
- [ ] Lint 没有阻断发布的错误。
- [ ] 正式签名构建成功。
- [ ] v2/v3 签名验证通过。
- [ ] 正式证书 SHA-256 指纹一致。
- [ ] 覆盖安装测试通过。
- [ ] 息屏、锁屏、通知和企业微信打开测试通过。
- [ ] 所有代码已推送到 `main`。
- [ ] 标签与 `versionName` 完全一致。
- [ ] GitHub Actions 全部成功。
- [ ] Release 中包含 APK 和 SHA-256 文件。
- [ ] GitHub APK 哈希与本地一致。
- [ ] 旧版本应用内升级测试通过。
- [ ] `.signing` 和任何密码都没有进入 Git。

## 七、官方参考资料

- [在 GitHub Actions 中使用 Secrets](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions)
- [管理 GitHub Release](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)
- [向远程仓库推送 Git 标签](https://docs.github.com/en/get-started/using-git/pushing-commits-to-a-remote-repository#pushing-tags)
