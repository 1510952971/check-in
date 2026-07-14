# 开发与测试

## 环境

- Java 17
- Android Gradle Plugin 8.7.3
- Gradle 8.9
- Android SDK / Build Tools 35

没有本机 Android 环境时运行：

```powershell
powershell.exe -ExecutionPolicy Bypass `
  -File .\scripts\bootstrap-and-build.ps1
```

## 提交前检查

1. `:app:assembleDebug` 成功。
2. `:app:lintDebug` 无错误。
3. `:app:assembleRelease` 和 APK 签名验证成功。
4. 在至少约 `320dp` 宽小屏和常见大屏手机尺寸检查主界面、手册、弹窗。
5. 完成亮屏、普通锁屏、安全锁屏和息屏闹钟测试。
6. 确认任务未完成时通知保留，企业微信进入前台后通知才消失。
7. 检查 GitHub 更新仓库输入、版本比较、下载失败和签名不匹配提示。

## 修改原则

- 不读取锁屏密码，不模拟企业微信中的打卡点击。
- 不以 `startActivity()` 返回成功作为任务完成。
- 新增厂商设置入口时必须保留标准 Android 回退路径。
- 用户可见文字放入 `strings.xml`，尺寸放入 `dimens.xml`。
- 关键可靠性判断写简短注释，避免解释显而易见的赋值或控件绑定。
