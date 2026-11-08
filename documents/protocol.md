# 配对与控制消息协议（草案）

版本：1（草案）  
状态：BLE GATT 承载骨架与分帧已实现；认证握手尚未实现

## 消息封套

首期采用 UTF-8 JSON。每条消息包含：

| 字段 | 类型 | 规则 |
| --- | --- | --- |
| version | integer | 当前为 1；未知版本拒绝 |
| messageId | string | 每消息唯一，用于去重 |
| sessionId | string | 绑定一次配对/共享会话 |
| type | string | 已知消息类型枚举 |
| sentAt | ISO-8601 UTC | 过期提示参考，不是单独的防重放措施 |
| sequence | non-negative integer | 会话内严格递增 |
| payload | object | 类型专属字段；敏感内容不得写日志 |

## 首期消息类型

- hello：能力与协议版本协商，不携带验证码明文。
- challenge：交换认证挑战参数。
- proof：认证协议计算出的证明。
- accepted：认证成功后返回设备信息。
- rejected：拒绝原因代码，不包含敏感信息。

## 安全决策

六位配对码熵不足，禁止直接作为加密密钥或在未认证链路上明文比较。真实握手必须使用经审查的口令认证密钥交换（PAKE）实现，或绑定系统提供的加密认证蓝牙配对通道。配对码用于用户核对会话，不取代设备会话密钥。设备身份绑定、密钥派生、安全存储和重放策略需单独评审。

## 演进规则

- 不改变已发布消息类型的含义；未知类型拒绝并记录非敏感错误码。
- 兼容扩展使用可选字段；改变认证语义或必需字段时提升主版本。
- 认证完成后才允许传输热点凭据；凭据负载必须端到端加密且绑定会话。
- 防重放依赖随机会话、序号和消息 ID；时间戳只用于过期提示。

Rust 代码提供封套 JSON 编解码与序号/消息 ID 去重，并经 FRB 暴露给 Dart；Rust session API 负责生成随机 session ID、6 位配对码与 5 分钟到期时间。Flutter 当前实现 Android/Windows 共用的 BLE GATT 服务 UUID `77a10001-7a4b-4d31-9b22-7b8e12a45001`，写入特征 UUID `77a10002-7a4b-4d31-9b22-7b8e12a45001`，通知特征 UUID `77a10003-7a4b-4d31-9b22-7b8e12a45001`。配对页可以广播该服务、扫描发现、连接后写入和订阅 notification。消息按 BLE 单次操作上限分片，每片包含 16 位消息 ID、总字节数、偏移量和负载，以支持重组。此阶段的连接和消息均未认证；尚未完成对端身份校验、PAKE、端到端加密和 Rust 重放策略集成，任何 GATT 消息均不得触发热点或凭据操作。

## 共享会话状态

Rust sharing API 为 UI 和后续平台 Provider 提供单设备会话状态机：

awaitingApproval -> preparingProvider -> credentialsReady -> joiningNetwork -> verifyingNetwork -> active -> idleClosing -> closed

任一准备或连接阶段可进入 failed；只有 awaitingApproval 可进入 rejected。活跃和空闲关闭状态可被显式停止或恢复。每次变更都需传入预期 revision，不匹配时返回 stale_session_revision，避免异步通知或重连覆盖新状态。设备已有非终态会话时拒绝新请求；设备身份 ID 由已认证传输层提供。热点凭据只允许在认证配对完成后通过后续受保护的控制通道传输；当前状态 API 本身不传递或持久化凭据。

这个 API 当前是进程内协调模型，不代表设备间蓝牙连接或网络共享已实现。重启后的持久化、跨进程并发仲裁和设备端到端认证待后续阶段处理。
