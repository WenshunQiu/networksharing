# NetworkSharing 架构与扩展约定

版本：0.1  
状态：实现指导草案  
适用平台：Android、Windows  
主架构：Flutter MVVM + 领域层 + 平台适配器 + Rust 核心

## 1. 架构目标

- 让页面逻辑不依赖 Android/Windows 原生 API。
- 把热点、蓝牙、通知和后台执行差异限制在可替换的适配器中。
- 让共享会话状态机与消息协议可独立测试。
- 新平台能力可以以新实现接入，而不是在 ViewModel 中增加平台分支。
- 手机、平板与 Windows 共享页面和交互流程，通过窗口尺寸自适应布局，而非按操作系统复制 UI。

## 2. 依赖方向

依赖由外向内：

`View -> ViewModel -> Use Case / Domain -> Repository interface <- Repository implementation -> Platform adapter / Rust bridge`

ViewModel 不得直接调用 MethodChannel、原生 API、Rust 生成绑定或具体插件。Domain 定义能力接口和模型；Repository 实现将领域操作路由到 Rust 核心或平台适配器。平台适配器不得依赖 Flutter UI。

## 3. 建议模块

| 模块 | 职责 | 平台相关性 |
| --- | --- | --- |
| `presentation` | 共用页面、ViewModel、UI 状态、响应式布局和用户操作 | Flutter；按窗口约束布局 |
| `domain` | 实体、值对象、用例、Repository/Provider 契约、错误类型 | 无 |
| `data` | Repository 实现、序列化、持久化、Provider 选择 | 少量 |
| `platform/android` | Android 通知、前台服务、蓝牙、热点/Wi-Fi、权限 | Android |
| `platform/windows` | Windows 通知、托盘/后台、蓝牙、移动热点/Wi-Fi、权限 | Windows |
| Rust crate | 配对/共享协议、状态机、校验、重放保护、超时/重试和 transport orchestration | 通用逻辑无平台依赖；系统 transport 通过 backend 接入 |

目录名可以随工程演进调整，但上述依赖边界保持稳定。Rust bridge 生成代码视为 Repository/Data 层绑定，不直接暴露给 UI。跨平台协议与通信编排优先在 Rust 实现，再由 FRB codegen 生成 Dart API。蓝牙底层如依赖系统原生 API，封装在 Rust transport backend 中并通过 FRB 接口调用。界面断点依据可用窗口宽度和交互方式计算，不以操作系统选择整套页面。

## 4. 关键领域契约

首批接口建议包含：

- `PairingRepository`：创建配对会话、验证码、保存/撤销可信设备、重连。
- `ControlChannel`：发现、连接、认证会话、发送/接收版本化消息。首期 Bluetooth LE/GATT 或经典蓝牙承载须经 Windows 与 Android 实机互通验证后定型。
- `ConnectivityMonitor`：流式报告可用/不可用/未知及变化时间。
- `HotspotProvider`：报告能力并启动、读取配置、停止本机热点。
- `WifiJoinProvider`：报告能力、加入热点、验证目标网络可用性、断开。
- `ClientPresenceProvider`：报告客户端数量/标识的能力与状态，用于空闲关闭。
- `BackgroundExecution`：启动/停止后台监测，检查授权并打开相关系统设置。
- `NotificationGateway`：显示本地通知、处理通知动作并将动作转为领域命令。
- `CredentialVault`：安全保存配对密钥；热点密码仅短时持有，默认不持久化。

能力调用采用异步结果和可取消任务。每种系统能力必须能报告“不支持”“需要用户操作”“权限缺失”“暂时失败”等结构化结果，不能只返回布尔值。

## 5. 会话状态与消息

`NetworkShareSession` 是双向共享的唯一领域会话模型，方向由 `requester` 和 `provider` 字段表达。建议状态：

`requested -> awaiting_approval -> preparing_provider -> credentials_ready -> joining -> verifying -> active -> idle_closing -> closed`

任一非终态可以进入 `failed` 或 `cancelled`。状态迁移集中于 Domain/Rust 状态机；UI 将状态映射为展示文案和动作。每个状态定义允许的下一步、超时、重试策略和用户可执行动作。

