# 绘图插件

绘图是 Personal Pi 的第一个正式 Pi Package 插件。它不是固定图表模板，而是一条由 Extension 确定性启动、由 Pi 在一次用户请求中自动完成的通用流程：理解问题、检查数据、选择绘图方法、生成、确定性验证、必要时修订，并把每一版图片送到 GUI 右侧预览。

## 1. 能力边界

当前支持：

- CSV、TSV、TAB、文本表格。
- XLS、XLSX、XLSM、XLSB、ODS。
- Parquet、Feather、JSON、JSONL、pandas Pickle。
- NumPy NPY、NPZ。
- Matplotlib、Seaborn、Plotnine 及基于 Matplotlib Figure 的组合图。
- 常规散点、折线、柱状、箱线、小提琴、直方、密度、热图，以及 Volcano、MA、PCA/UMAP 坐标、富集气泡、森林、生存等生物学常见图。

第一版明确不加载 AnnData/Scanpy，也不承担单细胞或空间组学对象的数据分析语义。NPZ 可包含多个数组；工具会将其作为映射返回，绘图代码必须明确选择数组。

pandas Pickle 属于可执行序列化，只应读取用户确认可信的本地来源；NumPy 输入固定使用 `allow_pickle=False`。

## 2. 一次请求内的流程

~~~text
GUI“绘图”按钮或 /figure <要求>
        │
        ▼
Figure Extension command
        │ 建立可持久化请求并显式启动 Agent
        ▼
figure_inspect_data
        │ 形状、列、类型、缺失、范围、小样本
        ▼
统计检验？ ── 是 ──► 说明方法并等待用户确认
        │ 否/已确认
        ▼
figure_render
        │ Python 生成 PNG/TIFF/PDF + 确定性检查
        ├── 通过 + 视觉无缺陷 ──► 完成
        └── 未通过 ──► 同一 figureId 下一版（最多 5 次）
                              │
                              ▼
                     GUI Artifact Sidebar
~~~

`/figure` 由 Extension 注册，因此不依赖模型是否自动识别 Skill。Extension 会向当前 Pi 会话发送明确的绘图任务上下文；`figure` Skill 仍用于自然语言触发和补充图形选择、排版与复核方法。

Pi 会在一次会话轮次中自行调用多次工具，不需要用户逐版下达命令。每次修订必须复用 `figureId`；GUI 因此把它们显示为同一图片的版本，而不是互不相关的文件。

当前模型的输入能力包含 image 时，工具把 PNG 预览返回给模型用于视觉复核；不支持图像输入时，仍执行全部确定性检查，但 Pi 不得声称完成了模型视觉审查。

## 3. 出版参数

| 参数 | 默认值 | 上限或规则 |
|---|---:|---|
| 宽度 | 210 mm | 不超过 A4 宽度 210 mm |
| 高度 | 74.25 mm | 不超过半页 A4 高度 148.5 mm |
| PNG/TIFF DPI | 300 | 72–1200 |
| PDF | 矢量页 | DPI 不适用；其中的栅格元素仍受源数据影响 |
| 自动修订 | 最多 5 版 | 第 5 版仍失败时停止并交给用户决定 |

Python 代码应在创建 Figure 时立即使用目标尺寸：

~~~python
fig, ax = plt.subplots(figsize=(width_mm / 25.4, height_mm / 25.4))
~~~

运行器验证栅格像素、TIFF 可读性、空白图、文本裁切和小于 6 pt 的文字。科学含义、样本单位、分组、坐标、误差定义、颜色与统计标记仍由 Pi 按 Skill 清单审查。

## 4. 统计确认契约

任何推断统计都必须先确认，包括显著性标记、组间检验、带 p 值的相关、拟合模型、由模型产生的区间和生存比较。Pi 必须先说明：

- 候选方法与选择理由；
- 独立样本单位、组别和假设；
- 多重比较校正；
- 将如何标注在图片上。

用户确认后，Extension 才接受 `statisticalAnalysis.method` 并通过 Pi 原生 `ctx.ui.confirm` 再形成可审计的交互。仅做描述性汇总或绘制输入中已经存在的统计结果时，不应伪装成重新执行检验。

## 5. Pi Package 与 GUI 插件清单

打包目录 `Resources/PiPackages/Figure/` 本身是一个标准 Pi Package：

| 文件 | 职责 |
|---|---|
| `package.json` | Pi Package manifest，声明 Extensions 与 Skills |
| `personal-pi-plugin.json` | GUI 发现清单：按钮、命令、设置命名空间和 artifact renderer |
| `extensions/index.js` | `/figure`、Pi tools、确认交互、文档检索和 artifact details |
| `skills/figure/SKILL.md` | 图形选择、统计边界、循环和完成条件 |
| `skills/figure/references/` | 包路由、图形配方、质量清单 |
| `runtime/runner.py` | 数据读取、受控命名空间、导出和确定性验证 |
| `runtime/pyproject.toml` / `runtime/uv.lock` | 可复现 Python 依赖环境 |

`PersonalPiPluginRegistry` 扫描 App bundle 或源码目录中的 `PiPackages`，读取插件清单。Pi 启动只需附加 Package 根目录：

