# NetworkSharing

NetworkSharing 是一款面向 Android 手机和平板、Windows 电脑的网络共享应用。配对设备通过 BLE 交换控制消息；当一端离线时，可请求另一端开启热点、传递 Wi-Fi 接入信息并尝试连接。

项目使用 Flutter 构建跨平台 Fluent UI 界面，采用 MVVM 组织页面和状态。Rust 通过 flutter_rust_bridge 提供配对与会话能力；目前 BLE transport、热点控制和 Wi-Fi 连接仍由 BLE 插件、Android Kotlin/Root helper 和 Windows WinRT/PowerShell provider 实现。

## 当前功能

- Android 扫描并连接正在广播的 Windows 电脑；手机输入电脑显示的配对码完成应用配对。
- 配对记录在本地保存。应用启动后尝试恢复连接，并定期重试；Windows 在应用运行或缩入托盘时持续广播。
- 网络检测访问 www.baidu.com 和 www.google.com 的 HTTPS 页面，任一站点可达即视为可以联网。
- 离线设备可以通知用户请求对端热点。对端可以逐次确认，也可以针对已配对设备设置每次询问、自动同意或自动拒绝。
- 获准后尝试开启或复用热点、发送接入信息、连接 Wi-Fi，并检测互联网连通性。设备状态页显示请求和连接进度。
- Android 通知动作支持后台处理；应用也提供前台连接服务。Windows 关闭主窗口时缩入系统托盘。
- 测试与诊断页面提供网络、热点、Wi-Fi、通知和日志工具。

当前以单台已配对设备和单个共享会话为范围。Android 热点启停、热点客户端统计和静默 Wi-Fi 连接依设备、系统版本、Root 授权及厂商策略而异；完整双向流程和后台限制仍需目标设备验证。

## 技术栈

| 区域 | 技术 |
| --- | --- |
| 跨平台界面 | Flutter stable、Dart、fluent_ui |
| 窗口平台 | Windows 桌面、Android API 24 及以上 |
| 配对/会话 | Rust、flutter_rust_bridge |
| BLE | bluetooth_low_energy Flutter plugin |
| Android 热点/Wi-Fi | Kotlin、Android TetheringManager、Root helper、Wi-Fi 系统授权流程 |
| Windows 热点/Wi-Fi | WinRT NetworkOperatorTetheringManager、PowerShell、netsh wlan |
| 偏好设置 | shared_preferences / SharedPreferencesAsync |

## 开发环境

- Flutter stable 与 Dart，使用 FVM 固定和调用 Flutter SDK。
- Rust stable，以及项目所需的 Android NDK 和 Windows C++ 桌面构建工具链。
- Android Studio / Android SDK；需要实际测试蓝牙、后台服务和热点行为时使用 Android 实机。
- Windows 10/11 桌面工具链和支持 BLE 外设与移动热点的电脑/网卡。

查看当前 Flutter/Dart 和依赖版本：.fvmrc、pubspec.yaml、pubspec.lock。不要改用系统全局 Flutter 命令；项目命令通过 fvm 执行。

## 开发命令

在仓库根目录运行：

~~~powershell
fvm flutter pub get
fvm dart format lib test
fvm dart analyze lib test
fvm flutter test --no-pub
~~~

构建 Android Debug APK 和 Windows Debug 程序：

~~~powershell
fvm flutter build apk --debug
fvm flutter build windows --debug
~~~

生成物位置：

- Android：build/app/outputs/flutter-apk/app-debug.apk
- Windows：build/windows/x64/runner/Debug/networksharing.exe

运行桌面应用：

~~~powershell
fvm flutter run -d windows
~~~

网络受限时，可在当前 PowerShell 会话按需使用本机 set-proxy.ps1 临时配置代理，再执行 FVM 命令。GitHub 访问凭据不得打印、写入文档或提交。

## 双端实机流程

1. 在两端安装同一版本并允许应用请求的蓝牙、附近设备、通知及后台运行权限。
2. 在 Windows 打开应用显示配对码；在 Android 搜索并连接 Windows 设备，然后输入该码。
3. 确认两端设备状态页都显示已配对和在线；重开应用验证自动恢复。
4. 分别测试 Windows 离线时使用手机热点，以及 Android 离线时使用 Windows 热点。检查对应通知、对端授权、系统热点和 Wi-Fi 确认、最终互联网状态。
5. 测试系统设置中手动关闭热点/Wi-Fi 后能否再次收到离线提醒，以及设备授权、停止共享和热点空闲关闭。

开发机的单元测试和构建通过，不等于 Android 各厂商权限策略或实际蓝牙链路均已验证。反馈问题时从应用的诊断日志页面导出 Windows 和 Android 日志，记录操作顺序与设备系统版本。不要发送热点密码、配对码或恢复令牌。

## 日志

应用使用 JSON Lines 写入 logs/networksharing.log，日志达到 2 MiB 后保留一份轮转文件 .1。可在应用设置的诊断日志页查看实际路径并导出。

- Windows：应用支持目录下的 logs 文件夹，通常在用户 AppData。
- Android：应用私有支持目录下的 logs 文件夹。

## 文档

- [正式共享流程与实机测试](documents/application-sharing.md)
- [实现状态、构建与验证记录](documents/implementation-status.md)
- [后续 Agent 开发约定](documents/agent-development-guide.md)
- [蓝牙与控制消息协议](documents/protocol.md)
- [架构与模块边界](documents/architecture.md)
- [平台能力与权限说明](documents/platform-capabilities.md)
- [设置持久化](documents/settings.md)
- [Debug 联调与开源参考](documents/network-debug.md)
- [Rust 蓝牙迁移计划](documents/rust-bluetooth-migration.md)

## 分支

master 是当前整合分支，debug 用于逐步开发和验证。已完成的开发阶段提交后合并至 master。请保留工作区中用户尚未提交的改动。

## 已知限制

- BLE 仍由 Flutter 插件执行，尚未整体迁移到 Rust btleplug。
- Android 普通应用不一定有权限自动启动个人热点、读取热点密码或无界面加入 Wi-Fi。Root/TetheringManager 路径取决于设备能力；Wi-Fi 保存/加入可能要求系统确认。
- Windows 移动热点依赖系统 API、Wi-Fi 适配器和 Windows 策略。
- Android 返回键、Home 或锁屏下的后台表现受系统和厂商电池管理影响；应用被强制停止后不保证恢复。
- Android 热点客户端数可能无法读取；无法确认客户端数量时，不会据此自动关闭热点。
- 文件传输、剪贴板同步、DocumentsProvider、厂商灵动岛、摄像头/麦克风共享和手机投屏仅记录在路线文档中，尚未实现。
