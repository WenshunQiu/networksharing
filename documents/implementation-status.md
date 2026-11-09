# 实现进度与运行说明

更新日期：2026-11-10

当前正常使用流程以 [application-sharing.md](application-sharing.md) 为准；下方日期较早的段落为阶段记录，不能覆盖最新行为。

## 正式共享集成（2026-11-10）

- 已先将上一轮 Debug 提交 796c1c1 合并到 master（0ea2f4a），再在 debug 分支推进本轮集成。
- 用户已实机确认上一版 Debug 所有项目成功；Windows 一次开热点失败为主动触发，不作为缺陷。新组装的正常流程待用户实测。
- SharingViewModel 接入双向离线提醒、双方确认、热点准备、会话凭据下发、Wi-Fi 自动加入、互联网验证、结果回传、超时和取消。设备状态页提供进度、允许/拒绝、请求和停止按钮，以及持久化的每设备授权。
- 应用启动后主动恢复配对连接，20 秒周期检查兜底；Windows 广播不再依赖配对页 build。既有 10 秒心跳、30 秒超时和扫描失败 5 秒重试保留。
- Android 通知允许/拒绝使用官方后台 isolate 入口，经过 SharedPreferencesAsync 邮箱交给现有 BLE 主 isolate，不拉起 Activity。返回键放入后台；前台服务保持进程，强制停止不自动复活。
- 设置已实际控制网络监测、通知提醒、手动/自动请求和空闲时长。网络检测遵循用户意见，继续百度/Google 任一可达即在线，否则离线，不新增未知状态。
- 本应用拥有热点标记可重启恢复。Windows ClientCount 与 Android Root 客户端回调支持空闲计数，持续为零且复查后才关闭；未知数量不当作零，已有系统热点不自动关闭。
- 正常共享协议新增 share_*，与 Debug 消息隔离；Rust 状态模型和迁移目标保留，目前实际跨设备编排仍在 Dart，BLE 与 Provider 未宣称完成 Rust 迁移。
- 本轮 52 项 Flutter 测试全部通过，Flutter analyze 无问题。覆盖完整共享编排、后台通知投递、权限持久化重建、窄屏设备权限对话框、请求超时、取消期间清理及客户端空闲检查。最新提交的 Android Debug APK、Windows Debug 和 Release 构建结果见下方交付记录。

## 2026-11-10 交付验证

- Flutter analyze / Dart analyze：无问题；全部 Flutter 测试 52 项通过。
- fvm flutter build apk --debug：成功，产物 build/app/outputs/flutter-apk/app-debug.apk。
- fvm flutter build windows --debug：成功，产物 build/windows/x64/runner/Debug/networksharing.exe。
- fvm flutter build windows --release：成功，产物 build/windows/x64/runner/Release/networksharing.exe。
- Windows getHotspot 实际只读探测成功，确认 enabled=false、clientCount=0，未输出热点密码；本轮未为验证而改变系统热点状态。
- Git 功能提交 9239a66；流程与 Agent 文档提交 c25de1e。交付前合入 master，未纳入不相关的 devtools_options.yaml。
- 以上是构建与自动化证据；正常双向共享、后台通知动作和热点客户端计数变化需用户按 application-sharing.md 进行双端实机测试。

## 开发环境

- 使用 FVM 管理 Flutter stable；本次验证版本为 Flutter 3.47.9、Dart 3.13.7。
- Fluent UI 为 4.17.0，解析版本由 pubspec.lock 记录。
- 所有 Flutter/Dart 命令通过 fvm 执行。需要网络代理时，在同一 PowerShell 会话执行用户提供的 set-proxy.ps1；不把代理或本机 SDK 绝对路径写入产品代码。

## 已实现

- Fluent UI 正文与标题字体按平台继承系统中文字体：Windows Microsoft YaHei UI，Android 系统 sans-serif；未捆绑额外中文字体。平台字体映射有单测覆盖。

