# AWESOM SDK v0.7.1 — Trae Agent Rules

## 项目描述
AWESOM SDK 开发包 — FPGA 开发工具、IDE 扩展和项目脚手架，支持 Efinity Titanium 系列。

## v0.7.0 新增功能
- 四层架构模型（L1 厂商工具 → L2 适配层 → L3 编排层 → L4 智能层）
- Workbench 6-Tab 统一工作台（Home/Build/Timing/Debug/Software/IP）
- BuildStrategyAdvisor：8 类编译策略建议 + Apply & Rebuild 一键重编译
- DataPathTracer：关键路径 hop 重分类 + 延迟分解 + Mermaid 拓扑图
- PipelineDepthAnalyzer：三阶段冗余寄存器分析（可行性→依赖→等效性）
- ProjectHealthChecker：编译前全面健康评估
- AI 错误诊断引擎（ErrorFingerprints）：自动匹配已知错误模式
- NL-to-RTL Generator：8 个模板的自然语言 RTL 代码生成
- MultiChipProject：多芯片系统建模（FPGA+SoC / 双 FPGA / FPGA+MCU）
- RISC-V 软件开发全流程（SoC 创建 / App 构建 / BSP 生成 / GDB 调试）
- Efinity IP Configuration Wizard 集成：复杂 IP（RISC-V Sapphire SoC 等）可通过 Efinity 原生多 Tab GUI 配置，配置后一键 Sync 回工程

## 技术栈
- TypeScript/JavaScript (VS Code 扩展)
- Python (MCP 服务器、CLI 工具)
- Verilog/SystemVerilog (FPGA RTL)
- Efinity 2025.2+ (FPGA 工具链)
- Icarus Verilog (仿真)

## 项目结构
```
awesomsdk/
├── README.md                     # 版本说明
├── .trae/rules.md                # 通用 Agent 工作流与项目规则
├── .trae/rules-rtl-style.md      # RTL、CDC、复位与 Efinity 格式规范
├── awesom-sdk-scaffold-v5/       # SDK 脚手架 v5
│   ├── catalog/                  # 板卡/底座/夹克/IP 清单 + RTL
│   │   ├── boards/
│   │   │   └── tj180-core/       # TJ180A484S 核心板
│   │   │       └── ecosystem/
│   │   │           ├── carriers/ awesom-base/
│   │   │           ├── jackets/  golden-top / sensor-fusion / sim-demo
│   │   │           └── demos/
│   │   └── ips/
│   │       ├── awesom-dma/
│   │       └── mipi-rx/
│   ├── extension/                # VS Code 扩展
│   │   ├── src/                  # TypeScript 源码
│   │   │   ├── extension.ts      # 主入口（命令注册、Webview Provider、MCP bootstrap）
│   │   │   ├── webview/          # Webview 基础设施（loader / panelRegistry）
│   │   │   └── toolchain/        # Efinity CLI 集成
│   │   │       ├── buildRunner.ts       # efx_map/pnr/pgm 执行、XML sanitization
│   │   │       ├── reportParser.ts      # map/P&R/timing 报告解析 → ResourceMap / TimingSummary
│   │   │       ├── timingAnalyzer.ts    # 时钟域、WNS/TNS、关键路径提取
│   │   │       ├── timingDiagnoser.ts   # 12 条规则的确定性诊断引擎
│   │   │       ├── codeLocator.ts       # timing report hop → RTL 源文件 + 行号
│   │   │       ├── copilotContext.ts    # LLM 上下文构建（RTL + SDC + 诊断结果）
│   │   │       ├── programmerRunner.ts  # Efinity Programmer 调用
│   │   │       ├── dataPathTracer.ts    # 数据路径 hop 重分类 + 延迟分解
│   │   │       ├── pipelineDepthAnalyzer.ts # 冗余寄存器分析
│   │   │       ├── buildStrategyAdvisor.ts  # 8 类编译策略建议
│   │   │       ├── aiDiagnoser.ts       # LLM 错误诊断
│   │   │       ├── errorFingerprints.ts # 错误指纹库
│   │   │       ├── riscvToolchain.ts    # RISC-V GCC 工具链管理
│   │   │       ├── softwareRunner.ts    # SoC 软件构建/烧录/调试
│   │   │       ├── codeStyleChecker.ts  # RTL 代码风格检查（25 条规则）
│   │   │       ├── efinixAdapter.ts     # L2: Efinix VendorAdapter 实现
│   │   │       ├── vendorAdapter.ts     # L2: 厂商适配器抽象接口
│   │   │       ├── types.ts             # 共享类型定义
│   │   │       └── ...
│   │   └── media/                # Webview HTML
│   │       ├── workbench.html    # 6-Tab 工作台（Home/Build/Timing/Debug/Software/IP）
│   │       ├── build-report.html # 6-Tab 报告（概览/资源/IO与时钟/时序/关键路径/优化/Tcl）
│   │       ├── timing-diagnose.html  # 规则引擎 + AI Chat + Mermaid
│   │       ├── welcome.html      # 主页（板卡画廊 + 操作入口）
│   │       ├── wizard-project.html / wizard-board.html
│   │       └── debug-console.html / board-designer.html
│   ├── cli/                      # 命令行工具 (Python)
│   │   ├── awesom               # 主 CLI 入口
│   │   ├── ipm_runner.py         # Efinity IP Manager 调用封装
│   │   ├── rtl_dep.py            # RTL 依赖分析
│   │   └── rtl_templates.py      # NL-to-RTL 模板
│   ├── mcp-server/               # MCP 服务器
│   │   └── server.py            # 暴露 ~15 个工具（list / ip / project / validate 等）
│   ├── docs/                     # 文档
│   │   ├── 用户使用手册.md       # 21 章用户使用手册
│   │   ├── AWESOM-SDK-完整设计说明书.md
│   │   └── ...
│   └── scripts/
│       ├── build-vsix.ps1        # 打包 VSIX
│       └── build-vsix.sh
├── release/                      # 发布产物
│   └── v0.7.0/
│       ├── awesom-sdk-0.7.0.vsix
│       ├── docs/
│       └── tutorials/
└── .trae/rules.md               # 本文件
```

