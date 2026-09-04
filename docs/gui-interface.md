# Personal Pi GUI Development Interface

本文档定义当前 macOS GUI 的内部开发接口和扩展边界，供后续功能开发使用。它不是独立发布的 Swift SDK；接口调整必须同步更新调用方、测试和本文档。

## 1. 运行架构

~~~text
SwiftUI Views
    │  用户操作 / Published 状态
    ▼
AppState (@MainActor)
    ├── PiRPCClient ── stdin/stdout JSONL ── pi --mode rpc
    ├── PiProviderAuthBridge ── Node bridge ── Pi ModelRuntime
    ├── PiPackageBridge ── Node bridge ── Pi SettingsManager / PackageManager
    ├── AccountUsageStore ── Pi auth check + local Codex App Server
    ├── PiTaskStore ── local JSON
    ├── FigureArtifactStore ── structured tool details + local JSON index
    └── Session Catalog / Workspace Inspector ── filesystem + Git
~~~

核心原则：

- Pi Runtime 是 Agent、会话、模型、工具和资源的唯一事实来源。
- **AppState** 是 GUI 会话状态与导航状态的唯一协调入口。
- View 不直接写 Pi RPC JSON，也不直接解析 auth.json。
- 阻塞式文件扫描、Git、Node bridge 和进程操作不得在主线程执行。
- Global/Project 路径必须由当前用户目录和所选项目动态推导。

## 2. App 入口与页面路由

应用入口位于 PersonalPiApp.swift。应用 delegate 持有唯一 AppState，根容器将它作为 EnvironmentObject 注入全部页面。

RootView.swift 负责固定外壳：

~~~text
WindowChrome
SidebarView (238 pt)
DetailView
    ├── TopBar + active page
    └── ArtifactSidebarView (optional, global across pages)
~~~

AppSection 与页面映射：

| AppSection | View | 职责 |
|---|---|---|
| .overview | OverviewView | 当前作用域快捷对话、账户和用量摘要 |
| .sessions | SessionsView | 会话目录、消息、工具活动和会话操作 |
| .knowledge | KnowledgeView | Global/Project 知识目录入口 |
| .packages | PackagesView | Packages 与资源配置 |
| .projects | ProjectsView | 项目注册、Git 与会话统计 |
| .tasks | TasksView | 任务状态与未读结果 |
| .diagnostics | RuntimeDiagnosticsView | 本机运行环境检查 |
| .settings | SettingsView | Pi Global/Project/Effective 配置 |

新增一级页面时需要同步：

1. AppSection 的 case、title、icon。
2. DetailView 的路由分支。
3. 英文和简体中文 Localizable.strings。
4. 至少一个 UI navigation smoke test。

## 3. 作用域接口

PiWorkspaceScope 只有两个运行作用域：

- .workspace：当前 Project，Pi cwd 为项目根目录。
- .global：Global Chat，Pi cwd 为 ~/.pi/chat。

View 通过以下只读派生值获取当前作用域，不自行拼接路径：

| AppState 接口 | 含义 |
|---|---|
| activeWorkingDirectory | Pi 子进程实际 cwd |
| scopeTitle | 当前 Project 名称或 Global Chat |
| scopePathLabel | 当前作用域完整路径 |
| shortenedScopePath | 用于 UI 的 Home 缩写路径 |
| workspaceScope | 当前作用域类型 |
| workspace / workspaces | 当前项目与已注册项目 |

切换入口：

- selectWorkspace(_:)
- selectGlobalScope()
- createWorkspace()
- addExistingWorkspace()
- refreshWorkspace()

切换作用域会清理当前消息状态并重启 Pi RPC。任何未来的作用域相关状态都必须在 restartPiForScope() 中明确决定是清理、保留还是重新加载。

## 4. AppState 状态契约

AppState 标记为 @MainActor。View 可以订阅 Published 状态并调用 action，但不应直接修改 private(set) 属性。

### 4.1 对话与运行状态

| 状态 | 用途 |
|---|---|
| connectionState / isPiRunning | Pi CLI 连接状态 |
| composerText | 当前输入框内容 |
| messages | 当前活动分支的用户和助手消息 |
| activities | LLM 工具调用生命周期 |
| uiRequest | Extension 请求的 confirm/select/input/editor 交互 |
| isGenerating / agentStatus | 生成和状态栏展示 |