- 应用设置通过 SharedPreferencesAsync 本地持久化：后台监测、通知、启动监测、热点空闲关闭时长和共享请求确认模式；未知设置值安全回退。设置页更改后自动保存，并在加载/保存失败时显示状态。
- 设置序列化采用版本化 JSON，加载失败时禁止编辑覆盖原数据，保存失败时恢复之前的界面值；扩展和迁移约定见 settings.md。正式自动策略、通知和 BLE 后台连接已接入。

- Android/Windows 共用 Fluent UI 页面；按窗口宽度切换窄屏和展开导航，断点为 760 逻辑像素。
- 配对首页支持 Rust 安全随机码生成、五分钟有效期、重新生成、输入清洗与六位校验。
- 配对 ViewModel 处理重复提交、超时、异常和销毁/模式切换后的迟到响应。
- 配对码由 Rust 使用系统安全随机源生成，带随机 session ID 与 5 分钟有效期；Flutter 通过 flutter_rust_bridge 调用。
- Rust 提供版本化配对 envelope JSON 编解码、session 内序号/消息 ID 重放保护，并由 FRB 暴露给 Dart。
- Rust/FRB 提供双向共享会话状态机：显式同意、热点准备、凭据就绪、加入网络、连通验证、活动、空闲关闭及终止状态；通过 revision 拒绝过期并发更新，并阻止同一设备参与冲突会话。
- 手机通过 BLE 验证 Windows 当前显示的验证码；双方保存同一恢复令牌以恢复应用配对。此阶段为单设备调试认证，尚非加密会话。
- 设备状态页显示每 30 秒刷新的网络检测，并发访问百度与 Google 的 HTTPS 首页，任一可达即可判断为在线；SharingViewModel 已接入完整共享流程。
- 领域网络接口和 Repository 与页面分离；蓝牙通过 PairingRepository 接口预留接入点。
- 蓝牙基础检查已接入配对页：Windows 通过 Rust WinRT/FRB 查询适配器与经典蓝牙已绑定设备；Android 通过平台通道按需申请附近设备权限并枚举已绑定设备。两端共享 Repository 契约、ViewModel 与页面。系统绑定不等于应用配对；平台边界和实机清单见 platform-capabilities.md。
- BLE 控制通道已接入应用层：Windows 广播 NetworkSharing GATT 服务，Android 扫描并连接；支持 BLE MTU 分片重组与串行发送队列。认证/恢复、心跳、网络状态和 Debug 热点凭据经此通道传输。

## 仍待实机验证或后续实现

- BLE、配对恢复、交互通知和两端网络控制仍需目标 Android 手机与 Windows 电脑联测，尤其 root shell、Android 热点配置读取及 BLE 后台行为。
- Android 前台服务与 Windows 托盘已实现；进程被系统/用户结束后的自动启动、登录自启和厂商后台限制仍未处理。
- 多设备连接、更细粒度的业务权限仍属后续阶段；当前单设备热点授权和空闲自动关闭已接入，需要实机确认客户端计数。
- Rust 已承载配对会话、消息封套和进程内共享状态机；当前热点/Wi-Fi 平台控制暂由 Flutter 适配层与 Windows PowerShell WinRT adapter 执行。

## 后台能力与扩展路线（2026-11-08）

