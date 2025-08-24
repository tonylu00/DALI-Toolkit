DALI-Toolkit: https://github.com/tonylu00/DALI-Toolkit
# DALI-Toolkit 后端服务架构与执行清单

本文件定义 server 目录的后端目标架构、技术选型、数据与权限模型、API 设计、集成方式与分阶段任务计划，作为逐条落地的工作蓝图。

## 背景与现状
- 现有 Flutter 客户端（`dalimaster`）已集成：
  - Casdoor 登录（`casdoor_flutter_sdk`），可获取 OIDC Token
  - 多平台运行（iOS/Android/Web/Desktop），有设备扫描/控制等本地能力
  - 国际化（`easy_localization`），页面示例：`settings.dart`、`home.dart`、`login.dart`、`short_address_manager_page.dart` 等
- 目标：新增后端“设备与权限管理、MQTT 网关接入、统一登录与接口鉴权”，并提供 Web 管理界面与移动端（Flutter App）共用的 REST API。

## 总体目标与功能清单
1) 设备管理
   - 作为 MQTT Server，与网关建立远程连接
   - MQTT 身份认证：固定用户名 + 使用设备 MAC 地址作为密码
   - 支持通过 MAC 将设备绑定到账户
   - 设备管理界面：树形“项目 -> 多级分区 -> 设备”，项目与分区支持给用户/用户组单独分配权限
   - 支持设备转移给其他账户、组织内共享访问
2) 统一身份认证：对接 Casdoor（SSO/OIDC）
3) 接口权限管理：使用 Casbin
   - 通过 Casdoor REST API 导入 Adapter/Enforcer 配置（模型与策略），本服务内控制授权
4) 设计 RESTful API + Web 图形界面，同时为移动端提供同样的管理能力

## 技术选型
- 语言与运行时
  - Go 1.22+（高并发网络、原生 Casbin/Casdoor/MQTT 生态成熟，单二进制易部署）
- Web 框架
  - Gin（性能与生态良好，社区广）
- 实时通道
  - WebSocket（供 App Cloud 模式使用，路径建议 `/ws`，支持 TLS/反向代理）
- 身份认证（AuthN）
  - Casdoor OIDC：服务端使用 casdoor-go-sdk 校验 ID/Access Token（JWKS 缓存）
- 鉴权（AuthZ）
  - Casbin v2：RBAC with Domains（多租户/层级授权），策略来源优先从 Casdoor 同步（REST 拉取），可落地至本地 Postgres 以加速
- MQTT Broker
  - mochi-mqtt（Go 实现、Hook 完整，易做认证与 ACL），后续可支持集群/持久会话
- 数据库
  - PostgreSQL 15+（UUID、JSONB、可选 ltree 用于树形路径），ORM 使用 GORM
- 缓存与会话
  - Redis（可选：保存短期票据、限流、任务队列，MQTT 会话暂使用内存，后续扩展）
- 配置与日志
  - Viper 读取环境变量/配置文件；Zap 结构化日志
- 迁移
  - golang-migrate（SQL/Go Migration）
- 前端管理界面（Admin）
  - Vite + React + Ant Design，打包为静态资源由后端 `/admin` 路由托管（后续 milestone 交付）

  可选 Flutter Web 集成：
  - 编译期：使用 go:embed 将 Flutter Web 构建产物内嵌（`server/internal/web`），按需开启。
  - 运行期：启动时检测当前工作目录的 `./app` 或通过 `--app-path=/abs/path/to/app` 指定，映射到 `/app/*` 静态路由。
  - 访问控制：`/app` 路由必须登录后才能访问；前端自动登录复用服务端的登录态（见“与 Flutter/Web 前端的集成”章节的自动登录方案）。

## 目录结构（拟定）
```
server/
  cmd/server/main.go              # 入口
  internal/
    api/                          # REST API 控制器（HTTP handlers）
      v1/
    auth/                         # OIDC 中间件、Token 校验、用户解析
    broker/                       # MQTT Broker 封装（mochi-mqtt），认证/ACL/Topic 策略
    casdoor/                      # Casdoor 客户端与策略同步器
    casbinx/                      # Enforcer 初始化、Model/Policy 装载
    domain/                       # 领域模型与服务接口
      models/                     # GORM 实体
      services/                   # 设备/项目/分区/权限等 Service
    store/                        # 数据访问与仓储（GORM/DAO）
    web/                          # 内嵌前端静态资源（构建产物）
    middleware/                   # 通用中间件（日志、恢复、限流、审计）
    migrations/                   # 数据库迁移
    telemetry/                    # 指标/Tracing（可选）
  pkg/                            # 可复用工具（如校验、错误定义）
  Makefile                        # 本地开发命令（可选）
  Dockerfile                      # 构建镜像
  docker-compose.yml              # 本地运行 PG/Redis/Server
  .env.example                    # 配置样例
```