## 核心架构

### 四层模型
```
L1: Vendor Tools       → Efinity / Icarus Verilog / xPack RISC-V GCC
L2: Vendor Adapter     → EfinixAdapter（实现 VendorAdapter 接口）
L3: System Orchestration → BuildRunner / TimingAnalyzer / CodeStyleChecker / HealthChecker
L4: AI Intelligence    → AI 诊断引擎 / Copilot 上下文 / NL→RTL 生成器
```

### 编译管线 (Build Pipeline)
1. 用户点击 Build 或执行 `awesom.build`
2. `extension.ts` → `buildRunner.ts` 的 `runBuildFlow()`
3. 查找 XML → sanitize → 依次执行 efx_map / efx_pnr / efx_pgm
4. 成功后 `parseAndSummarize()` 解析所有报告 → 结构化数据
5. `adaptSummaryForWebview()` 序列化 → postMessage 到 `build-report.html`
6. 状态栏更新（ready / running / failed）

### 时序诊断管线 (Timing Diagnosis Pipeline)
1. 用户执行 `awesom.diagnoseTiming`
2. 找到 timing report → 运行 `diagnoseTimingIssues()`
3. 12 条规则引擎逐条评估每个违反端点 → 生成诊断对象（含置信度）
4. 打开 `timing-diagnose.html` Webview 面板
5. 用户可点击 "Ask AI" 发送完整上下文（RTL + SDC + path analysis）给 LLM
6. 追问聊天面板支持持续对话，自动注入上下文

### IP 配置策略
- **简单 IP**（FIFO、GPIO 等）：在 VS Code 内用 Config 按钮编辑 `settings.json`
- **复杂 IP**（RISC-V Sapphire SoC、DDR 控制器等）：通过橙色 **Efinity** 按钮打开 Efinity 原生 IP Configuration Wizard（多 Tab GUI），配置完成后用 **Sync from Efinity** 同步回工程
- IP 相关命令：`awesom.openInEfinityIpManager`、`awesom.syncIpFromEfinity`

## 开发注意事项
- SDK 遵循 core-board-centric 设计理念
- 项目创建使用 `awesom.newProject` 命令
- 编辑 regmap.md 后需要调用 regenerate_bsp
- 验证清单使用 validate_manifest 命令
- Mermaid 图表优先于 ASCII art
- 所有 Efinity 交互通过 `EfinixAdapter` → `BuildRunner` / `TimingAnalyzer` / `ProgrammerRunner` 调用链完成
- L3/L4 层代码面向 `VendorAdapter` 抽象接口编程，不直接依赖 Efinity 特化代码
- 编译前自动检查 SDC 文件是否存在，路径自动转为绝对路径

