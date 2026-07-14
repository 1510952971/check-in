# Check in

一个面向 Android 8.0 及以上系统的原生 Android 小工具，重点适配小米
HyperOS。默认每天在 `08:33` 和 `17:31` 自动打开企业微信，也可以改成仅
周一至周五。

## 它会做什么

- 使用系统闹钟滚动预排未来 7 天，避免依赖常驻后台进程。
- 到点先直接拉起企业微信。
- 通过用户启用的“Check in 自动打开服务”执行息屏唤起。
- 锁屏、密码、屏保或系统策略拦截任务时，持续保留高优先级通知。
- 只有确认企业微信已进入前台后，才会自动移除未完成通知。
- 手机重启、时区改变、系统时间改变或应用升级后自动重新排程。
- 提供精确闹钟、通知、全屏提醒、电池无限制和厂商后台权限入口。
- 支持从公开 GitHub Releases 检查、下载并安装同签名更新。

它只负责打开企业微信，不会代替用户点击企业微信里的“打卡”按钮。

## 适配范围

- Android 8.0（API 26）及以上。
- 针对 `320dp` 至常见大屏手机宽度提供响应式尺寸资源。
- 提供小米、Redmi、POCO、华为、荣耀、OPPO、一加、realme、vivo、
  iQOO、三星、魅族和通用 Android 的后台权限入口。
- 厂商设置页发生改名时，会回退到 Android 标准应用详情页。

## 小米 15 首次设置

1. 安装并打开“Check in”。
2. 保持右上角开关为开启状态。
3. 依次处理页面上显示为“待设置”的权限。
4. 在无障碍设置中开启“Check in 自动打开服务”。
5. 在小米自启动设置里允许“Check in”自启动。
6. 在应用信息的其他权限中允许“后台弹出界面”。
7. 将电池策略设为“无限制”，并可在最近任务中锁定应用。
8. 点击“立即测试打开企业微信”确认企业微信能正常拉起。
9. 点击“安排 1 分钟后息屏测试”，返回桌面并锁屏。

应用内也可以点击“操作手册”查看完整步骤。

## 构建

项目使用 Java 17、Android Gradle Plugin 8.7.3 和 Android SDK 35。

电脑尚未安装 Android 开发环境时，可运行项目自带的一次性构建脚本。工具会下载到
项目内的 `.tools` 目录，不修改系统 Java 或 Android 配置。

```powershell
.\scripts\bootstrap-and-build.ps1
```

生成正式签名安装包：

```powershell
.\scripts\bootstrap-and-build.ps1 -Release
```

首次正式构建会在已忽略的 `.signing/` 目录生成本地证书和随机口令配置。
请单独备份整个目录，不要把其中任何文件提交到仓库。若 PowerShell 阻止脚本
运行，可使用：

```powershell
powershell.exe -ExecutionPolicy Bypass `
  -File .\scripts\bootstrap-and-build.ps1 -Release
```

已有 Java 17 和 Android SDK 35 时，可直接运行：

```powershell
.\gradlew.bat assembleDebug
```

构建结果位于：

```text
app\build\outputs\apk\debug\app-debug.apk
app\build\outputs\apk\release\check-in-<versionName>.apk
```

## GitHub 自动更新

正式构建默认使用 `1510952971/check-in` 检查更新；长按“检查更新”按钮可以
切换到其他公开仓库。发布正式版本时，将本地正式签名证书配置为以下 GitHub
Actions Secrets：

```text
CLOCKIN_KEYSTORE_BASE64
CLOCKIN_KEYSTORE_PASSWORD
CLOCKIN_KEY_ALIAS
CLOCKIN_KEY_PASSWORD
```

推送形如 `v1.3.0` 的标签后，工作流会构建同签名 APK，并发布 APK 与
SHA-256 文件到 GitHub Releases。版本标签应与 `app/build.gradle` 中的
`versionName` 保持一致。

## 仓库文档

- [用户操作手册](docs/USER_GUIDE.md)
- [架构与任务完成判定](docs/ARCHITECTURE.md)
- [新版本上传与发布操作手册](docs/RELEASE_MANUAL.md)
- [GitHub Release 与签名配置](docs/RELEASE_GUIDE.md)
- [参与开发与测试清单](CONTRIBUTING.md)