## 数据模型（草案）
- 基础多租户：Casdoor Organization 视为“组织/租户”
- 树形结构：组织 -> 项目(Project) -> 分区(Partition, 支持多级) -> 设备(Device)

关键表（简化字段）：
- organizations(id, casdoor_org, name)
- users(id, casdoor_user_id, username, org_id, email, created_at, ...)
- groups(id, casdoor_group_id, name, org_id, ...)
- projects(id, org_id, name, remark, created_by, ...)
- partitions(id, project_id, parent_id, name, path, depth, ...)
  - path 采用“物化路径”或 PostgreSQL ltree（如 org.项目.分区.子分区）
- devices(id, mac CHAR(12), imei VARCHAR(16), device_type ENUM(lte_nr|wifi_eth|other), project_id, partition_id, display_name, status, last_seen_at, meta JSONB, ...)
  - mac 正规化为不含分隔符的大写 12 HEX（示例：A1B2C3D4E5F6）
  - imei 保持为仅数字字符串，长度通常 14~16，存在时可作为主标识
- device_bindings(device_id, user_id, bound_at, bound_by)
- device_shares(device_id, subject_type ENUM(user|group), subject_id, role, granted_by, granted_at)
- device_transfers(id, device_id, from_subject, to_subject, status, created_at, processed_at)
- casbin_rule（若采用本地适配器存储策略）
- audit_logs(id, actor, action, target_type, target_id, detail JSONB, ip, ua, ts)

说明：
- 所有增删改均写审计日志（审计与追溯）
- 设备“所有权”通过 device_shares 中 role=owner 表达，转移即 owner 变更

## 权限模型（Casbin）
- 模型：RBAC with Domains
  - p, sub, dom, obj, act
  - g, sub, role, dom
- Domain 约定：
  - org:<orgId>
  - project:<projectId>
  - partition:<partitionId>
  - device:<deviceId|mac>

多租户与超级组织：
- 租户=Casdoor 组织（organization），所有业务资源与授权策略均绑定 orgId。
- 仅 Casdoor 的内置默认组织（built-in default org，例如 `built-in` 或配置项 `CASDOOR_SUPER_ORG`）具备跨租户管理能力，可在任何 org 域内进行读写与授权；其策略加载为“超级域匹配”，实现方式：
  - 在 Enforce 时，若 subject 属于超级组织，则允许 dom 任意匹配（或通过额外的 `g_super` 链接到所有域角色）。
  - API 层仍要求明确指定操作目标的 orgId，便于审计与限流。
- 普通组织用户仅能在自身 org 域内访问资源；所有查询默认追加 org 过滤（DB 与 Casbin 双重）。
- 角色建议：
  - org_admin / org_viewer
  - project_owner / project_admin / project_viewer
  - partition_admin / partition_viewer
  - device_owner / device_editor / device_viewer
- 对象（obj）与动作（act）
  - obj: devices, projects, partitions, users, groups, permissions, mqtt, audit
  - act: read, write, manage, transfer, share

模型示意（model.conf 摘要）：
```
[request_definition]
 r = sub, dom, obj, act

[policy_definition]
 p = sub, dom, obj, act

[role_definition]
 g = _, _, _

[policy_effect]
 e = some(where (p.eft == allow))

[matchers]
 m = g(r.sub, p.sub, r.dom) && r.dom == p.dom && r.obj == p.obj && r.act == p.act
```

策略示例（policy.csv 摘要）：
```
# 用户/组在不同域的角色
p, role:project_admin, project:123, devices, manage
p, role:project_viewer, project:123, devices, read

# 用户 -> 角色（带域）
g, user:alice, role:project_admin, project:123
```

Casdoor 集成：
- 从 Casdoor REST API 拉取/导入模型与策略；若 Casdoor 维护的是全局策略，我们在导入后按 org/project/partition 进行域过滤与扩展
- 启动时加载，后续定时增量同步（或管理操作触发即时同步）

## MQTT Broker 设计
- 使用 mochi-mqtt 嵌入式 Broker
- 连接认证（CONNECT Hook）
  - 固定用户名：如 `device`
  - 密码：设备 MAC（12 位 HEX，不含冒号/横线），大小写都接受，入库统一上层大写
  - 客户端 ID 建议：`mac` 或 `mac@something`
  - 若设备未登记，可记为“未绑定”状态，允许连接但限制主题（仅注册/申诉主题）