## Build, analysis, and diagnosis
- **Build mode**: `awesom.buildMode` 可设为 `cli` (推荐) 或 `gui`
- **Build Report**: `awesom.openReport` 打开 6-tab 报告面板（Overview / Resources / I/O & Clock / Timing / Critical Paths / Optimization / Tcl）
- **Timing Diagnosis**: `awesom.diagnoseTiming` 打开诊断面板（规则引擎 + AI Chat + Mermaid）
- **Mermaid**: 关键路径 hop 以 `graph LR` 流程图展示

---

## Release Pre-Check Protocol ⚠️

**当用户说 "release" / "发布版本" / "打版本包" / "打包" 时，必须先执行完整文档审计。**

### 触发关键词
- "release" / "发布版本" / "打版本包"
- "v0.x.0" / 版本号变更请求

### 强制检查清单（按顺序执行）

#### Phase 1: 核心设计文档（9 个文件）
| # | 文档 | 路径 | 检查项 |
|---|------|------|--------|
| 1 | AWESOM-SDK-完整设计说明书.md | `docs/` | 版本号、日期、交叉引用 |
| 2 | SDK-ARCHITECTURE-VISION.md | `docs/` | 版本、日期、架构状态 |
| 3 | UI-CONSOLIDATION-DESIGN.md | `docs/` | 实现状态更新 |
| 4 | efinity-toolchain-reference.md | `docs/` | 工具链版本对齐 |
| 5 | efinity-coding-style.md | `docs/` | 代码风格规则时效性 |
| 6 | efinity-optimization-design.md | `docs/` | 3 个优化方向的实现状态 |
| 7 | timing-analysis-guide.md | `docs/` | STA 命令准确性 |
| 8 | 用户使用手册.md | `docs/` | 功能覆盖完整性 |
| 9 | DEPLOYMENT.md | `docs/` | 安装步骤有效性 |

#### Phase 2: 教程文档（~22 个文件）
| 类别 | 需审计文件 |
|------|-----------|
| TA Series（入门） | TA01-快速上手.md |
| TB Series（基础） | TB01-TB03（RTL 编码/仿真/风格检查） |
| TC Series（编译） | TC01-TC02（编译报告/烧录调试） |
| TD Series（时序） | TD01-TD04（诊断/优化/RTL 修改/数据路径） |
| TE Series（扩展） | TE00-TE02（硬件搭建/RISC-V/Catalog） |
| TF Series（工具链） | TF01-TF02（CLI/MCP-Agent） |
| TG-TV Series（进阶） | TG01、TV01（参考设计/Vibe-Coding） |
| Snapshots（快照） | 所有 `snapshots/*/README.md` + `awesom-project.md` |
| Meta Docs | TUTORIAL-DESIGN.md、TUTORIAL-TOOL-AUDIT.md |

#### Phase 3: 硬件规格文档（12 个文件）
| 类别 | 需审计文件 |
|------|-----------|
| 板卡规格 | 核心板规格.md、底板规格.md、datasheet.md |
| IP 核 | awesom-dma/*、mipi-rx/*（awesom.md + regmap.md） |
| 生态 | Golden-Top-Design-Spec.md、Sensor-Fusion-Design-Spec.md |

#### Phase 4: 跨文档校验
- [ ] **版本一致性**: 所有文档显示相同的目标版本号
- [ ] **日期一致性**: 全部更新到当前发布日期
- [ ] **引用完整性**: 所有文档间链接正确解析
- [ ] **内容对齐**: 无过期信息（如 "coming soon" 指向已发布功能）
- [ ] **代码↔文档同步**: 文档内容与实际实现状态匹配

#### Phase 5: 输出
生成 **Release Notes Summary**，包含：
1. ✅ 已更新的文档（含版本变更）
2. 📝 内容修改摘要
3. ⚠️ 发现的问题（如有）
4. 🔗 更新的文档索引/目录

### 执行规则
1. **绝不跳过此检查** — release 请求时必须执行
2. **更新所有文档** — 即使内容未变，至少更新版本号 + 日期
3. **报告发现** — 在发布操作前先输出审计结果
4. **请求确认** — 审计完成后、打 tag/发布前等待用户确认

---