- Windows runner 在窗口最小化或点击关闭时隐藏主窗口并保留托盘图标；托盘左键恢复，右键菜单可恢复或退出。托盘只维持桌面进程，不等同于 Windows 服务或登录自启；应用退出后 BLE 广播/连接结束。
- Android 在 BLE 广播或 Central 连接期间由 Flutter 前台发起 connectedDevice 前台服务，显示常驻通知；连接/广播都结束后停止服务。系统通知权限受 Android 13+ 控制；若通知被禁用，需在实机核实目标系统对服务启动的处理。服务用于保活承载进程，当前 BLE 插件是否在 Activity 暂停、Doze 和厂商省电策略下保持 GATT，仍需实机验证。
- “设备状态”中的当前设备使用独立磁贴展示在线/等待状态和应用配对结果；“管理权限”跳转至 Android 应用权限页或 Windows 蓝牙设置。Windows 手机名称尚未由后端提供，因此仅展示通用设备名。
- 当前仍为单一活动 BLE peer，不能同时管理多个设备或独立权限。多设备后续方案：将单个 connectedDeviceId 与全局 applicationPaired 演进为 DeviceSession 集合，按稳定设备身份保存认证状态、在线状态、能力/授权范围、最近连接时间和会话 revision；每台设备独立断连、撤销权限与重连，热点共享状态仍以单个活动网络会话协调冲突。广播发现、设备配对存储、并发 GATT 限制与 UI 列表作为独立阶段评审，本轮不实施。

## Debug 与当前连接能力（2026-11-09）

- Windows 保存“已配对手机”占位身份和恢复令牌；手机保存发现的 Windows BLE ID 和同一令牌。启动先加载持久化，再处理配对/恢复。Windows 持续广播等待手机，Android 启动后扫描并恢复。
- Android 正确码验证成功后隐藏验证码输入和开始配对按钮；错误码/超时仍保留输入区域便于重试。附近 Windows 设备以独立磁贴呈现。
- 设置增加 Debug 页面入口；网络检测沿用 HTTP 连通性探测，电脑端将结果经 BLE 通知手机，手机回复 ACK，测试结果和事件写入本机结构化日志。
- Debug 热点与 Wi-Fi 已接入 Windows WinRT/NETSH、Android root helper/系统网络请求；可显式发送 SSID 和密码。系统 Wi-Fi 选择页保留为辅助入口。普通权限 Android 热点仍可能被系统拒绝，须看具体返回值。
- Windows 关闭窗口保持默认缩回托盘，不再询问，也移除了设置页面对应选项。

## 断线恢复与网络控制边界（2026-11-09）

- 首次验证码认证成功后由 Windows 广播端生成随机恢复令牌，双端分别持久化同一令牌；Windows 键按单设备占位身份保存，手机按 BLE 设备 ID 保存。Android 启动后周期扫描已配对 Windows 设备，重新连接并验证恢复令牌。拒绝恢复会保留设备记录并提示重新输入验证码。后台 BLE 持续性与 Windows Peripheral 重启后可发现性需要实机验证。
- 网络检测并发访问 www.baidu.com 和 www.google.com 的 HTTPS 首页，任一返回可接受状态即认为可联网，并将可达主机列表通过调试消息通知对端。
- Windows 移动热点通过 WinRT NetworkOperatorTetheringManager 读取、启动与停止；开发机已验证 start 返回 On 并读取凭据，stop 返回 Off，恢复到测试前的关闭状态。跨设备凭据传输与真实 Wi-Fi 加入仍待联测。
- Android Debug 热点先运行 APK 内 RootHotspot helper（su/app_process + TetheringManager，尝试隐藏 API 豁免并反射读取热点配置），普通权限 fallback 尝试 TetheringManager 并返回系统权限限制；失败不伪称成功。修改系统设置权限本身不授予公开 tethering API 权限。Root、系统 API 与凭据读取需按目标机型实测。
- Debug Wi-Fi 页面提供输入 SSID/密码并连接、以及连接蓝牙收到的凭据；连接结果会经 BLE 返回对端。
- 调试通知注册 Android 通知动作和 Windows Toast 动作；通知测试可同时触发两端本机通知，热点请求带 requestId 并提供系统通知内允许/拒绝。允许时回调启动热点并回传凭据，无需 Debug 页面保持打开。
- BLE 所有消息经 repository 队列串行写入，避免心跳、认证和凭据分片交错。实际 BLE 和通知动作仍需 Android/Windows 双端实机联测。
- Debug 阶段允许显式发送 SSID 和密码用于联调；正式功能接入 Rust 加密会话后再开放自动网络切换。

