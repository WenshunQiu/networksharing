# 正式网络共享流程与实机测试（2026-11-10）

本页是当前正常使用流程的实现说明。历史文档中的“仅 Debug 能用”“尚未接入自动策略”描述由本页替代。用户已确认上一版 Debug 中通知、双端热点开关、凭据传输和 Wi-Fi 连接可用；其中一次 Windows 开热点失败是用户主动触发，不视为程序缺陷。本轮将这些能力组装到正式入口，仍需双端实测完整链路。

## 正常使用

1. Windows 启动后自动广播，Android 从应用配对记录加载目标并主动尝试连接；无需重新访问配对页。首次连接仍由手机输入电脑当前配对码。应用级恢复检查每 20 秒执行；断线扫描失败继续按既有 5 秒重试路径处理。心跳仍为 10 秒，30 秒无响应显示离线。手动断开暂停本次运行自动重连，重新打开应用恢复默认行为。
2. 网络监测每 30 秒检测百度和 Google HTTPS（任一可达即可）；按用户意见维持联网/离线二值判断。已认证连接建立后 5 秒发送一次本机网络情况，在设备磁贴显示；每次重连重新发送。
3. 本机持续离线约 15 秒、对端最近报告在线、两端控制通道可用且没有共享会话时，发送本机“请求对方热点”通知。系统检测周期会带来额外延迟；5 分钟内不重复提醒。设置为“仅手动请求”或关闭通知时不会自动提示。
4. 用户确认请求后，向对端发送 share_request。对端按该设备授权显示“允许开启/拒绝”通知，或按已保存的“自动允许/拒绝请求”处理；设备状态页也有确认入口。拒绝、忙碌、两分钟超时均可重试。
5. 对端允许后重新检测本机互联网，读取已有热点或开启新热点，取得 SSID/密码，再发送绑定该会话的 share_credentials。普通 Debug 凭据消息不触发自动加入，保持调试用途。
6. 请求方收到当前会话凭据后立即调用已有 Wi-Fi Provider，随后最多检查三次互联网，回报 share_result。两端在设备状态页显示进度和成功/失败，不依赖 Debug 页。
7. 任一方可停止/取消会话。已有热点可以复用；仅关闭由本应用启动并记录拥有的热点。取消到达时若热点尚在启动，等待系统操作完成后清理，不再发送凭据。
8. 单一活动共享会话阻止反向共享和重复开热点。双方同时请求时均返回忙碌，用户稍后重试；不会两边同时开热点。多设备仍留后续。
9. 在设备状态页的已配对设备磁贴点击“管理权限”，可为该设备设置每次询问、自动同意或自动拒绝；保存后立即生效。自动授权只作用于该已配对设备的热点请求。

## 后台通知

Android 使用 flutter_local_notifications 官方后台动作机制：showsUserInterface=false，注册带 vm:entry-point 的独立入口。后台 isolate 只把动作写入 SharedPreferencesAsync 的独立消息键；正在运行的主 isolate 每秒取出，按会话 ID 和有效期验证后交给 SharingViewModel 执行。不会创建第二份 BLE 连接，不主动启动 Activity。

调试热点确认沿用同一入口，转发给原 BluetoothViewModel。正式 32 位 hex 会话 ID 与 Debug 16 字符请求 ID 分开路由，过期或已消费的通知不能重复执行。

手机已建立连接或在启动恢复扫描前启动 connectedDevice 前台服务。Android 返回键将任务放入后台，保留引擎和会话；Home/锁屏同样不需要打开主页面执行开热点动作。Android Wi-Fi 加入需要系统批准时依然遵守系统界面交互；它与提供方后台“允许开启”是不同环节。被强制停止/系统杀进程后，旧会话不重建，不执行陈旧通知。目标机型 Doze/后台冻结行为需要实测。

Windows 点击关闭保留托盘和进程，收到通知动作继续由现有进程处理；托盘菜单退出才结束后台能力。

## 空闲关闭与重启

热点客户端检查间隔 30 秒：Windows 读取 NetworkOperatorTetheringManager.ClientCount；Android Root helper 反射注册 TetheringEventCallback.onClientsChanged，等待首次客户端集合回调后读取数量。接口不支持或未及时返回时数量为空，不把它当作零。

仅在“本应用拥有热点 + 实际客户端数持续为零 + 达到设置时长 + 再次确认为零”时自动关闭。已有非本应用热点不自动关闭；蓝牙断线不是热点空闲判断依据。无法取得客户端数时继续保持热点，状态页显示“系统暂未提供”，允许手动停止。

以 networksharing.ownedHotspotSsid 保存本应用拥有热点的标记，重启后先核对热点是否开启和 SSID 是否一致，再恢复空闲监测；不保存热点密码，也不恢复中断中的 Wi-Fi 加入请求。用户若在系统设置重建同名热点，当前标记无法区分，需要后续增加平台实例身份；日常使用中可在状态页停止本应用共享。

## 模块与扩展

- SharingViewModel：正式会话、通知确认、Provider 编排、超时、取消、空闲检查；通过可注入 NetworkOperation/ShareNotification 测试和扩展。View 不调用系统网络 API。
- BluetoothViewModel：持久化配对、恢复、心跳，以及已认证 sharingMessages/sendSharingMessage 入口。分享功能通过独立 share_* 消息接入，不把 Debug 消息重新解释为自动操作。
- PlatformNetworkControl：复用已验证 Android Kotlin/Root 和 Windows PowerShell/WinRT Provider；以后迁移 Rust Provider 时保持操作返回结构。
- Rust 既有 sharing.rs 是进程内状态模型，本轮正常网络编排由 Dart 协调；BLE 仍使用当前插件，未声称完成 Rust btleplug 传输迁移。后续迁移需统一状态源，不另起独立业务状态副本。
- SharedPreferencesAsync：用户设置、每设备授权、拥有热点标记和通知动作邮箱；授权键为 networksharing.sharePermission.<peerId>，值 ask/allow/deny。当前 Windows peerId 为单设备占位身份，多设备阶段须迁移。