主要 action：

- connectPi()
- sendPrompt()
- startNewSession()
- stopGeneration()
- respondToUIRequest(...)
- compactSession(customInstructions:)

### 4.2 会话状态

| 状态 | 用途 |
|---|---|
| sessionId / sessionFile / sessionName | 当前 Pi 会话身份 |
| sessionModel / thinkingLevel | 当前模型与思考等级 |
| sessionMessageCount | 当前分支消息数量 |
| savedSessions / projectGroups | 会话目录快照 |
| sessionTree / sessionTreeLeafId | 当前会话树及活动叶节点 |
| forkMessages | 可作为 Fork 起点的用户消息 |

主要 action：

- refreshSavedSessions()
- switchSession(_:)
- resumeSession(matching:)
- presentSessionInfo()
- presentSessionTree() / navigateSessionTree(...)
- presentForkPicker() / forkCurrentSession(from:)
- cloneCurrentSession()
- exportCurrentSession(outputPath:)
- copyLastAssistantReply()
- reloadPiResources()

PiSavedSession.id 是任务归并使用的稳定身份。同一 Session 中继续发送消息必须更新同一 PiTaskRecord，不能每轮创建新任务。

### 4.3 模型、命令和账户

| 状态或 action | 用途 |
|---|---|
| availableModels | Pi 返回的完整模型列表 |
| availableThinkingLevels | 当前模型可用思考等级 |
| availableCommands | GUI 原生命令与 Pi 动态命令合并结果 |
| selectModel(_:) | 调用 set_model |
| selectThinkingLevel(_:) | 调用 set_thinking_level |
| refreshCommands() | 刷新 Extensions、Prompts、Skills 命令 |
| presentProviderAccounts(...) | 打开 Pi 原生登录/退出流程 |
| applySettingsChange() | 保存配置后刷新目录并重启运行时 |

### 4.4 图片产物

| 状态或接口 | 用途 |
|---|---|
| `isArtifactSidebarVisible` | 全局右侧栏开关；不属于某个页面 |
| `figureArtifactStore` | artifact 索引、当前选择、版本聚合与恢复 |
| `FigureArtifact` | `personalPiFigureArtifact` manifest 的类型化表示 |
| `FigureExporter` | PDF 矢量重排与 PNG/TIFF 尺寸、DPI 导出 |

`tool_execution_end` 携带图片 manifest 时，AppState 必须先 `upsert`，再自动显示右侧栏。切换 Session 优先选择相同 `sessionId` 的最近图片；切换 Project/Global 时回退到相同 CWD 的最近图片。

GUI 原生命令定义在 AppState.nativeCommands，执行分派位于 executeNativeCommand(_:)。新增原生命令时必须同时加入两处，并补充命令面板测试。

## 5. PiRPCClient 接口

PiRPCClient 管理一个 pi --mode rpc --approve 子进程。每条请求是单行 JSON，每个带响应的请求使用 UUID 关联回调。

### 5.1 生命周期与回调

| 接口 | 作用 |
|---|---|
| start(workingDirectory:projectTrusted:completion:) | 在给定 cwd 启动 Pi |
| stop() | 终止当前 Pi 子进程并清理管道 |
| onEvent | 普通 Pi 流事件 |
| onUIRequest | extension_ui_request |
| onError | 启动或协议错误 |
| onTermination | 子进程退出 |

### 5.2 当前封装的 RPC

| Pi RPC | Swift 接口 |
|---|---|
| prompt | sendPrompt(_:) |
| abort | abort(completion:) |
| new_session | newSession(...) |
| switch_session | switchSession(path:completion:) |
| get_state | requestState(...) |
| get_messages | requestMessages(...) |
| get_tree | requestSessionTree(...) |
| get_fork_messages | requestForkMessages(...) |
| fork | forkSession(entryId:completion:) |
| clone | cloneSession(completion:) |
| compact | compact(customInstructions:completion:) |
| export_html | exportHTML(outputPath:completion:) |
| get_last_assistant_text | requestLastAssistantText(...) |
| get_available_models | requestAvailableModels(...) |
| get_available_thinking_levels | requestAvailableThinkingLevels(...) |
| get_commands | requestCommands(...) |
| set_model | setModel(provider:modelId:completion:) |
| set_thinking_level | setThinkingLevel(_:completion:) |
| set_session_name | setSessionName(_:completion:) |
| get_session_stats | requestSessionStats(...) |
| extension_ui_response | respondToUIRequest(...) |

