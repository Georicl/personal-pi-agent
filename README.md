# Personal Pi Agent

Personal Pi 是一个以 [Pi Coding Agent](https://pi.dev/) 为运行时的原生 macOS 桌面客户端。它保留 Pi 的 Agent 循环、工具调用、会话树、上下文压缩、Skills、Extensions 与 Packages，同时提供项目切换、会话总览、任务状态、账户状态和图形化配置。

当前版本提供 Pi 桌面外壳、表格数据绘图、Global/Project 本地知识库和文献检索 MVP。连接生命周期、任务完成判断、知识来源身份、检索入库和配置模块已有独立回归测试。

## 系统要求

- macOS 13 或更高版本。
- 已安装 Node.js、[uv](https://docs.astral.sh/uv/) 以及能够正常运行的 `pi` 命令；若在 Settings 指定自备的完整绘图 Python 环境，可不使用 uv。
- 使用源码构建时需要 Xcode。

安装当前兼容的 Pi CLI：

```bash
npm install -g --ignore-scripts @earendil-works/pi-coding-agent
pi --version
```

本仓库当前验证基线为 Pi `0.84.3`。升级 Pi 后应重新运行兼容性检查，详见 [Pi 兼容性记录](docs/pi-compatibility.md)。

## 构建与启动

使用 Xcode 打开工程：

```bash
open PersonalPi.xcodeproj
```

或直接构建并签名本地 App：

```bash
scripts/build-app.sh debug
open Build/PersonalPi.app
```

Release 构建：

```bash
scripts/build-app.sh release
```

应用会从当前 `PATH`、Homebrew、nvm、fnm、Volta、asdf、pnpm、Bun 等常见用户目录寻找 `pi`、`node` 和 `codex`，不会写死用户名或 Node 版本。

## 第一次使用

1. 启动 Personal Pi，确认左下角显示“Pi CLI ready / Pi CLI 已就绪”。
2. 在左上角作用域菜单中选择 **Global Chat**，或者创建、添加一个 Project。
3. 打开 **Settings → Model provider accounts**，选择 Pi `/login` 实际支持的供应商并完成登录。
4. 在 Settings 中选择默认模型和思考等级。
5. 回到 Overview 或 Sessions，输入消息开始会话。

需要绘图时，直接用自然语言描述图片目的与数据路径，或输入 `/figure <要求>`。Extension 会确定性启动绘图流程，不依赖 Skill 自动识别。Pi 会检查数据、生成并最多自动修订 5 版；新图片会自动出现在全局右侧预览栏。

Global Chat 的工作目录为 `~/.pi/chat`。Project 模式以所选项目根目录作为 Pi 的 `cwd`，并自动加载该项目允许的 `.pi` 配置与资源。

## 页面与主要操作

| 页面 | 用途 | 当前能力 |
|---|---|---|
| Overview | 当前作用域入口 | 新会话、发送消息、账户状态、当前会话用量、最近会话 |
| Sessions | 会话总览与对话 | 恢复、切换、筛选、停止、压缩、会话信息、树导航、Fork、Clone、HTML 导出、复制回复、资源重载 |
| Knowledge | 知识库总览 | Global/Project 切换、文件数与总大小、分类列表、文本搜索、文件详情、导入、更新/重建索引、发布已审阅草稿 |
| Literature | 文献检索 | Pi 拟定可编辑检索式、Europe PMC 查询、摘要与 DOI/PMID、去重、选择入库、总结草稿 |
| Packages | Pi 包与资源管理 | Global/Project 安装、移除、更新 Packages；启用或禁用 Extensions、Skills、Prompt Templates、Themes |
| Projects | 项目总览 | 创建或添加项目、查看 Git 分支、修改数量、会话数量并快速切换 |
| Tasks | 任务状态 | 按 Submitted、Running、Waiting、Finished 展示；同一 Pi Session 持续更新同一任务 |
| Diagnostics | 环境诊断 | 检查 Pi、Node、Codex、全局目录、项目配置和资源加载条件 |
| Settings | Pi 原生配置 | Global、Project、Effective 三种视图；模型、思考、压缩、重试、消息投递、图像、工具和高级运行环境设置 |

TopBar 右上角的预览按钮可在任意页面打开 Artifact Sidebar；侧栏左缘可以拖动并记住宽度。当前第一类产物为图片：支持版本预览、验证结果，以及按尺寸导出 PNG、TIFF 或矢量 PDF。会话工具栏中的“智能体活动”按钮用于随时显示或隐藏工具执行记录。

## Project 与 Global Chat

### Project

- 一个目录就是一个 Project。
- 左侧 Project 卡片显示当前 Git 分支、工作区修改数量和 Pi 会话数量。
- Pi 使用项目根目录启动，因此项目级 `AGENTS.md`、`.pi/settings.json`、Skills、Extensions、Prompts 和 Themes 会按 Pi 规则加载。
- 切换 Project 时，当前 Pi RPC 进程会重启；正在生成的任务会标记为被项目切换中断。
- 连接中的待发送消息留在原项目，不会跟随切换发送；切回后可从草稿重新发送。跨项目恢复会话会同步采用该会话的精确目录与知识库。

### Global Chat

- 不绑定任何项目，工作目录固定为当前用户的 `~/.pi/chat`。
- 适合普通问答和临时文件，不显示项目 Git 信息。
- 只提供 Global Settings、Global Packages 和 Global Knowledge。

## 会话与斜杠命令

会话由 Pi 以 JSONL 树保存。Personal Pi 默认扫描 `~/.pi/agent/sessions/`，同时读取 Global 和各 Project 实际生效的 `sessionDir`。相对 `sessionDir` 以对应 Pi 工作目录为基准解析，重复目录和重叠文件会去重。

在 Overview 或 Sessions 输入 `/` 可以打开命令面板。GUI 原生命令包括：

| 命令 | 作用 |
|---|---|
| `/settings` | 打开 Settings |
| `/new` | 新建会话 |
| `/resume [ID或路径]` | 打开 Sessions，或恢复指定会话 |
| `/session` | 查看会话名称、ID、路径和用量 |
| `/name <名称>` | 重命名当前会话 |
| `/compact [要求]` | 压缩上下文，可附加自定义总结要求 |
| `/tree` | 查看并切换当前会话树分支 |
| `/fork [条目ID]` | 从指定用户消息创建新会话分支 |
| `/clone` | 将当前活动分支克隆为新会话 |
| `/export [路径]` | 导出当前会话为 HTML |
| `/copy` | 复制最近一条助手回复 |
| `/model <provider/model>` | 切换模型；不带参数时打开 Settings |
| `/thinking <level>` | 切换思考等级 |
| `/login [provider]` | 打开 Pi 原生供应商登录流程 |
| `/logout [provider]` | 移除 Pi 保存的供应商凭据 |
| `/reload` | 重新加载 Extensions、Skills、Prompts 和 Themes |

Pi 返回的 Extension commands、Prompt Templates 和 `/skill:*` 命令也会合并到同一命令面板。以 `__personal_pi_` 开头的内部桥接命令不会显示给用户。

纯命令和通知不会新增聊天任务；命令真正启动模型后才显示任务。通知不要求确认，停止或取消也不会显示为正常完成。知识卡发布绑定已预览的具体内容版本；预览后修改正文或更新为不同索引版本，需要重新预览确认。

知识卡发布会保留可恢复原稿，成功后显示恢复路径；并发编辑冲突不会覆盖或删除新稿。恢复文件位于知识根目录的 `.publish-recovery/`，不参与检索、不自动清理。

## Settings

Settings 提供三个作用域：

- **Global**：写入 `~/.pi/agent/settings.json`。
- **Project**：写入 `<project>/.pi/settings.json`。
- **Effective**：只读显示 Global 与 Project 合并后的实际配置。

保存时 GUI 会重新读取最新文件，只更新自己管理的字段，并保留未知配置键。Advanced Runtime 当前支持：

- HTTP proxy、HTTP idle timeout、WebSocket connect timeout。
- Provider timeout、最大重试次数和最大重试延迟。
- `sessionDir`。
- `shellPath`、`shellCommandPrefix`、`npmCommand`。
- Branch summary reserve tokens、skip prompt。
- Anthropic extra-usage warning。
- Figure 插件的 Python 环境覆盖与工作文件保留策略。

模型供应商列表来自当前 Pi `/login`，不是 GUI 自建列表。OAuth 地址由 Pi 返回后交给 macOS 打开；API Key 仅作为临时安全输入传递给 Pi，Swift GUI 不读取 `auth.json`。

## Packages 与资源

Packages 页面直接调用安装版 Pi 的 `SettingsManager` 和 `DefaultPackageManager`：

- **Refresh**：只读取状态，不安装缺失包。
- **Install**：支持 Pi 接受的 npm、Git、URL 和本地路径来源。
- **Remove**：从实际所属作用域移除。
- **Update / Update all**：更新单包或当前作用域中的全部包。
- **Resource controls**：管理 Extensions、Skills、Prompt Templates 和 Themes 的启用状态及附加路径。

Project 资源支持 Inherit、Enabled、Disabled 三态，不建立第二套独立包注册表。

## Knowledge Core

Knowledge Core 提供 GUI 无关的基础能力：Global/Project 标准目录、Markdown/TXT/PDF 解析、SQLite FTS5、结构化知识卡校验、增量索引、删除检测、重建、跨作用域搜索和可定位结果。Markdown/PDF 等人类可读文件是事实来源，`~/.pi/personal/knowledge/` 下的 SQLite 仅为可重建索引。

内置 Knowledge Pi Package 已注册 `/knowledge`、检索与维护工具，并提供只在明确请求时运行的捕获/发布流程；不会把整个知识库注入每轮上下文。接口、路径和卡片格式见 [Knowledge Core](docs/knowledge-core.md)，Agent 工作流见 [Knowledge Plugin](docs/knowledge-plugin.md)。

左侧“知识库”入口下方还有当前 Project 与 Global 的容量摘要，点击即可进入对应知识库。页面展示文件总数、总大小、知识卡与草稿数量，以及来源、知识卡、草稿、收件箱、附件、旧版条目、其他文件的分类。容量为实际文件字节数，包含附件和未分类文件，不包含隐藏文件、符号链接或外部 SQLite 索引。

使用“导入文件…”选择 Markdown、TXT 或文本型 PDF，会复制到所选知识库的 `sources/` 并建立索引；原文件保持原样，重名文件会报告冲突。“搜索”查询所选范围的已索引来源资料和已审阅卡片，显示章节或 PDF 页码。点击文件可查看文本详情、打开原文件或在 Finder 中定位；文件修改后会提示更新索引。草稿详情中的“发布已审阅知识卡”保留稳定 ID，将已确认的草稿移入 `cards/`。

侧边栏统计在后台读取文件系统；打开知识库页面后，GUI 通过同一个 Knowledge Core 获取索引信息，不需要发送聊天消息或消耗模型额度。首次使用会通过 `uv` 准备锁定的 Python 依赖环境。扫描型 PDF 暂不支持 OCR；列表显示前 5,000 个文件，统计包含全部文件，文本详情最多预览 50 个片段。

~~~bash
scripts/check-knowledge-core.sh
scripts/check-knowledge-plugin.sh
~~~

## 数据与隐私边界

```text
~/.pi/
├── agent/                         # Pi 原生状态
│   ├── auth.json                  # 凭据，GUI 不读取
│   ├── settings.json              # Global Settings
│   ├── sessions/                  # 默认会话目录
│   ├── personal-pi-tasks.json     # GUI 任务状态
│   ├── personal-pi-figure-artifacts.json # GUI 图片产物索引
│   ├── environments/figure/              # uv 锁定绘图环境
│   ├── skills/
│   ├── prompts/
│   ├── extensions/
│   └── themes/
├── chat/                          # Global Chat 临时工作目录
├── knowledge/                     # Global Knowledge 源文件和知识卡
└── personal/knowledge/            # 可重建的本地知识索引

<project>/
├── AGENTS.md
└── .pi/
    ├── settings.json
    ├── skills/
    ├── prompts/
    ├── extensions/
    ├── themes/
    ├── knowledge/
    └── artifacts/figures/          # Project 图片
```

- GUI 不读取或展示 API Key、OAuth Token。
- 个人运行目录 `.pi/` 已被仓库忽略，不应整体提交到公开仓库。
- Pi Extensions 与 Packages 使用当前用户权限运行，只应安装可信来源。
- Personal Pi 按用户要求不再增加一层工具执行许可系统。

## 当前边界

GUI 已完成 Pi 的核心使用闭环，但不宣称与全部 Pi CLI/TUI/RPC 功能 100% 对等。当前尚未直接提供：

- Steering 和 follow-up 队列及 `queue_update` 展示。
- 独立 `bash` / `abort_bash` 控制台。
- `get_entries` 原始会话条目接口。
- `pi update --self`。
- 完整 Extension widget/status/title/editor UI。

这些差异不会阻止普通 Agent 对话、工具调用、会话管理、配置和包管理。

## 文献检索

文献流程：选择目标 Project → **Literature / 文献检索** → 输入研究问题 → “让 Pi 拟定检索条件”。
该操作使用当前会话与模型，计划自动回到文献页。也可直接手动输入英文检索式，无需模型调用。
检查关键词、年份、结果数量与完整的对外检索式后，再“检索文献”。只发送检索条件，不上传本地知识。
展开摘要与来源，勾选所需文献，再“将所选文献存入知识库”：Project 写入该项目 `sources/`，
Global Chat 写入全局 `sources/`；重复保存复用来源 ID，不覆盖原稿。

“让 Pi 总结已保存的文献”读取本地来源并写入 `drafts/`，区分事实、总结与推断。成为已审阅知识卡
仍须在 Knowledge 中预览、确认并发布。每次检索保留检索式、UTC 时间、来源服务、记录 ID 和项目。
快照存于动态 Pi 根目录的 `personal/literature/`；切换项目清空页面旧状态，不删除快照或来源。
已提交的保存仅在原项目完成。

MVP 使用 Europe PMC（包含 PubMed 记录），每次最多取 50 条，显示总命中数和去重条数；不是系统综述
的穷尽性检索。不自动下载全文，不补猜摘要或 DOI；总结的证据范围仅为书目信息与摘要。
网络错误明确显示，可自行重试。Pi CLI 可使用 `/literature <研究问题>` 和 `literature_plan/search/save/draft`。
插件依赖同发行包的 Knowledge，不能单独复制 Literature 目录使用。协议见 [Literature 插件接口](docs/literature-plugin.md)。

## 开发与验证

工程包含 `PersonalPi`、`PersonalPiTests` 和 `PersonalPiUITests`。常用验证：

```bash
swift test
PERSONAL_PI_TEST_KNOWLEDGE_RUNTIME=1 swift test --parallel
swift build -c release -Xswiftc -warnings-as-errors
xcodebuild test -project PersonalPi.xcodeproj -scheme PersonalPi -destination 'platform=macOS'
scripts/check-pi-compatibility.sh
scripts/check-session-rpc.sh
scripts/check-package-bridge.sh
scripts/check-starter-pack.sh
scripts/check-figure-plugin.sh
scripts/check-knowledge-plugin.sh
scripts/check-literature-plugin.sh
scripts/build-app.sh debug
```

环境覆盖项：

PR 和 main 推送会运行 `.github/workflows/checks.yml`：Swift 单元及本地 Python 集成测试、
严格 Release 构建、Xcode 构建、Knowledge/Figure/Literature 包检查。Pi 包检查使用固定版本的离线运行时，
不需要模型 API 凭证。交互式 XCUITest 仍需本机允许系统 UI 自动化。

| 环境变量 | 作用 |
|---|---|
| `PERSONAL_PI_DATA_ROOT` | 覆盖 `.pi` 数据根，默认用户目录下的 `.pi` |
| `PI_CODING_AGENT_DIR` | Pi 原生认证与设置目录；未指定时为 `<数据根>/agent` |
| `PERSONAL_PI_KNOWLEDGE_ENVIRONMENT` | 覆盖知识库的受管理 Python 环境 |
| `PERSONAL_PI_EXECUTABLE` | 指定 Pi CLI |
| `PERSONAL_PI_NODE_EXECUTABLE` | 指定 Node.js |
| `PERSONAL_PI_CODEX_EXECUTABLE` | 指定 Codex CLI |
| `PERSONAL_PI_UV_EXECUTABLE` | 指定 uv 可执行文件 |
| `PERSONAL_PI_FIGURE_ENVIRONMENT` | 覆盖受管理的绘图 Python 环境 |
| `PERSONAL_PI_DISABLE_EXTERNAL_PROCESSES` | 禁止 Pi、Node、Codex 子进程，主要用于测试 |
| `PI_CODING_AGENT_SESSION_DIR` | 按 Pi 原生优先级覆盖会话目录 |

后续开发先阅读 [GUI 开发接口](docs/gui-interface.md)。其他设计与兼容性文档：

- [Personal Pi 配置协议](docs/configuration-contract.md)
- [Pi 兼容性记录](docs/pi-compatibility.md)
- [Packages 与资源管理](docs/package-management.md)
- [P4 Global Context 与核心 Skills](docs/p4-core-context-and-skills.md)
- [绘图插件](docs/figure-plugin.md)
