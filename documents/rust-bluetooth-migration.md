# Rust 蓝牙迁移与扩展边界

更新：2026-11-08，工作分支：`debug`。

## 当前可运行范围

现有配对页面的扫描、广播、连接及 GATT 读写/通知仍由 `bluetooth_low_energy` 插件承载；Rust 承载配对协议、会话状态与 Windows 适配器查询。本阶段没有宣称已完成 Rust 双端 transport。

已加入 `btleplug 0.13.5`，并通过 FRB 生成 `probeRustBluetoothScan` 扫描诊断接口。Windows 探针按 NetworkSharing 服务 UUID 过滤、订阅事件后启动扫描、在限定时间内收集设备并停止扫描，拒绝并发探针。此接口暂不接入页面；返回的 btleplug ID 与 Flutter BLE 插件 ID 属于不同后端，不能混用。Android 调用探针明确返回 `android_btleplug_jni_init_required`，不会调用尚未初始化的 backend 而触发 panic。

## btleplug 的职责

[btleplug README](https://github.com/deviceplug/btleplug) 明确限定为 BLE Central：扫描、连接对端 GATT 服务、写入、订阅通知。它不支持 Peripheral，也不支持经典蓝牙。收发消息的方向与 Central/Peripheral 角色无关；建立一个 GATT 连接后即可双向通信，无需为反向共享热点再建立相反角色的连接。

应用配对要求一端显示码并广播、另一端输入码并扫描，因此仍需 Peripheral。计划保留双角色接口：Central 使用 btleplug；Peripheral 封装 Windows WinRT GattServiceProvider 和 Android BluetoothGattServer / BluetoothLeAdvertiser，优先在 Rust 管理生命周期，Android 保留必要的 JNI 系统回调。也可以评估 Rust Peripheral 库，但只有通过双平台 API 与构建验证后才替换平台实现。

## 接下来的迁移顺序

1. 完成 Rust Central 会话（缓存 Peripheral handle、连接/服务发现、写入、通知、断线事件、超时与资源释放），按后端整体切换；不能仅替换扫描而继续用插件连接。
2. Android 集成 btleplug Java/JNI helper：将依赖源码固定到可重现版本，按 upstream build-java 指引构建；由 Java 进入的线程调用 `btleplug::platform::init`，保证 application ClassLoader 可见。在初始化和权限成功前，Rust 不能创建 Android Manager。当前 minSdk 24 符合 upstream 要求。
3. Rust Peripheral 实现 GATT 注册、广告状态、写入响应、CCCD 订阅、通知上限及断线清理。只有替代路径可用后再移除 Flutter BLE 插件。
4. 将分帧/重组迁入 Rust，让两个角色共用协议实现；FRB 只暴露完整消息和结构化事件。随后实现配对码认证、可信设备和后台生命周期。

## 接口约定

- Flutter Repository / ViewModel 不保留平台蓝牙对象，页面只消费设备列表、能力状态、连接状态及诊断结果。MVVM 与自适应 Fluent UI 保持独立。
- Rust transport 持有连接、订阅和分片重组状态；后台服务持有 transport，不能依赖页面存活。多设备扩展使用独立 peer/session handle，禁止全局共享一个重组器。
- Windows 原生 backend 与 btleplug 使用不同版本的 windows crate；当前分别为 0.58 与 0.62。两套类型不得跨 backend 传递，API 边界只使用业务 DTO。
- Android 系统权限与 Activity 交互仍需原生层；热点控制 Provider、Root/Shizuku 与 BLE transport 分离。
- 对外事件包含操作阶段、可重试错误码、角色和匿名计数；普通日志禁止包含地址、设备名、配对码、热点凭据与消息正文。

## 文件日志

`AppLogger` 在应用支持目录的 `logs/networksharing.log` 追加 UTF-8 JSON Lines，超过 2 MiB 后保留上一份 `.1`，并提供 `flush()` 供后续导出前等待写入。日志记录按钮点击、扫描数量、权限结果、GATT 分片长度、通知订阅及失败阶段。

Windows 通常位于 `%APPDATA%` 下应用支持子目录；Android 位于应用私有支持目录，不会写入公共存储。实际位置以 `AppLogger.instance.filePath` 为准。Android 调试包可使用 `adb shell run-as com.example.networksharing find . -name networksharing.log` 查找，再用 `adb exec-out run-as com.example.networksharing cat <查到的相对路径>` 导出。导出级别选择和系统分享入口留待后续实现。

## 实机反馈

先用手机广播、电脑扫描，连接后分别发送链路测试消息；再交换角色。反馈失败时间、操作方向、系统版本和两端同一时间段的日志。重点检查首次授权后是否无需再次刷新即可扫描、Windows 是否能开启广播、第二次发送是否仍成功。诊断消息只验证 transport，不代表应用配对认证或热点共享已完成。