- 主题命名与 ACL（订阅/发布权限）
  - 设备标识优先级：IMEI > MAC；均需规范化（IMEI：纯数字；MAC：12 位大写 HEX 无分隔符）
  - Topic 统一采用设备标识占位：`devices/<ID>/...`，其中 `<ID>` 为 IMEI 或 MAC
  - 设备上行：`devices/<ID>/up`
  - 设备下行：`devices/<ID>/down`
  - 状态/遗嘱：`devices/<ID>/status`
  - 自注册：`devices/<ID>/register`（设备首次上线发送 JSON 载荷，包含自身 IMEI/MAC 与能力摘要）
  - Hook 内基于设备标识与授权关系做 ACL：设备仅能发布 `<ID>/up` 与 `<ID>/status|register`，订阅 `<ID>/down`
- 网关/设备上线后：
  - 更新 `last_seen_at`
  - 若首次见到 MAC，记录为“待绑定”并产生审计事件
  - 多租户：设备资源上的 orgId 由绑定关系决定；未绑定设备仅对超级组织或具备全局注册权限的主体可见/可认领。

## RESTful API（V1 草案）
认证：
- Bearer Token（Casdoor OIDC），后端中间件校验并解析 user/org 信息

错误格式：
```
{ "error": { "code": "...", "message": "...", "details": {} } }
```

通用查询：分页 `?page=&pageSize=`，排序 `?sort=`，过滤 `?q=`

主要端点：
- 自身信息
  - GET /api/v1/auth/me -> 当前用户、所在组织、角色摘要
  - POST /api/v1/auth/switch-org { orgId } -> 切换活跃组织（仅用户属于该组织或为超级组织时生效）
- 设备
  - GET /api/v1/devices?projectId=&partitionId=&status=&q=&idType=imei|mac（默认限定当前活跃 org）
  - GET /api/v1/devices/:id?by=imei|mac
  - POST /api/v1/devices/bind { id, idType: imei|mac, userId? 默认当前用户, projectId, partitionId }
  - POST /api/v1/devices/:id/transfer?by=imei|mac { toUserId | toGroupId }
  - POST /api/v1/devices/:id/share?by=imei|mac { subjectType: user|group, subjectId, role }
  - DELETE /api/v1/devices/:id/share?by=imei|mac { subjectType, subjectId }
  - PATCH /api/v1/devices/:id?by=imei|mac { displayName, tags, meta }
- 项目 & 分区
  - GET /api/v1/projects
  - POST /api/v1/projects { name, remark }
  - PATCH /api/v1/projects/:id { name, remark }
  - DELETE /api/v1/projects/:id
  - GET /api/v1/projects/:id/partitions/tree
  - POST /api/v1/partitions { projectId, parentId, name }
  - PATCH /api/v1/partitions/:id { name, parentId? 允许移动 }
  - DELETE /api/v1/partitions/:id
- 权限（基于 Casbin）
  - GET /api/v1/permissions/subjects?projectId=&partitionId=&deviceMac=
  - POST /api/v1/permissions/grant { domain, subject(user|group), role }
  - POST /api/v1/permissions/revoke { domain, subject(user|group), role }
  - GET /api/v1/roles -> 角色字典
- 用户 & 组（从 Casdoor 拉取/缓存）
  - GET /api/v1/users?q=（限定当前活跃 org，超级组织可加 `orgId=` 查询任意）
  - GET /api/v1/groups?q=（限定当前活跃 org，超级组织可加 `orgId=` 查询任意）
- MQTT 辅助
  - GET /api/v1/mqtt/status -> 基本指标（连接数、主题）
  - POST /api/v1/mqtt/kick { clientId }
- 审计
  - GET /api/v1/audit?actor=&action=&targetType=&targetId=

说明：
- 授权检查：所有写操作在进入 Service 前进行 Casbin Enforce
- 域计算：根据 projectId/partitionId/deviceMac 推导 domain（如 `project:123`）

