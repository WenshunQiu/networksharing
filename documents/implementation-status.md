# 实现进度与运行说明

更新日期：2026-11-08

## 开发环境

- 使用 FVM 管理 Flutter stable；本次验证版本为 Flutter 3.47.9、Dart 3.13.7。
- Fluent UI 为 4.17.0，解析版本由 pubspec.lock 记录。
- 所有 Flutter/Dart 命令通过 fvm 执行。需要网络代理时，在同一 PowerShell 会话执行用户提供的 set-proxy.ps1；不把代理或本机 SDK 绝对路径写入产品代码。

## 已实现

- Fluent UI 正文与标题字体按平台继承系统中文字体：Windows Microsoft YaHei UI，Android 系统 sans-serif；未捆绑额外中文字体。平台字体映射有单测覆盖。

- 应用设置通过 SharedPreferencesAsync 本地持久化：后台监测、通知、启动监测、热点空闲关闭时长和共享请求确认模式；未知设置值安全回退。设置页更改后自动保存，并在加载/保存失败时显示状态。
- 设置序列化采用版本化 JSON，加载失败时禁止编辑覆盖原数据，保存失败时恢复之前的界面值；扩展和迁移约定见 settings.md。当前仅保存偏好，尚未驱动后台、通知和热点系统能力。

- Android/Windows 共用 Fluent UI 页面；按窗口宽度切换窄屏和展开导航，断点为 760 逻辑像素。
- 配对首页支持 Rust 安全随机码生成、五分钟有效期、重新生成、输入清洗与六位校验。
- 配对 ViewModel 处理重复提交、超时、异常和销毁/模式切换后的迟到响应。
- 配对码由 Rust 使用系统安全随机源生成，带随机 session ID 与 5 分钟有效期；Flutter 通过 flutter_rust_bridge 调用。
- Rust 提供版本化配对 envelope JSON 编解码、session 内序号/消息 ID 重放保护，并由 FRB 暴露给 Dart。
- Rust/FRB 提供双向共享会话状态机：显式同意、热点准备、凭据就绪、加入网络、连通验证、活动、空闲关闭及终止状态；通过 revision 拒绝过期并发更新，并阻止同一设备参与冲突会话。
- 明确区分本地配对码预览与真实设备配对。当前尚未通过蓝牙广播验证码、认证对端或持久化配对身份。
- 设备状态页支持主动网络检测。访问 Microsoft 连通性测试地址，响应匹配时报告可用，失败或重定向时报告未知，不据此触发自动共享。
- 领域网络接口和 Repository 与页面分离；蓝牙通过 PairingRepository 接口预留接入点。
- 蓝牙基础检查已接入配对页：Windows 通过 Rust WinRT/FRB 查询适配器与经典蓝牙已绑定设备；Android 通过平台通道按需申请附近设备权限并枚举已绑定设备。两端共享 Repository 契约、ViewModel 与页面。系统绑定不等于应用配对；平台边界和实机清单见 platform-capabilities.md。
- BLE 控制通道已接入应用层：定义 Android/Windows 共用 GATT 服务及写入/通知特征；配对页可在显示码模式广播，在输入码模式扫描 NetworkSharing 服务并发起 Central 连接，展示传输连接状态与诊断消息。支持带消息 ID、总长和偏移的 BLE MTU 分片重组。当前不代表配对认证；诊断消息不能执行热点操作或承载凭据。

## 尚未实现

- BLE 双设备实机互通、配对码认证通道、设备身份与可信设备持久化。当前配对页面不会报告真实配对成功。
- 原生后台服务、托盘、网络状态订阅和交互式通知。
- Android/Windows 热点控制、Wi-Fi 自动接入、客户端空闲计时与自动关闭。
- Shizuku/Root Provider 及权限引导。
- Rust 已承载配对会话、消息封套、重放检查和进程内共享状态机；尚未接入真实热点 Provider。

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

新增结构化 JSONL 文件日志、2 MiB 轮转和排队刷新接口；修复 BLE 初始化等待、Windows Peripheral 不支持的连接事件订阅、CCCD 和订阅者检查。扫描结果实时更新。当前 32 项 Flutter 测试、5 项 Rust 测试和 Dart 静态分析通过。当前 transport 仍为 Flutter BLE 插件，后续分阶段迁移到 Rust。


### Rust transport 迁移起点

已引入 btleplug 0.13.5 与 Windows 服务 UUID 扫描探针，并通过 FRB 重新生成桥接；探针暂未接入 UI，Android 返回明确的 JNI 初始化缺失状态。现有 Flutter BLE transport 保留。补充平台专属 CCCD：Android 显式注册，Windows 由 WinRT 管理。最终 33 项 Flutter 测试及 Dart 分析通过；Rust 5 项测试通过。完整迁移边界和日志导出命令见 rust-bluetooth-migration.md。
