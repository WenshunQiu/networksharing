# 平台能力与验收矩阵

当前实现日期：2026-11-08。编译通过不能替代真实蓝牙设备互通验收。

| 能力 | Android | Windows |
| --- | --- | --- |
| 蓝牙是否可用/开启 | BluetoothManager + BluetoothAdapter | Rust WinRT BluetoothAdapter + Radio |
| 已绑定设备枚举 | BluetoothAdapter.bondedDevices | Rust WinRT BluetoothDevice 的已配对筛选器 + DeviceInformation |
| 运行时权限 | Android 12+ 按用户点击申请 BLUETOOTH_CONNECT | 无应用内权限申请；系统拒绝返回 permissionDenied |
| BLE Central API 支持 | 插件 API 可用；实机扫描/连接待验证 | 插件 API 可用；实机扫描/连接待验证 |
| BLE Peripheral/GATT API 支持 | 插件 API 可用；实机广播/回调待验证 | 插件 API 可用；实机广播/回调待验证 |
| 配对码认证及身份保存 | 待实现 | 待实现 |
| 控制消息发送/接收 | BLE GATT 已接入；待实机确认 | BLE GATT 已接入；待实机确认 |
| 自动启停热点、加入 Wi-Fi | 待实现 | 待实现 |
| 后台驻留、通知、状态订阅 | 待实现 | 待实现 |

## 当前调用流程

配对页的刷新按钮 -> BluetoothViewModel -> BluetoothRepository。

- Windows：PlatformBluetoothRepository -> FRB inspectWindowsBluetooth -> Rust WinRT backend。查询在 FRB worker 执行，使用配平的 RoInitialize/RoUninitialize 初始化 MTA。
- Android：PlatformBluetoothRepository -> networksharing/bluetooth MethodChannel -> MainActivity。系统权限请求与 Activity 生命周期绑定；拒绝、重复请求和销毁均完成 pending result。系统查询异常转为错误，不包含设备地址或凭据日志。

Android 11 及以下使用普通 BLUETOOTH 权限；Android 12 及以上声明 BLUETOOTH_CONNECT、BLUETOOTH_SCAN 和 BLUETOOTH_ADVERTISE，并按需由 BLE 插件授权。编译通过只验证插件 API 链接；真实扫描、广播和 GATT 回调仍须用实体设备验证。无适配器、关闭、权限不足、查询失败分别返回结构化状态。没有查到已绑定设备并不代表附近没有设备。

Windows 目前使用经典蓝牙设备选择器，未实现 BLE 未绑定设备发现，也不声称列出所有 BLE-only 设备。查询到设备不代表它运行 NetworkSharing，更不代表本应用已经建立信任。

## BLE transport 评估

当前 bluetooth_low_energy 插件文档列出 Android 与 Windows 均支持 Central 发现、连接、GATT 读写/通知，也均支持 Peripheral 服务、广播、写回调和通知 API。应用已接入 GATT 服务、配对页广播/扫描/连接控件、诊断消息和 MTU 分片重组。尚无双设备实机结果，因此需继续按下方步骤验收广播发现、连接和消息方向。

系统设备 ID 只供后端建立连接，不作为跨平台可信身份。后续通过认证握手建立应用设备 ID，再与控制通道绑定。分帧/协议状态可由 Rust 管理；Android 原生层仅承载权限和必要的系统 API。

## 实机验收清单

1. 无适配器、蓝牙关闭与开启时，点击刷新分别显示对应状态；允许打开系统设置后再刷新。
2. Android 首次点击出现附近设备授权；拒绝后不显示设备，重新授权后刷新能恢复；永久拒绝时引导到应用系统权限设置。
3. 在系统蓝牙设置先绑定手机/电脑，刷新后能看到对端名称；该设备应标注为系统已绑定而非应用已认证。
4. Android 在权限对话框中旋转、返回、销毁 Activity 后，应用不崩溃；重复点击不会发起第二个请求。
5. 查询中退出页面/应用不更新已销毁 ViewModel。超时不标记成功；当前超时仅结束 UI 等待，不取消系统查询或权限对话框。
6. 设备地址和名称不得进入一般日志；最终 transport 需另做两设备间端到端认证、断线和重连测试。

单元测试可验证分帧重组、通道映射与 ViewModel 状态；编译验证两端 API 可用性。还需 Android 手机与 Windows 电脑双向轮测：先在手机选“显示配对码”并开启广播，在 Windows 选“输入配对码”扫描、连接后发送链路测试消息；再交换角色，验证手机作为 Central 时同样可发现并发送。两端均需在对方界面看到消息。断线重连、权限拒绝及后台恢复可随后补测。