蓝牙消息信封至少包含 `protocolVersion`、`messageType`、`messageId`、`requestId`、`sessionId`、`sentAt`、`sequence` 和负载。需要保证重放检测、重复消息幂等、超时后的迟到响应被忽略。热点凭据字段只存在于加密消息负载中，不进入通用遥测或日志。

配对认证使用成熟、经过审查的协议与库；低熵短码不能直接当作加密密钥，也不能只比较明文验证码就认定安全。根据蓝牙安全模式选择绑定系统安全连接或标准口令认证密钥交换方案，实施前单独评审。

无需严格识别上游网络，但须避免本应用产生共享环路：已知本机正使用对端提供的网络时，不向同一对端反向提供网络。双方同时请求时通过确定性仲裁只保留一个方向；网络状态抖动采用去抖和通知冷却。

## 6. Provider 选择和能力协商

Repository 通过能力探测选择可用实现，而不是检查设备品牌后到处写条件分支。Android 热点 Provider 可按部署情况实现公开 API、Shizuku、Root 和系统面板引导路径；Windows Provider 实现移动热点 API 或系统设置引导。每个实现声明能力、前置授权和可执行动作。

Provider 的选择结果和用户动作应可观测，例如 `requires_user_action(open_hotspot_settings)`；用户操作后重新探测能力。高级 Provider 由用户显式启用，授权撤回、Shizuku 服务断开或 Root 不可用时，安全退回其他实现。

## 7. 后台与空闲策略

网络监测和通知需使用平台适用的后台机制。后台服务只做轻量状态观察和通知，不在后台未经用户同意启动对端热点。Android 电池优化/通知/后台权限按需检查并提供设置深链；Windows 处理应用关闭、托盘驻留、睡眠和恢复。

热点保持规则由领域策略配置：用户确认共享后持续开启；`ClientPresenceProvider` 确认无客户端达到 `idleTimeout` 后，进入宽限检查，再关闭热点。无法读取客户端列表时使用单独标识的近似空闲策略。蓝牙断开本身不得立即关闭热点。

仅自动关闭由本应用创建且仍持有控制权的热点。若会话使用的是用户已手动开启的热点，默认不自动关闭，也不改写配置；记录资源所有权，防止取消或失败清理影响用户已有连接。

## 8. 测试策略

- Domain/Rust：协议兼容、状态迁移、重复/迟到消息、超时和空闲关闭策略的单元测试。
- Repository：Provider 选择、权限失败回退、取消传播的测试。
- Platform adapter：真机/Windows 实机验证系统权限、后台限制、热点与 Wi-Fi 行为。
- Integration：两台设备端到端配对和双向共享，覆盖断连、拒绝、权限撤销及热点已开启。
- UI：覆盖 ViewModel 状态到页面动作映射；平台行为不能仅以模拟器测试通过作为验收。

## 9. 新功能扩展流程

1. 在 `documents/` 新增或更新需求，描述触发条件、授权、状态、失败和验收标准。
2. 确认功能属于通用领域能力还是平台 Provider；先更新能力接口与领域模型。
3. 定义错误类型、事件和协议变更；需要跨设备交互时同步更新 `protocol.md` 及兼容策略。
4. 实现 Repository/Provider，再由 Use Case 暴露给 ViewModel。
5. 对已有平台实现补齐支持或明确记录限制；不得让不支持的平台静默假成功。
6. 更新 `platform-capabilities.md`、测试矩阵和变更记录。

## 10. 多设备演进

首期允许 UI 限制为一个活动配对设备，但领域层使用设备 ID 关联会话，配对设备通过集合仓库管理，不把单一设备字段写死在全局状态中。后续增加多设备时，可扩展设备列表、活动设备选择、并发会话策略和冲突仲裁；共享页面仍按窄屏/大屏自适应呈现。首期不实现多热点并发、多个请求并发或复杂设备分组。

## 11. 相关文档

- `documents/requirements.md`：产品范围、用户流程、阶段与验收。
- `documents/architecture.md`：本文，模块边界与扩展约定。
- `documents/protocol.md`：待创建，蓝牙消息协议、认证和兼容策略。
- `documents/platform-capabilities.md`：待创建，Android/Windows 版本能力和实测结果。
- `documents/decisions/`：待创建，重要架构决策记录。
