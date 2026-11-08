# 实现进度与运行说明

更新日期：2026-11-08

## 开发环境

- 使用 FVM 管理 Flutter stable；本次验证版本为 Flutter 3.47.9、Dart 3.13.7。
- Fluent UI 为 4.17.0，解析版本由 pubspec.lock 记录。
- 所有 Flutter/Dart 命令通过 fvm 执行。需要网络代理时，在同一 PowerShell 会话执行用户提供的 set-proxy.ps1；不把代理或本机 SDK 绝对路径写入产品代码。

## 已实现

- Android/Windows 共用 Fluent UI 页面；按窗口宽度切换窄屏和展开导航，断点为 760 逻辑像素。
- 配对首页支持 Rust 安全随机码生成、五分钟有效期、重新生成、输入清洗与六位校验。
- 配对 ViewModel 处理重复提交、超时、异常和销毁/模式切换后的迟到响应。
- 配对码由 Rust 使用系统安全随机源生成，带随机 session ID 与 5 分钟有效期；Flutter 通过 flutter_rust_bridge 调用。
- Rust 提供版本化配对 envelope JSON 编解码、session 内序号/消息 ID 重放保护，并由 FRB 暴露给 Dart。
- 明确区分本地配对码预览与真实设备配对。当前尚未通过蓝牙广播验证码、认证对端或持久化配对身份。
- 设备状态页支持主动网络检测。访问 Microsoft 连通性测试地址，响应匹配时报告可用，失败或重定向时报告未知，不据此触发自动共享。
- 领域网络接口和 Repository 与页面分离；蓝牙通过 PairingRepository 接口预留接入点。

## 尚未实现

- 蓝牙发现、认证通道、设备身份与可信设备持久化。
- 原生后台服务、托盘、网络状态订阅和交互式通知。
- Android/Windows 热点控制、Wi-Fi 自动接入、客户端空闲计时与自动关闭。
- Shizuku/Root Provider 及权限引导。
- Rust 目前承载配对会话、消息封套和重放检查；热点共享状态机尚未实现。

## 验证命令

在项目根目录执行：

~~~powershell
fvm flutter pub get
fvm dart analyze lib test
fvm flutter test --no-pub
fvm flutter run -d windows
~~~

Flutter analyze 在当前环境有 LSP 初始化消息截断问题；Dart analyze 是本轮采用的静态分析入口。Widget 测试覆盖窄屏/大屏构建；领域测试覆盖配对与网络检测状态，不依赖真实蓝牙或互联网。真实设备网络与蓝牙功能须另做集成测试。

本轮验证：Android Debug APK 构建成功；12 个 Flutter 测试通过，3 个 Rust 单测通过，Dart analyze 无问题。Android Gradle 构建需要 android.overridePathCheck=true，因为工程路径包含中文。Windows 整包仍被 MSBuild/Cargokit 自定义生成步骤的 no such file or directory 阻断；Windows 批处理启动仍需单独定位。Rust crate 可由本机 MSVC 工具链通过测试编译。

## 下一阶段

下一步验证 Android/Windows 可互通的蓝牙 transport，并完成配对认证方案。Rust 的协议模型和状态处理继续由 FRB 暴露；平台系统 API 可封装为 Rust transport backend。配对码不能直接用作加密密钥。后台服务必须独立于 Flutter 页面生命周期；热点和特权适配器按能力检测逐步接入。
