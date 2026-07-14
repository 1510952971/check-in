# 架构与可靠性设计

## 核心组件

| 组件 | 职责 |
| --- | --- |
| `AlarmScheduler` | 预排未来闹钟，并在重启、升级、时区或时间变化后重排 |
| `AlarmTriggerReceiver` | 接收正式闹钟，先记录未完成任务和通知，再请求唤起 |
| `AlarmWatchdogReceiver` | 在首次唤起未到达时重试，并维持提醒 |
| `TriggerActivity` | 点亮屏幕、请求系统解锁，解锁后打开企业微信 |
| `ClockInAccessibilityService` | 发起受系统约束的中转页启动，并确认企业微信进入前台 |
| `LaunchCompletionTracker` | 持久化任务状态，决定何时允许取消通知 |
| `NotificationHelper` | 创建持续、高优先级、可点击的未完成通知 |
| `DeviceCompatibility` | 打开厂商后台权限页，失败时回退到标准设置 |
| `GitHubUpdateManager` | 检查 Release、下载、校验签名并打开系统安装器 |

## 一次任务的完成判定

```text
系统闹钟触发
  -> 写入 pending
  -> 立即显示未完成通知
  -> 请求解锁并打开企业微信
  -> 无障碍收到企业微信窗口事件
  -> 清除 pending 和对应通知
```

`startActivity()` 返回成功不代表企业微信真的出现在前台。厂商系统可能接收
启动请求后仍在锁屏、屏保或后台策略处拦截，因此通知只在收到企业微信窗口
事件后取消。

## 系统升级后的恢复

`RescheduleReceiver` 监听开机、应用替换、时区变化、系统时间变化和精确闹钟
授权变化。厂商专属设置页可能在升级后改名，所以所有入口都有标准 Android
设置回退路径。

## 更新安全

更新器只读取公开 GitHub Releases。下载完成后会比较：

1. APK 包名是否为 `com.clockin.assistant`。
2. APK 签名证书 SHA-256 集合是否与当前安装版本一致。
3. 文件体积是否在合理上限内。

随后 Android 系统安装器还会再次执行平台级签名和版本检查。
