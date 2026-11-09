# 网络共享联调（2026-11-09）

## 当前路径

保持单个活动设备：Android 主动扫描 Windows 广播。首次验证 Windows 当前配对码；Windows 生成恢复令牌，两端保存同一份。Android 重启时扫描保存的设备 ID；心跳每 10 秒发送，30 秒无响应则清除当前链路状态，重新扫描和连接，再验证恢复令牌。扫描失败或未发现设备时等待 5 秒重试；手动断开暂停自动重连。Windows 持续广播等待手机恢复。

持久化读取完成前不会开始认证和保存。配对码到期/刷新不使已建立连接失效。令牌被拒绝时保留设备记录并提示重新验证。设备 ID 由当前 BLE backend 提供，Windows 手机身份暂为单设备占位符，多设备留到后续。

认证/恢复成功 5 秒后发送一次本机网络状态；每次重新连接恢复都会重新计时。所有 BLE 消息通过串行发送队列避免分片交错。Windows 使用系统 curl.exe 探测百度与 Google，Android 用 HTTPS 请求；任一站点可达即判断有网。这里使用 HTTPS 连通性检测，不是 ICMP ping。

## 热点与 Wi-Fi provider

- Windows：assets/windows_network.ps1 通过 NetworkOperatorTetheringManager 创建、读取、启动和停止移动热点，用 PowerShell WinRT async bridge 等待系统操作，不依赖不支持的 Hosted Network。连接 Wi-Fi 使用 netsh WLAN profile，SSID 以 UTF-8 hex 编码、密码作 XML 转义。临时 XML 用后删除；连接轮询确认目标 SSID 后才报告成功。
- Android：NetworkControl 在工作线程经 su 运行 APK 内 RootHotspot helper（app_process），helper 尝试隐藏 API 豁免、创建系统 Context、调用 TetheringManager、等待回调并检查 AP 状态，再反射读取 SoftApConfiguration。无 root 或失败时尝试普通系统 API，并明确返回系统权限限制；修改系统设置权限不保证获得 tethering 特权。
- Android 11+ Wi-Fi：WifiNetworkSuggestion + ACTION_WIFI_ADD_NETWORKS 系统确认保存，并轮询实际 SSID；用户取消、保存失败、25 秒未切换都不报成功。Android 10 使用 WifiNetworkSpecifier，只提供用户批准的应用局部网络，不能等同于默认互联网网络。
- Dart PlatformNetworkControl 提供 startHotspot、stopHotspot、getHotspot、connectWifi；后续可以替换成 Rust/FRB provider，同时保留这些操作语义。

## Debug 页面操作

1. 手机连接电脑并验证配对码；分别退出进程重开验证设备记录，或短时关闭蓝牙后重开检查自动恢复。
2. 设置 → Debug：测试本机网络，或通知对端并查看 ACK。通知测试会同时尝试本机和对端通知；Android 13+ 首次需要系统通知权限。
3. 双端分别测试开启/关闭热点。“读取本机热点信息并发送给对端”可以读取已有热点，不要求重新开启。平台不能读出密码时，可手动填写表单继续联调。
4. 任意一端请求对方热点；接收端收到含允许/拒绝的系统通知，Debug 页面也有相同确认项。允许后调用热点 provider，再通过 BLE 发送凭据。requestId 必须匹配当前请求；两分钟后旧通知不可操作。热点操作结果会另行返回，确认接受不代表启动成功。
5. 收到凭据后点击“连接收到的 Wi-Fi”，或输入 SSID/密码后点击“连接输入的 Wi-Fi”。Android 会显示系统保存/连接确认；结果通过 BLE 回报。网络切换可能影响当前互联网，应查看设备真实网络状态。

日志可通过设置页显示路径和导出入口获取。文件记录网络操作结果、root 错误、BLE 恢复与通知操作；不记录密码、令牌和配对码正文。Android 原生日志可用 logcat 按 NetworkSharing 过滤。

## 已验证与需要实机确认

Windows PowerShell 5.1 脚本解析成功，并在开发机真实验证 Off → On（成功读取 SSID/密码）→ Off，测试后恢复关闭状态；未输出密码。Android Debug APK 和 Windows Debug EXE 构建成功，40 项 Flutter 测试与 Dart 静态分析通过。Android root、Wi-Fi 系统批准、BLE 双端传输和通知动作仍需真实设备联调。

## 参考来源与扩展约定

- GitHub [jfhr/mobile-hotspot](https://github.com/jfhr/mobile-hotspot)：MIT，Copyright 2020 Jakob Fahr。用于比对 GetInternetConnectionProfile、CreateFromConnectionProfile、Start/StopTetheringAsync 和配置读取流程；本项目未复制源码。
- [Microsoft NetworkOperatorTetheringManager](https://learn.microsoft.com/en-us/uwp/api/windows.networking.networkoperators.networkoperatortetheringmanager)：Windows 移动热点 API。
- [Android TetheringManager](https://developer.android.com/reference/android/net/TetheringManager) 和 [AOSP Wi-Fi shell 源码](https://android.googlesource.com/platform/packages/modules/Wifi/+/refs/heads/main/service/java/com/android/server/wifi/WifiShellCommand.java)：`cmd wifi start-softap` 本身不提供互联网 tethering。
- [Android Wi-Fi 保存请求](https://developer.android.com/develop/connectivity/wifi/wifi-save-network-passpoint-config)：ACTION_WIFI_ADD_NETWORKS 用户批准流程；Android Framework/AOSP 为 Apache-2.0。
- [flutter_local_notifications](https://github.com/MaikuB/flutter_local_notifications)：BSD-3-Clause；复用现成 Android 通知权限/动作与 Windows Toast 支持。

后续 agent 继续先检索开源实现与官方示例并积极尝试接入；Debug 阶段可发送热点凭据，不因未来安全工作搁置联调。SDK 不兼容时可提高 SDK；本轮 compileSdk 37、desugar_jdk_libs 2.1.5，并修复 Cargokit 对 `android-37.0` 格式的解析。

网络检索可使用用户配置的本机 127.0.0.1:10808 代理和 set-github-token.ps1；token 仅供当前进程使用，不打印、不写文档、不提交。平台行为按真实系统版本记录，不能把打开设置或编译成功当作功能实测。