## 与 Flutter/Web 前端的集成
- Flutter
  - 继续使用 `casdoor_flutter_sdk` 完成登录，拿到 `access_token`
  - 调用 REST API 时设置 `Authorization: Bearer <token>`
  - 新增页面：
    - 设备树管理（项目/分区/设备）
    - 设备绑定/转移/共享
    - 权限查看与授权
    - Cloud 连接（WebSocket）：
      - 入口：连接方式选择“Cloud”，与本地 USB 并列
      - 点击连接后弹窗展示设备树（调用 `/api/v1/projects`、`/api/v1/projects/:id/partitions/tree`、`/api/v1/devices`）
      - 选择目标设备后，建立 `wss://<server>/ws?deviceId=<ID>&by=imei|mac` 连接；协议：
        - App -> Server：与 USB 完全一致的二进制帧或文本命令，按现有编解码
        - Server -> MQTT：将 App 的数据透传到 `devices/<ID>/down`
        - MQTT -> Server：订阅 `devices/<ID>/up` 与 `devices/<ID>/status`，反馈通过 WS 推给 App
      - 关闭连接：WS 关闭即释放 MQTT 订阅；异常断开需重连与节流
    - 设备添加：
      - 扫码添加：解析二维码中的 IMEI 或 MAC，进行规范化（IMEI：仅数字；MAC：去分隔转大写）
      - 手动输入添加：提供 IMEI/MAC 两种输入模式与校验；
      - LTE/NR 设备通过 IMEI 添加；其他类型通过 MAC 添加；
      - 规范化后调用 `POST /api/v1/devices/bind` 完成绑定；
      - 设备自注册：设备首次上线会向 `devices/<ID>/register` 发送 JSON，如 `{ "imei": "861234...", "mac": "A1B2...", "cap": {...} }`，后端将据此创建或补全设备记录。
- Web Admin（后续里程碑交付）
  - React + AntD：仪表盘、项目/分区树、设备列表、设备详情、用户&组、授权、审计日志、MQTT 监控

Flutter Web 客户端集成与自动登录：
- 部署模式：
  1) 内嵌模式：通过 go:embed 将 `build/web` 产物打入可执行文件，服务端 `/app` 路由直接提供；
  2) 外部目录：通过启动参数或目录检测挂载 `./app`，适合 CI/CD 独立构建前端；
- 访问控制：
  - `/app` 由服务器侧中间件保护，未登录返回 302 跳转至后端登录/授权页或 401。
  - 自动登录方式：
    - 同域 Cookie Session：服务端在 OIDC 登陆后签发短期 Session（HttpOnly + Secure + SameSite=Lax/Strict）；Flutter Web 客户端通过浏览器携带 Cookie 获取 `/api/v1/auth/me` 完成会话验证。
    - 或短期 Web Token（STS）：服务端为已登录用户签发短期 Web Token（极短有效期，绑定 UA/IP），前端初始化时以查询参数或一次性接口获取并保存在内存，用于首轮 API 调用，随后依旧通过 Cookie 会话维持。
  - 注销：清理服务端会话并使 `/app` 访问被拒绝。

## 安全与合规
- OIDC Token 校验（ISS/AUD/EXP）与 JWKS 缓存刷新
- 最小权限原则：设备仅能访问自身主题；用户访问仅限其域内资源
- 速率限制与防刷：对登录回调、绑定/授权等写操作限流
- 输入校验与标准化：MAC 统一 12 HEX（不含分隔符）
 - 输入校验与标准化：
   - MAC：统一 12 位 HEX（不含分隔符，转为大写）
   - IMEI：仅数字，常见长度 14~16，保留前导 0
- 审计日志：所有敏感变更记录 actor/ip/ua
- 配置密钥：从环境变量读取，严禁硬编码

## 配置与环境变量（示例）
```
SERVER_ADDR=:8080
LOG_LEVEL=info

PG_DSN=postgres://user:pass@localhost:5432/dali?sslmode=disable
REDIS_ADDR=localhost:6379

CASDOOR_SERVER_URL=https://door.casdoor.com
CASDOOR_CLIENT_ID=...
CASDOOR_CLIENT_SECRET=...
CASDOOR_ORG=YOUR_ORG
CASDOOR_APP=YOUR_APP
CASDOOR_SUPER_ORG=built-in           # 超级组织（具备跨租户管理能力）

MQTT_LISTEN_ADDR=:1883
MQTT_DEVICE_USERNAME=device
APP_EMBED_ENABLED=true               # 是否启用 go:embed 内嵌 Web 客户端
APP_STATIC_PATH=./app                # 外部 Web 客户端路径（当未内嵌或覆盖时）
WS_ENABLE=true                       # 是否启用 WebSocket Cloud 通道
WS_PATH=/ws                          # WS 路由
WS_MAX_CONN_PER_USER=4               # 单用户最大并发 WS 连接数
```

## 里程碑与任务分解
M0. 准备与脚手架
- [ ] 初始化 Go 模块与基础目录（cmd/internal/pkg）
- [ ] 添加配置、日志、错误处理基座
- [ ] Dockerfile + docker-compose（Postgres/Redis/Server）