## 后续 Agent 工作方式

- 本项目目前处于积极验证与 Debug 阶段。遇到 Android/Windows 热点、Wi-Fi、后台或蓝牙能力时，先检索官方文档和已有开源项目，优先实际接入平台 API 并在目标设备尝试，不要因为正式产品阶段的安全限制而提前搁置 Debug 功能。
- Debug 阶段可通过当前蓝牙链路发送热点/Wi-Fi 凭据以验证端到端流程；应提供明确的调试入口、关键操作日志和调用结果，便于开发者实机测试。安全加固、加密会话及面向普通用户的风险提示统一留到后续阶段处理，不作为当前联调的阻断条件。
- 平台调用失败时保留具体错误和可复现信息，并在当前阶段记录实际能力、系统版本要求和待实测项；不要把“打开设置页面”描述为已实现自动控制，也不要把未经验证的机型行为写成确定结论。
- 新功能动手前先检索 GitHub、官方样例和活跃开源项目，优先复用可维护的现成方案，避免重复造轮子；记录参考项目、许可证和适配差异。
- Windows 热点接入 Microsoft WinRT NetworkOperatorTetheringManager；PowerShell adapter 用 System.Runtime.WindowsRuntime 等待系统异步操作。GitHub jfhr/mobile-hotspot（MIT，Jakob Fahr）用于比对相同 WinRT API 生命周期，本项目未复制其源码。
- Android 参考 TetheringManager、WifiNetworkSuggestion 与 WifiNetworkSpecifier API。WifiNetworkSpecifier 仅提供用户批准的本地连接，不等于系统互联网默认网络；Android 11+ Debug 加入已保存 Wi-Fi 会显示系统确认界面。

## 自动网络与设备在线状态（2026-11-09）

- Windows Dart HttpClient 在实机上同时探测百度和 Google 均失败，但系统 curl.exe 对百度返回 HTTP 200，Google DNS 解析超时；Windows 网络探测现使用系统 curl.exe，Android 仍用 Dart HttpClient。
- DeviceStatus 页面启动时检测本机网络并每 30 秒刷新一次。BLE 活跃时每 10 秒发心跳，30 秒无对端心跳/响应即离线；新连接 5 秒后仅发送一次本机网络结果给对端。
- Windows 网卡实测 Hosted Network 不可用；移动热点改为 WinRT WLAN tethering provider。PowerShell 5.1 脚本已在开发机完成 Off → On（含凭据）→ Off 的真实启停验证，未输出 SSID 或密码。
- 本轮 Android Debug APK 构建成功。Root helper/普通系统 API、热点 Wi-Fi 切换、双端 BLE 凭据、通知动作均待实体设备联调。
- 网络检索已使用用户提供的 127.0.0.1:10808 代理访问 GitHub API 并比对开源项目；后续可使用本机 set-github-token.ps1，但 token 不能打印、写进文档或提交。

## 2026-11-08 实机反馈修正

- 早期实机反馈已改为手机发现电脑、可选系统 bond、GATT 连接、应用码验证；应用码握手现经 BLE 实际往返校验。Windows Peripheral 仍依赖适配器与驱动。
- Central 连接存在时，发送固定通过对端 GATT write 特征；只有无 Central 连接时才使用本机 Peripheral notify，修复本机同时广播和连接时错误走通知路径、二次发送因无订阅者失败的问题。发送按钮在发送过程中置为忙态。
- 设置页显示日志文件绝对路径并可导出当前日志与轮转日志；支持目录不可用时回退到临时目录。错误记录保留截断后的平台异常详情。
- 更新后验证：Flutter 33 项测试、Rust 5 项测试通过；Android Debug APK 与 Windows Debug 构建通过。两设备连接、广播和配对仍待现场复测。

## 当前验证结果（2026-11-09）

