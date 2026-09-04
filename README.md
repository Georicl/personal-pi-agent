# Personal Pi Agent

Personal Pi 是一个以 [Pi Coding Agent](https://pi.dev/) 为运行时的原生 macOS 桌面客户端。它保留 Pi 的 Agent 循环、工具调用、会话树、上下文压缩、Skills、Extensions 与 Packages，同时提供项目切换、会话总览、任务状态、账户状态和图形化配置。

当前版本定位为 **GUI 基础能力完成 + 首个插件可用**：已经可以作为日常 Pi 桌面外壳，并能完成基于表格数据的出版级绘图；后续开发重点继续转向学术编辑、个人知识库与更多结构化产物。

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
| Knowledge | 知识目录入口 | 查看 Global/Project 知识文件数量并在 Finder 中打开目录；尚未实现检索数据库 |
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
└── knowledge/                     # Global Knowledge

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

## 开发与验证

工程包含 `PersonalPi`、`PersonalPiTests` 和 `PersonalPiUITests`。常用验证：

```bash
swift test
swift build -c release -Xswiftc -warnings-as-errors
xcodebuild test -project PersonalPi.xcodeproj -scheme PersonalPi -destination 'platform=macOS'
scripts/check-pi-compatibility.sh
scripts/check-session-rpc.sh
scripts/check-package-bridge.sh
scripts/check-starter-pack.sh
scripts/check-figure-plugin.sh
scripts/build-app.sh debug
```

环境覆盖项：

| 环境变量 | 作用 |
|---|---|
| `PERSONAL_PI_EXECUTABLE` | 指定 Pi CLI |
| `PERSONAL_PI_NODE_EXECUTABLE` | 指定 Node.js |
| `PERSONAL_PI_CODEX_EXECUTABLE` | 指定 Codex CLI |
| `PERSONAL_PI_UV_EXECUTABLE` | 指定 uv 可执行文件 |
| `PERSONAL_PI_FIGURE_ENVIRONMENT` | 覆盖受管理的绘图 Python 环境 |
| `PERSONAL_PI_DATA_ROOT` | 覆盖 `~/.pi`，主要用于测试 |
| `PERSONAL_PI_DISABLE_EXTERNAL_PROCESSES` | 禁止 Pi、Node、Codex 子进程，主要用于测试 |
| `PI_CODING_AGENT_SESSION_DIR` | 按 Pi 原生优先级覆盖会话目录 |

后续开发先阅读 [GUI 开发接口](docs/gui-interface.md)。其他设计与兼容性文档：

- [Personal Pi 配置协议](docs/configuration-contract.md)
- [Pi 兼容性记录](docs/pi-compatibility.md)
- [Packages 与资源管理](docs/package-management.md)
- [P4 Global Context 与核心 Skills](docs/p4-core-context-and-skills.md)
- [绘图插件](docs/figure-plugin.md)
