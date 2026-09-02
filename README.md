# Personal Pi Agent

这是个人深度定制 Pi Agent 的开发工作区。

## 当前目标

以 Pi Agent Runtime 为基础，逐步构建一个服务于个人编程、资料阅读、学术研究、知识库维护、计划执行和浏览器操作的个人工作系统。

## 设计原则

- 复用 Pi 的 Agent Runtime、工具调用、会话、分支和上下文压缩能力。
- 用 Skills 描述工作方法，用 Extensions 提供工具和动作，用本地数据库维护长期知识与任务状态。
- 知识库不直接全部注入上下文，而是通过检索、来源和引用按需提供给 Agent。
- 不额外构建文件或命令操作权限层；需要用户输入的业务步骤由任务状态标记为 Waiting。
- 先完成可验证的最小闭环，再逐步增加外部服务和复杂自动化。

## 当前作用域

- Project：一个目录就是一个项目，包含 Git 状态、项目会话、`AGENTS.md`、`.pi` 配置和项目知识库。
- Global Chat：不绑定项目，工作目录为 `~/.pi/chat`，只提供普通对话和临时文件空间。
- Global Knowledge：`~/.pi/knowledge`。
- Project Knowledge：`<project>/.pi/knowledge`。
- Task State：`~/.pi/agent/personal-pi-tasks.json`，记录 Submitted、Running、Waiting、Finished 和未读完成状态。
- Settings：在 GUI 中分别编辑全局 `~/.pi/agent/settings.json` 和项目 `.pi/settings.json`，查看合并后的 Effective 配置，并管理模型、压缩、重试、消息投递、传输、图像、工具与资源选项。
- Slash Commands：Overview 和 Session 共用命令输入组件；输入 `/` 可发现并滚动浏览 GUI 命令、Pi Extensions、Prompt Templates 和 Skills 命令。
- Account Status：provider readiness 通过 Pi 的无凭据 `auth check` 读取；Codex 限额通过本机 Codex App Server 的 `account/rateLimits/read` 读取真实窗口。Swift 不读取 API key 或 OAuth token。

## 计划中的层次

```text
Personal Knowledge Base
        ↓
Workflow and Task Layer
        ↓
Pi Agent Runtime
        ↓
Web/Desktop Interface
```

## 起步顺序

1. 配置全局和项目级上下文、Skills、Prompt Templates。
2. 建立项目注册表、知识检索和任务状态模型。
3. 实现代码、资料阅读、研究和报告工作流。
4. 接入网络搜索、浏览器、Obsidian、Zotero 等外部能力。
5. 构建个人网页工作台。

## 开发与兼容性

使用 Xcode 打开正式的 macOS App 工程：

```bash
open PersonalPi.xcodeproj
```

工程包含 `PersonalPi`、`PersonalPiTests` 和 `PersonalPiUITests` 三个 target。GUI 可在 Settings 的 Interface language 中选择跟随系统、English 或简体中文。

构建并签名本地 macOS App（产物位于 `Build/PersonalPi.app`）：

```bash
scripts/build-app.sh debug
```

运行 Swift Package 与 Xcode 测试：

```bash
swift test
xcodebuild -project PersonalPi.xcodeproj -scheme PersonalPi -destination 'platform=macOS' test
```

应用会从当前 `PATH` 和常见用户级安装目录发现 `pi`、`node` 与 `codex`。如需覆盖 Codex CLI 路径，可设置 `PERSONAL_PI_CODEX_EXECUTABLE`。

运行本机 Pi/RPC 兼容性检查：

```bash
scripts/check-pi-compatibility.sh
```

验证公开 Starter Pack 的四个 Pi Skills：

```bash
scripts/check-starter-pack.sh
```

- [Pi 兼容性记录](docs/pi-compatibility.md)
- [Personal Pi 配置协议](docs/configuration-contract.md)
- [P4 全局上下文与核心 Skills](docs/p4-core-context-and-skills.md)