Android Debug APK 和 Windows Debug EXE 均构建成功；Dart 静态分析无问题，40 项 Flutter 测试通过。新增覆盖 Windows 重建后恢复令牌、Android 心跳超时自动重连、手动断开停止重连、恢复拒绝保留记录、通知确认只启动一次热点、凭据 ACK、Windows Peripheral 回传凭据。Windows 热点启停及凭据读取实测成功。没有 Android 实机连接，root/系统 Wi-Fi/通知动作与双端 BLE 必须继续联调。

## 验证命令

在项目根目录执行：

~~~powershell
fvm flutter pub get
fvm dart analyze lib test
fvm flutter test --no-pub
fvm flutter run -d windows
~~~

Flutter analyze 在当前环境有 LSP 初始化消息截断问题；Dart analyze 是本轮采用的静态分析入口。Widget 测试覆盖窄屏/大屏构建；领域测试覆盖配对与网络检测状态，不依赖真实蓝牙或互联网。真实设备网络与蓝牙功能须另做集成测试。

基础 UI/协议阶段验证：Android Debug APK 构建成功；Windows Debug 构建成功；12 个 Flutter 测试通过，当前 5 个 Rust 单测通过，fvm dart analyze lib test 无问题。Windows 工程移动后清理旧 CMake 缓存并重建通过，产物为 build/windows/x64/runner/Debug/networksharing.exe。共享状态机的跨设备行为仍需真实蓝牙与系统热点 Provider 集成测试；状态机目前只在本进程内存中运行。

## 下一阶段

BLE 应用接入阶段：30 项 Flutter 测试通过，Dart 静态分析无问题；Android Debug APK 和 Windows Debug EXE 均构建成功。新增分片/乱序重组及 ViewModel 传输流程测试。真实手机/电脑发现和双向诊断消息待实机测试；需要时按测试结果修正平台行为。

设置持久化阶段：21 项 Flutter 测试通过（含默认值/重载/损坏文档保护、读写失败和窄屏/大屏设置页面）；Dart 静态分析无问题；新增 shared_preferences 插件后的 Android Debug APK、Windows Debug EXE 均构建成功。重启恢复目前通过异步内存后端新建 Repository 验证，仍需物理设备/进程重启验收。Windows 构建曾被本机空的 path_provider_windows 缓存目录阻断，备份空目录后重新下载已解决。

下一步验证 Android/Windows 可互通的蓝牙 transport，并完成配对认证方案。Rust 的协议模型和状态处理继续由 FRB 暴露；平台系统 API 可封装为 Rust transport backend。配对码不能直接用作加密密钥。后台服务必须独立于 Flutter 页面生命周期；热点和特权适配器按能力检测逐步接入。

## debug 分支：诊断基线

最新单向配对流程见 [ble-device-feedback.md](ble-device-feedback.md)，网络与热点联调见 [network-debug.md](network-debug.md)。Debug 阶段已允许显式发送凭据；加密和普通用户风险提示留待后续统一加固。

新增结构化 JSONL 文件日志、2 MiB 轮转和排队刷新接口；修复 BLE 初始化等待、Windows Peripheral 不支持的连接事件订阅、CCCD 和订阅者检查。扫描结果实时更新。当前 32 项 Flutter 测试、5 项 Rust 测试和 Dart 静态分析通过。当前 transport 仍为 Flutter BLE 插件，后续分阶段迁移到 Rust。


### Rust transport 迁移起点

已引入 btleplug 0.13.5 与 Windows 服务 UUID 扫描探针，并通过 FRB 重新生成桥接；探针暂未接入 UI，Android 返回明确的 JNI 初始化缺失状态。现有 Flutter BLE transport 保留。补充平台专属 CCCD：Android 显式注册，Windows 由 WinRT 管理。最终 33 项 Flutter 测试及 Dart 分析通过；Rust 5 项测试通过。完整迁移边界和日志导出命令见 rust-bluetooth-migration.md。