M1. 数据层与迁移
- [ ] 设计 GORM 模型与 migrations（含物化路径/ltree）
- [ ] 接入 Postgres，完成基础 CRUD 的集成测试
 - [ ] 为所有资源增加 org_id 并实现全局租户过滤（含超级组织旁路）

M2. 认证与鉴权
- [ ] OIDC 中间件（Casdoor Token 校验，用户上下文注入）
- [ ] Casbin Enforcer 初始化（导入 Casdoor 模型与策略）
- [ ] 策略同步器（启动加载 + 周期增量）
 - [ ] 多租户：解析用户所属组织集合与活跃组织；仅超级组织具备跨租户能力
 - [ ] Enforce 适配域：org -> project/partition/device 映射；超级组织放行逻辑

M2.5. Cloud WS Proxy（App<->WS<->MQTT）
- [ ] WebSocket 服务：`/ws`（支持 TLS，兼容反向代理）
- [ ] 鉴权：复用 OIDC Bearer（握手时校验），绑定用户上下文
- [ ] 设备选择：支持 `deviceId` + `by=imei|mac`，校验对目标域的读写权限
- [ ] 透传编解码：与 USB 协议一致，二进制/文本透明
- [ ] WS <-> MQTT 映射：下行 -> `devices/<ID>/down`，上行 <- `devices/<ID>/{up,status}`
- [ ] 会话与限流：单用户并发、心跳、超时与重连策略
- [ ] 审计：连接、断连、错误与关键命令

M3. MQTT Broker
- [ ] 嵌入 mochi-mqtt，启动监听 :1883
- [ ] 认证：用户名固定、密码=MAC；MAC 规范化
- [ ] ACL：仅允许设备访问自身主题；遗嘱/状态处理
- [ ] 设备在线状态与 last_seen 维护
- [ ] 主题：支持 IMEI 或 MAC 作为 `<ID>`；注册通道 `devices/<ID>/register`
- [ ] 自注册：解析注册 JSON（包含 imei/mac/capabilities），创建或更新设备记录
 - [ ] 未绑定设备的多租户可见性与认领流程（仅超级组织或具备注册权限者可见/可绑定）

M4. 设备/项目/分区 API
- [ ] 设备查询/绑定/转移/共享 API + 审计（支持 `idType=imei|mac`）
- [ ] 项目/分区 CRUD + 树移动 API
- [ ] 基于 Casbin 的授权校验（域映射）
 - [ ] 设备绑定/转移/共享均需校验 org 一致性或具备跨租户权限
 - [ ] 设备添加：扫码/手动（字段校验与规范化）

M5. 权限管理 API
- [ ] 角色列表、授权/回收接口
- [ ] 与 Casdoor 策略的同步/回写（按选型，支持本地存储与同步上游）

M6. 管理界面（Admin）
- [ ] Vite + React + AntD 脚手架
- [ ] 设备树、绑定/共享/转移操作 UI
- [ ] 权限管理、审计日志、MQTT 监控页面
 - [ ] `/app` 静态资源挂载策略（内嵌/外部目录）与登录态复用

M7. 稳定性与发布
- [ ] e2e 测试（API + MQTT）与回归
- [ ] 性能与安全加固（限流、CORS、CSRF、Header 安全）
- [ ] CI/CD 与版本化发布

M8. 规则引擎（低优先级）
- [ ] 网关分组：定义 `gateway_groups`、`gateway_group_members` 数据模型
- [ ] 规则模型与 DSL：条件（来源网关/主题/内容匹配）与动作（转发/广播/丢弃）
- [ ] 执行器：从某网关上行匹配规则并转发到同组其他网关（MQTT 多主题发布）
- [ ] 管理 API：创建/更新/启用/停用规则与组成员
- [ ] 性能与安全：循环转发检测、限流与审计

## 与现有项目的耦合点（从 Flutter 端提取的信息）
- 登录：Flutter 端已集成 Casdoor，后端仅需校验 Bearer Token
- 设备标识：使用 MAC 地址作为后端标准主键之一（设备侧 MQTT 密码也用 MAC）
  - 扩展：蜂窝设备支持 IMEI 作为主标识；MQTT topic 使用 IMEI/MAC 二选一
- 未来在 `pages/` 中新增设备管理与权限授权页面即可对接后端 REST API

## 后续扩展（可选）
- MQTT 集群化（mochi-mqtt + Redis/一致性），WebSocket MQTT（前端直连）
- 指令下发编排、长任务/工单系统
- 设备影子（Device Shadow）与状态缓存
- 事件总线（Kafka/NATS）对接分析平台

---

状态：本文件为执行蓝图。下一步将按 M0-M1 开始落地代码与环境脚手架。
