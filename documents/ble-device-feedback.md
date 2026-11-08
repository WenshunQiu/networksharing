# BLE 实机反馈与权限约定

本阶段在 debug 分支修正现有 transport，并保留 Rust/btleplug 整体迁移计划。当前页面使用的实际传输仍为 bluetooth_low_energy；Rust 扫描探针尚未替换它。

## Android 权限

Android 6–11（API 23–30）：扫描需要运行时定位权限，并检查系统定位服务开关。清单将 ACCESS_COARSE_LOCATION / ACCESS_FINE_LOCATION 限定到 API 30。

Android 12 及以上（API 31+）：使用 BLUETOOTH_SCAN、BLUETOOTH_CONNECT、BLUETOOTH_ADVERTISE 运行时权限，扫描声明 neverForLocation。本应用不从蓝牙扫描推断位置，因此不额外要求定位权限；该标记可能过滤部分广播，若后续设备兼容性测试显示需要调整，再单独评估。

开始扫描、广播或连接前，由原生 prepare 接口完成权限请求，再检查插件适配器状态。日志记录 SDK、定位是否必需、定位开关和适配器角色。已开启蓝牙不代表扫描权限或定位条件已满足。

## 日志结论与修复

第一轮日志显示 Android 扫描到 Windows 并发现 GATT 服务，首次连接的通知订阅失败，随后诊断消息发送出现 StateError。早期 Windows 广播尝试也失败。修复 Windows GATT 广播创建、Android 初始化/权限时序、连接/服务失败清理，并确保已建立连接优先使用 GATT write 通道。

## 配对边界

目标流程（当前单向方案）：Windows 广播 NetworkSharing 服务并显示短期码 → Android 扫描、连接 Windows → Android 输入 Windows 屏幕上的码 → Windows 校验并返回结果 → 认证成功后允许敏感数据。

广播仅标识服务，不包含配对码、热点凭据或秘密。BLE 连接、系统 bond、应用认证是三个独立状态。诊断测试消息可用于未认证通道，但不能承载凭据。

当前 BLE 应用层验证码流程由 Windows 持有并校验短期码，Android 经已连接的 GATT 通道提交验证码，Windows 返回 success 布尔结果。日志仅记录请求、成功、拒绝、超时和错误类型，不记录验证码或消息正文。Windows 主动扫描手机、Android 主动展示码和系统 Bluetooth bond 均不再是目标配对流程。应用认证结果与断开状态关联；只有认证成功的会话才可继续接入敏感数据授权。

第三轮实机日志发现电脑码原先仅在 GATT 连接后显示，且手机在空输入时仍能发起请求。现调整为 Windows 页面加载即显示有效配对码（无需等待手机连接），Android 在提交前从文本框同步 ViewModel 值并校验必须是 6 位。普通链路测试消息不再进入 JSON 认证解析，因此不会产生认证解析失败日志。日志中的 133 是 Android BLE descriptor 写入状态失败，之后重连成功；增加退避重试尚待后续稳定性工作。

本阶段的验证码回环不是密码学认证协议：6 位码在 BLE 链路内传输，未实施 PAKE、密钥协商、消息完整性或跨进程会话密钥，因此不能把当前 success 作为热点凭据加密保障。热点敏感数据仍须等待后续安全握手实现。

## 日志与复测

设置 → 诊断日志可查看实际路径或导出当前文件及上一轮转文件。Android 使用应用私有目录，Windows 通常为 %APPDATA%/com.example/networksharing/logs/networksharing.log。每份文件最大 2 MiB；导出前等待排队写入结束。

两端均更新版本并重新启动后，电脑应自动广播并显示验证码；手机扫描电脑、连接并输入正确码，应显示成功。然后输入错误码，应显示拒绝；电脑屏幕上的码过期后再试，应失败。断开后重复连接，只有当前显示的码可成功。查看日志确认两端都有结果事件，且无验证码/消息正文。若失败，导出两端同一时段日志，并注明 Android 版本和操作步骤。

参考：[Android 蓝牙权限](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions)。

## 第二轮实机结果（14:25–14:27 UTC）

手机为 API 36，附近设备权限成功，locationRequired=false。Windows 广播成功，Android 系统 bond 确认、GATT 连接和通知订阅成功。Android 两次写入均为 4 个分片（20/20/20/7），Windows 收到对应两组分片；双向通知发送尚无日志证明。

随后实机复测中 Windows 发现了手机、手机也扫描到 Windows；双向诊断消息及 GATT 分片重组成功。现已确定采用单向目标方案：Windows 只广播并展示配对码，Android 只扫描/连接 Windows 并输入电脑配对码。Windows 扫描路径不会出现在配对 UI 中。

应用配对码请求/响应及接受/拒绝/超时日志已经实现，并有正确码、错误码、无效码清空后的测试。手机日志从不包含输入码；Windows 日志不写入接收消息正文。认证 UI 显示成功仅说明对端比较了本次短码，不能代表密钥协商或安全会话。

## 第三轮实机结果与界面反馈（15:27–15:28 UTC）

最新手机与电脑日志显示，手机首次 GATT 通知订阅遇到 Android status 133，断开后第二次连接和订阅成功。手机发送的链路测试消息已被 Windows 收到并完成分片重组；电脑没有弹出提示是因为原先只记日志，没有对应界面反馈。手机随后提交 6 位码，Windows 收到请求并接受，且认证结果已回传到手机；两端认证都成功。API 36 的附近设备权限已授予，不要求定位权限。

现已在 Windows 配对页显示认证成功状态和链路测试接收时间，并在“本机状态”显示 BLE 连接及应用配对状态。Android 状态页优先显示扫描所得的电脑名称；Windows 当前蓝牙后端未暴露中央设备名称，因此只显示“手机已完成应用配对”，不展示伪造名称或原始蓝牙地址。