~~~text
--extension <PiPackages>/Figure
~~~

Pi 会按照 `package.json` 同时加载 Extension 和 `figure` Skill。用户首选 GUI 的“绘图”按钮或 `/figure <要求>`；也可以自然语言提出绘图要求或显式调用 `/skill:figure`。

## 6. Extension tools

| Tool | 输入重点 | 结果 details |
|---|---|---|
| `figure_capabilities` | 无 | `personalPiFigureCapabilities` |
| `figure_inspect_data` | `dataPath` | `personalPiFigureInspection` |
| `figure_library_docs` | `library`, optional `topic` | 官方 URL、来源类型 |
| `figure_render` | `title`, `code`, paths, figure/version, dimensions, DPI, optional confirmed statistics | `personalPiFigureArtifact` |

文档检索只访问 Skill 参考表中列明的官方文档源；网络不可用时返回打包参考，不虚构 API。

## 7. Artifact manifest

`figure_render` 在 `tool_execution_end.result.details.personalPiFigureArtifact` 返回：

~~~json
{
  "schemaVersion": 1,
  "kind": "figure",
  "id": "figure-id-v001-pathhash",
  "figureId": "figure-id",
  "version": 1,
  "title": "Figure title",
  "sessionId": "pi-session-id",
  "cwd": "/absolute/project/path",
  "createdAt": "ISO-8601",
  "previewPath": "/absolute/path/figure.png",
  "files": [
    {"format": "png", "path": "/absolute/path/figure.png"},
    {"format": "tiff", "path": "/absolute/path/figure.tiff"},
    {"format": "pdf", "path": "/absolute/path/figure.pdf"}
  ],
  "widthMm": 210,
  "heightMm": 74.25,
  "dpi": 300,
  "validation": {
    "passed": true,
    "score": 100,
    "errors": [],
    "warnings": [],
    "checks": []
  },
  "intermediatesRetained": false
}
~~~

Swift 解析层只接受这一结构化字段，不从助手文本提取路径。`id` 由产物绝对路径稳定派生以避免跨项目冲突；`FigureArtifactStore` 用 `id` 去重，并按 `figureId + Session + CWD` 聚合版本和恢复最近图片。迁移前的 `scientific-figure` artifact 仍可读取，新产物统一写为 `figure`。

## 8. 文件位置与清理

Project：

~~~text
<project>/.pi/artifacts/figures/<figureId>/v001/
├── figure.png
├── figure.tiff
└── figure.pdf
~~~

Global Chat 使用 `~/.pi/chat/.pi/artifacts/figures/`。GUI 为了跨页面和重启恢复，只保存一份最小索引：

~~~text
~/.pi/agent/personal-pi-figure-artifacts.json
~~~

默认版本目录只有图片。`source.py`、`request.json`、`validation.json` 和 `runtime.log` 在成功或失败后都会清理；只有用户明确要求，或 Settings 中明确启用 `figure.keepWorkFiles`，才保留这些工作文件。

## 9. GUI 交互

- TopBar 右上角的图片按钮在所有页面可见。
- 每次 render 返回新 manifest 后侧栏自动展开并显示当前版本。
- 版本选择器展示同一 `figureId` 的历史版本。
- 验证卡展示 passed/needs revision、分数、错误与警告。
- Export 面板只列出 manifest 中实际存在的格式。
- PDF 隐藏 DPI 输入；PNG/TIFF 默认 300 DPI。
- 导出时允许重新指定物理尺寸，但仍强制 210 × 148.5 mm 上限。

导出优先从 PDF 矢量源重新栅格化 PNG/TIFF，以减少二次缩放损失；PDF 导出保持矢量内容并设置目标页尺寸。

## 10. 配置

Settings → Advanced runtime → Figures 管理两个非 Pi 原生、由本 Extension 读取的嵌套键：

~~~json
{
  "figure": {
    "pythonPath": "/optional/custom/python",
    "keepWorkFiles": false
  }
}
~~~

`pythonPath` 为空时，Personal Pi 使用 uv 在 `~/.pi/agent/environments/figure/` 创建受 `uv.lock` 约束的环境。Project 设置可以覆盖 Global。自定义 Python 必须自行提供锁文件中的依赖。旧的 `scientificFigure` 字段仍作为只读回退；Settings 下一次保存对应字段时会迁移为 `figure`，并保留旧对象中的未知字段。

可用于测试或高级部署的环境变量：

- `PERSONAL_PI_UV_EXECUTABLE`：覆盖 uv 可执行文件。
- `PERSONAL_PI_FIGURE_ENVIRONMENT`：覆盖受管理环境目录。

## 11. 验证

~~~bash
scripts/check-figure-plugin.sh
swift test
xcodebuild test -project PersonalPi.xcodeproj -scheme PersonalPi -destination 'platform=macOS'
~~~

专用检查验证 Package/GUI manifest，在临时 uv 环境中读取 CSV，生成三格式文件，核对 300 DPI 与物理尺寸、默认清理策略，并启动真实 Pi RPC 验证 `/figure`、Extension marker 与 `/skill:figure`。