navigateTree 和资源 reload 在 Pi 0.84.3 中不是普通 RPC；它们通过打包的 Resources/personal-pi-runtime-extension.js 执行。内部命令必须使用 __personal_pi_ 前缀并从用户命令面板中过滤。

新增 RPC 时应：

1. 在 PiRPCClient 增加一个类型化方法，不让 View 构造字典。
2. 在解析层保留 Pi 的 error/message，避免把失败显示为成功。
3. 在 AppState 中转换为可展示状态。
4. 增加响应解码或 live RPC smoke test。
5. 更新 docs/pi-compatibility.md 的已接入列表。

## 6. 事件接口

当前 PiStreamEvent 解析并由 AppState.handle(_:) 消费：

- agent_start、agent_settled
- turn_start、turn_end
- message_update、message_end
- tool_execution_start、tool_execution_update、tool_execution_end
- compaction_start、compaction_end
- extension_error

`tool_execution_end.result.details.personalPiFigureArtifact` 会被独立解析为 `PiStreamEvent.figureArtifact`。聊天文本只用于人类阅读，不是产物接口。manifest v1 的完整字段见 [Scientific Figure 工作流](scientific-figure.md#7-artifact-manifest)。

extension_ui_request 走独立的 PiUIRequest 通道。当前 Session 页支持 confirm、select、input/editor 的基础卡片；notify、status、widget、title 和 editor text 尚未形成完整的 macOS 表现层。

待接入事件包括 queue_update、直接 RPC Bash 的 bash_execution_update、retry telemetry 以及更完整的 branch/tree 事件。新增事件时不得用单个字符串字段承载全部结构；先增加对应数据模型。

## 7. 非 RPC Bridge

### 7.1 Provider authentication

PiProviderAuthBridge 调用打包的 Node bridge，并使用当前安装版 Pi 的 ModelRuntime：

- listProviders(...)
- makeLoginProcess(...)
- logoutProvider(...)
- refreshModelCatalog(...)

Swift 只接收 Provider、登录方式、提示和结果，不读取 Pi 凭据文件。

### 7.2 Packages and resources

PiPackageBridge 使用 Pi 的 SettingsManager 和 DefaultPackageManager：

- load(...)
- install(...)
- remove(...)
- update(...)
- setResource(...)
- setConfiguredPaths(...)

打开 Packages 页必须保持只读；只有用户明确点击安装、移除、更新或保存路径时才执行写操作。

### 7.3 Account usage

AccountUsageStore 聚合：

- Pi auth check --json --no-refresh 的凭据就绪状态。
- 本机 Codex App Server 的 ChatGPT/Codex rate limits。
- 当前 Pi Session 的 Token、费用与上下文统计。

供应商不公开配额 API 时，GUI 必须显示“凭据可用、限额不可用”，不能伪造百分比。

## 8. 文件与持久化接口

| 数据 | 路径或存储 | 所有者 |
|---|---|---|
| Global Settings | ~/.pi/agent/settings.json | Pi |
| Project Settings | project/.pi/settings.json | Pi / Project |
| Sessions | 默认 ~/.pi/agent/sessions/ 或有效 sessionDir | Pi |
| Global Chat files | ~/.pi/chat/ | Personal Pi 工作目录 |
| Global Knowledge | ~/.pi/knowledge/ | Personal Pi |
| Project Knowledge | project/.pi/knowledge/ | Project |
| Task records | ~/.pi/agent/personal-pi-tasks.json | Personal Pi |
| Figure artifact index | ~/.pi/agent/personal-pi-figure-artifacts.json | Personal Pi |
| Project figures | project/.pi/artifacts/figures/ | Scientific Figure Extension |
| Global Chat figures | ~/.pi/chat/.pi/artifacts/figures/ | Scientific Figure Extension |
| Registered projects | UserDefaults personalPi.workspacePaths | Personal Pi |
| Interface language | UserDefaults personalPi.appLanguage | Personal Pi |

设置写入使用 PiSettingsFile.write(...) 的原子写入。保存前必须重新读取源文件，并只覆盖 GUI 拥有的字段，以保留未知键和其他进程的并发修改。

## 9. 并发和性能契约

- AppState、PiTaskStore、AccountUsageStore 的 UI 更新在 MainActor 完成。
- 会话扫描、Git 状态、认证检查、Package bridge 和其他阻塞工作使用 utility/background task。
- refreshSavedSessions() 使用 isRefreshingCatalog 与 needsCatalogRefresh 合并重复刷新请求。
- 同一个 Pi 子进程同一时间只有一个活动作用域。
- 新功能不得在 SwiftUI body 内执行文件读写、进程启动或网络请求。

## 10. 本地化与可访问性

- 英文：Resources/en.lproj/Localizable.strings
- 简体中文：Resources/zh-Hans.lproj/Localizable.strings
- 语言设置：AppLanguage 与 personalPi.appLanguage

用户可操作的关键控件应设置稳定的 accessibilityIdentifier，供 PersonalPiUITests 使用。新增文案必须同时补齐英文和中文，并用 plutil -lint 验证 strings 文件。

## 11. 测试接口

UI 测试支持：

| 环境变量 | 行为 |
|---|---|
| PERSONAL_PI_UI_TESTING=1 | 关闭外部进程并使用确定性测试状态 |
| PERSONAL_PI_DATA_ROOT=path | 将 ~/.pi 替换为临时目录 |
| PERSONAL_PI_DISABLE_EXTERNAL_PROCESSES=1 | 禁止 Pi、Node、Codex 子进程 |
| PERSONAL_PI_UV_EXECUTABLE=path | 覆盖 Scientific Figure 使用的 uv |
| PERSONAL_PI_FIGURE_ENVIRONMENT=path | 覆盖受管理的绘图 Python 环境 |

测试层次：

1. Swift unit：纯解析、设置合并、目录解析、任务身份。
2. Xcode unit：验证正式工程 target 与资源集成。
3. XCUITest：验证导航、本地化和主要交互入口。
4. Shell compatibility：验证真实安装版 Pi、RPC、Packages 和 Starter Pack。
   Scientific Figure 还必须运行 `scripts/check-scientific-figure.sh`，检查真实三格式产物和默认清理策略。
5. Manual GUI smoke：检查 Finder 启动、真实作用域切换、会话恢复和视觉布局。

## 12. 新功能接入模板

一个同时涉及 Agent 和 GUI 的新功能应按以下顺序接入：

1. **定义领域模型**：输入、运行状态、产物、错误和可恢复状态。
2. **选择 Pi 机制**：工作方法放 Skill；需要确定性动作的能力放 Extension/tool；长期事实放知识库。
3. **封装执行接口**：Pi RPC、Extension tool 或独立 bridge，不让 View 直接启动脚本。
4. **接入 AppState**：增加 Published 状态和明确 action，处理作用域切换与会话恢复。
5. **实现 View**：保持页面只负责展示和用户意图。
6. **持久化**：声明 Global/Project 路径、文件所有者和清理策略。
7. **验证**：unit、UI、真实 Pi smoke、产物级验证。
8. **更新文档**：README、本文档和 Pi compatibility record。

### 产物预览接口

DetailView 已实现全局可折叠产物栏：

~~~text
DetailView
├── Active page
└── Artifact sidebar (optional)
    ├── Preview
    ├── Metadata / validation state
    └── Export actions
~~~

Scientific Figure 通过 `FigureArtifactStore` 实现第一种 schema。后续 PDF、报告等类型应扩展为显式 artifact kind/schema，并复用全局容器；不要从聊天文本中猜测文件路径，也不要让每个页面自行维护一套右侧栏状态。任何新 schema 至少应包含稳定 ID、源文件、预览文件、MIME/UTType、支持导出格式、物理尺寸或页面信息、生成时间、所属 Project/Session 和验证结果。