## 实机测试建议

双方更新同一版本后，优先测这些实际使用路径：

1. 保留配对记录，关闭进程后重开两端，不点击扫描；确认自动恢复、设备磁贴在线和网络状态。关闭蓝牙 40 秒后重新开启，等待恢复。
2. Windows 断开互联网、手机保留移动数据；Windows 本地通知确认请求，手机保持后台点击“允许开启”。确认手机不跳回主页面、热点自动启用，Windows 自动连接，双方显示结果。
3. Android 关闭移动数据/断开原 Wi-Fi，Windows 保留有线上网；手机确认请求，Windows 通知允许，手机接受系统 Wi-Fi 保存/连接授权，双方显示联网成功。
4. 分别测试拒绝、每次询问/自动允许/拒绝授权持久化、停止共享；请求超时后点击旧通知应没有新操作。
5. 将空闲时长设为 5 分钟，断开热点客户端并观察是否自动关闭；设备状态页确认客户端计数真实变化。蓝牙断开而 Wi-Fi 仍连接时热点不得误关。
6. Windows 关闭窗口到托盘，Android 按返回/Home/锁屏，重复通知确认。正常应用进程仍运行即可；强制停止不在本轮自动恢复范围。

问题反馈附双端导出日志，优先查看 sharing.session.state、sharing.credentials.sent、notification.background_action.received、bluetooth.runtime.recovery_check 和 network.operation.*。无须贴出密码或配对令牌。

### 连接被手动断开后的提醒（2026-11-10）

用户日志显示共享接入侧成功联网后切到 closed，但 stop 写入新的五分钟离线提醒冷却时间，挡住再次提示。代码还遗漏了系统外关闭 Wi-Fi 后 requester 保留 active 会话的清理，canRequest 因而可能一直为 false。现在监测到请求方在 active 后持续离线 15 秒便结束旧会话并发送 share_cancel；正常 stop 不再启动通知冷却，联网重新出现也会重置冷却。同一段持续离线仍保留五分钟提醒间隔；短暂切网在 15 秒内恢复则保留会话，不重复通知。

按项目约定核对了 fluttercommunity/plus_plugins 的 connectivity_plus 官方 example 中“初始检查 + 监听状态变化”方式（BSD-3-Clause，未复制源码）；本次不引入新依赖，直接订阅已有 ConnectivityViewModel 的探测完成事件。仍使用百度/Google HTTPS 结果，不把仅有 Wi-Fi 连接当作有互联网。

## 未来功能（已记录，本轮不实现）

### 优先级较高，后续评估

- 在适合的通知场景加入应用内弹窗，或调研并接入 Android 各厂商“灵动岛/实时活动”类能力。保持普通通知可用，不把厂商定制 API 作为基础依赖。
- 扩展数据通道：保留 BLE 做发现、配对和控制，增加 Wi-Fi Direct 或同一局域网点对点连接，用于高吞吐文件传输与剪贴板同步。先设计平台无关 Transport/Channel 能力协商、加密会话、连接切换和传输恢复，再加传输功能。
- 双端便捷文件互取考虑使用 Android DocumentsProvider（及 Windows 对应文件访问组件），由本端文件管理器按需浏览对端授权共享的文件；文件内容走前述 Wi-Fi 通道。依赖关系是先实现 Wi-Fi/局域网传输与授权范围，随后接入 DocumentsProvider；不要把 DocumentsProvider 误当传输层。

### 未来可能，但目前不排期

- 手机摄像头与麦克风向 Windows 共享，需单独研究实时媒体传输、权限提示、音视频设备接入及网络质量适配。
- Android 手机投屏到 Windows，需单独评估系统采集授权、屏幕编码、音频策略、低延迟传输和窗口呈现。

以上为路线记录，不表示已实现、已经选定协议/供应商或已完成兼容性调研。按项目约定，开始实施时先搜索官方 API 与活跃开源项目，核查许可证并写专题设计。

## 借鉴来源

验证记录：52 项 Flutter 测试与 Flutter analyze 通过；Windows getHotspot 实际只读验证返回 success=true、enabled=false、clientCount=0，未读取输出密码；编译产物及 Git 交付记录见 implementation-status.md。双端正常共享、锁屏下通知确认和 Android 客户端数的真实变化交由用户本轮实机测试。

本轮核对 flutter_local_notifications 23.0.0 的 README、callback_dispatcher.dart 和 Android ActionBroadcastReceiver，实现后台 isolate 动作投递；插件 BSD-3-Clause。SharedPreferencesAsync 官方实现用于跨 isolate 无缓存读写。Android 客户端回调参照 AOSP TetheringManager.TetheringEventCallback；Windows 客户端数采用 Microsoft NetworkOperatorTetheringManager.ClientCount。此前热点/Wi-Fi 的开源参考及许可证见 network-debug.md。

- https://github.com/MaikuB/flutter_local_notifications/tree/master/flutter_local_notifications
- https://github.com/flutter/packages/tree/main/packages/shared_preferences
- https://android.googlesource.com/platform/packages/modules/Connectivity/+/refs/heads/main/Tethering/common/TetheringLib/src/android/net/TetheringManager.java
- https://learn.microsoft.com/en-us/uwp/api/windows.networking.networkoperators.networkoperatortetheringmanager.clientcount

后续 agent 优先查找现有开源方案和平台示例；目前以补齐使用流程和机型兼容为主，不因后期安全加固而中断已授权的开发与实机测试。
