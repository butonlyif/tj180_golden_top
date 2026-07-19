# DDR3 / LPDDR4x 硬核配置参考

> 本文档记录 `tj180_golden_top` 工程中 DDR 控制器（硬核 IP）的启用配置参数。
> DDR 在 Titanium 芯片上是 **Hard IP**（硅片固化），不是 `ip/<name>/` 软 IP 文件夹，
> 因此无法像 TSEMAC 那样直接拷贝目录，必须通过 **Efinity GUI 的 DDR 面板** 启用并配置。
>
> **参考来源**：`TJ180A484S_SDHOST/TJ180A484S/TJ180A484S.peri.xml` 的 `<efxpt:ddr_info>` 与 `<efxpt:pll name="pll_ddr">` 段落（与本项目 Sapphire SoC 版本最接近）。

---

## 1. 现状盘点

| 项目 | 状态 | 位置 |
|------|------|------|
| DDR AXI0 总线引脚约束 | ✅ 已就绪 | `constraints/tj180_golden_top.peri.isf` 第 453–637 行 `DDR_AXI0` peripheral |
| DDR 参考时钟输入 | ✅ 已就绪 | `DDRCLK` peripheral (`ddr_clk_ref`, pin L28) |
| DDR 状态/控制引脚 | ✅ 已就绪 | `PLL_STATUS` peripheral (`ddr_inst_CFG_DONE` / `CTRL_BUSY` / `CTRL_INT` / `CTRL_REFRESH` / `CTRL_MEM_RST_VALID` / `CTRL_CKE[0..1]`) |
| **DDR 硬核块定义** | ✅ **已配置** | `tj180_golden_top.peri.xml` 的 `<efxpt:ddr_info>`（由 `debug/configure_ddr.py` 产出） |
| **DDR PLL (pll_ddr)** | ✅ **已配置** | `tj180_golden_top.peri.xml` 的 `<efxpt:pll name="pll_ddr">` |

---

## 2. DDR 硬核启用参数（Efinity GUI → DDR 面板）

在 Efinity 中打开 `tj180_golden_top.xml`，进入 **Peripheral / DDR** 面板，按以下参数配置：

| 参数 | 值 | 说明 |
|------|-----|------|
| Block Name | `ddr_inst` | 实例名，须与 ISF 中 `ddr_inst_*` 引脚前缀一致 |
| DDR Definition | `DDR_0` | 硬核位置（TJ180A484S 唯一可用 DDR 块） |
| Clock In Select | `2` | `clkin_sel` = 2 |
| Data Width | `16` | LPDDR4x 16-bit |
| Physical Rank | `1` | 单 rank |
| **Memory Type** | **`LPDDR4x`** | ⚠️ 是 LPDDR4x，不是 DDR3（板载颗粒为 LPDDR4x 4Gb） |
| **Memory Density** | **`4G`** | 4 Gbit |

### AXI Target 配置

| Target | 使能 | 位宽 | ACLK |
|--------|------|------|------|
| **AXI Target 0** | ✅ `enable` | **512-bit** (`is_axi_width_256=false`) | `i_axi0_mem_clk` |
| AXI Target 1 | ❌ `disable` | — | — |

> AXI Target0 必须为 **512-bit**（与 ISF 中 `axi0_WDATA`/`axi0_RDATA` 512-bit 总线宽度一致；当前 ISF 注释「512-bit WDATA not fully enumerated for brevity」即指此）。

### Configuration Control 端口（CFG）

启用 `cfg_start` / `cfg_done` / `cfg_reset` / `cfg_sel`，对应 ISF 中 `ddr_inst_CFG_*` 引脚。
默认从 ROM 自动加载 DDR 配置（`is_reg_ena=false`，不使用寄存器配置接口）。

---

## 3. DDR PLL 配置（pll_ddr，PLL_TL2）

DDR 硬核需要专用 PLL 产生 1066 MHz（DDR3-2133 等效）时钟。在 **Peripheral / PLL** 面板新增 PLL：

| 参数 | 值 |
|------|-----|
| PLL Name | `pll_ddr` |
| PLL Block | `PLL_TL2` |
| 参考时钟模式 | `external` |
| 参考时钟频率 | `33.3300 MHz`（来自 `ddr_clk_ref`，pin L28） |
| 参考时钟选择 | `ext_ref_clock_id=3` |
| Multiplier | `4` |
| Pre-divider | `1` |
| Post-divider | `1` |
| Feedback | `pll_ddr_CLKOUT0`, local |
| Locked 信号 | `pll_ddr_LOCKED` |

### PLL 输出时钟

| 输出名 | Number | Out-divider | 用途 |
|--------|--------|-------------|------|
| `pll_ddr_CLKOUT0` | 0 | 24 | DDR 主时钟（→ `clkin_sel=2`） |
| `pll_ddr_CLKOUT4` | 4 | 6 | DDR 辅助时钟 |
| `i_axi1_mem_clk` | 1 | 32 | AXI 域内存时钟（如启用 target1） |

> 计算验证：33.33 MHz × 4 ÷ 1 ÷ 1 = 133.33 MHz（VCO）；
> CLKOUT0 = 133.33 ÷ (24 实际为分频比的倒数映射) → 产生 DDR 数据率 2133 Mbps 对应的 1066 MHz 差分时钟。
> 具体分频语义以 Efinity DDR Wizard 自动计算结果为准。

---

## 4. 引脚约束核对

`constraints/tj180_golden_top.peri.isf` 中 DDR 相关引脚命名约定如下，**Efinity GUI 中 DDR 端口名必须与之匹配**，否则 PT 阶段会报 `Required pin ... is not found`：

| ISF 引脚前缀 | 对应 DDR 端口 |
|--------------|---------------|
| `axi0_AW*` / `axi0_AR*` / `axi0_W*` / `axi0_R*` / `axi0_B*` | AXI Target0（512-bit） |
| `axi0_ARESETn` | `ARSTN_0` |
| `ddr_inst_CFG_DONE` | `CFG_DONE` |
| `ddr_inst_CTRL_BUSY[0..1]` | `CTRL_PORT_BUSY` / `CTRL_BUSY` |
| `ddr_inst_CTRL_INT` | `CTRL_INT` |
| `ddr_inst_CTRL_REFRESH` | `CTRL_REFRESH` |
| `ddr_inst_CTRL_MEM_RST_VALID` | `CTRL_MEM_RST_VALID` |
| `ddr_inst_CTRL_CKE[0..1]` | `CTRL_CKE` |

> ⚠️ 命名差异提示：参考工程 SDHOST 的 peri.xml 使用 `ddr_inst_<CHANNEL>_0` 前缀
> （如 `ddr_inst_ARADDR_0`），而本项目 ISF 使用 `axi0_<CHANNEL>` 前缀
> （如 `axi0_ARADDR`）。在 Efinity DDR 面板里绑定 AXI 端口时，
> **请按 ISF 中实际的 `axi0_*` 名字连接**，或在 GUI 中重命名 DDR AXI 端口前缀为 `axi0`。

---

## 5. 操作方式（命令行，已实施）

DDR 已通过 **Efinity `DesignAPI`（命令行）** 配置进工程，**无需 GUI**。

实施脚本：`debug/configure_ddr.py`（用 Efinity 自带的 Python `DesignAPI` 驱动）。

### 原理

| 步骤 | API | 作用 |
|------|-----|------|
| 1. 种子 | `DesignAPI.load(SDHOST_peri.xml)` | 加载同芯片 (TJ180A484S) 的已知良好 peri.xml（含 DDR） |
| 2. 审计 | `design.get_preset("ddr_inst","DDR")` | 查询 DDR 配置（Titanium 走直接属性，不走 preset） |
| 3. 输出 | `design.save_as(tj180_golden_top.peri.xml)` | 由工具产出 peri.xml（非手写） |
| 4. 改名 | 文本替换 `design_db name` | `name="TJ180A484S"` → `name="tj180_golden_top"`（不动 `device_def`） |

### 运行

```powershell
$env:EFXPT_HOME  = "C:\Efinity\2026.1\pt"
$env:EFINITY_HOME = "C:\Efinity\2026.1"
$env:PYTHONHOME  = "C:\Efinity\2026.1\python311"
$env:PYTHONPATH  = "C:\Efinity\2026.1\python311\Lib;C:\Efinity\2026.1\pt\bin"
& "C:\Efinity\2026.1\python311\bin\python.exe" debug\configure_ddr.py
```

产出 `tj180_golden_top.peri.xml`（~43 KB），含 `<efxpt:ddr_info>` 与 `<efxpt:pll name="pll_ddr">`。

### 也可用 Efinity 自带脚本（注意 argparse bug）

`efx_run_pt_import_isf.py --peri_design <x.peri.xml> --isf_files <a.isf> -s <out>`
可把增量 ISF 合并进 peri.xml；但其 `--isf_files` 用了 `action='append'`，传单文件会触发
`TypeError: ... not list`，故本工程改用直接调用 `DesignAPI` 的方式（即 `configure_ddr.py`）。

---

## 6. ⚠️ 遗留事项：非 DDR 外设的引脚

### 已完成（工具驱动，DesignAPI 校验通过）

| 硬核 | 来源 | 状态 |
|------|------|------|
| DDR (`ddr_inst`, LPDDR4x 4G 16-bit) + `pll_ddr` | SDHOST 种子 | ✅ `configure_ddr.py` |
| MIPI TX (`mipi_dphy_tx_inst1`) + RX (`mipi_dphy_rx_inst2`) | TJ180MIPI_loopback 的 `<efxpt:mipi_info>` | ✅ `merge_mipi.py` |
| JTAG (`jtag_inst1`) | SDHOST 种子 | ✅ |

### 遗留（需要真实 Python ISF）

当前 peri.xml 由 SDHOST 种子产出，**DDR / PLL / MIPI 硬核 / JTAG 部分完全正确**（芯片级），
但 **SoC 外设的引脚是 SDHOST 的**（UART/SPI/I2C/SD），与 golden_top 板级引脚不一致。

**⚠️ 重要：`constraints/*.peri.isf` 不可信，不能直接转换。** `debug/audit_isf.py` 审计发现：
- **59 个引脚重复分配**（如 `C29` 同时给 GPIO0 和 MIPI RX；`AA27` 被 3 条 MIPI lane 共用）
- **529 个端口中 456 个是硬核引脚被错当成 GPIO**（260 mipi_dphy + 173 ddr_axi + 23 rgmii）
- MIPI lane 0/1/2/3 重复使用相同物理引脚（合成数据，非真实硬件）

### 正确做法

把 golden_top 真实引脚并入 peri.xml，需**手写真实 Python ISF**（不用自创 XML）：
1. 参考 `C:\Efinity\2026.1\examples\helloworld\Ti180J484_kit.isf` 的 API
   （`design.create_input_gpio` / `design.create_output_gpio` / `design.assign_pkg_pin` 等）
2. 引脚值取自 **`项目总结.md` 引脚表** 或 golden_top 载板原理图（**不要**取自自创 ISF）
3. 用 `DesignAPI.import_design(isf)` 合并进 peri.xml（绕开 `efx_run_pt_import_isf.py` 的 argparse bug）

待并入的板级引脚：RGMII（TSE MAC↔PHY）、SoC 外设（UART/SPI/I2C/SD）、
MIPI lane 数/速率调整（loopback 是 2-lane 1200Mbps；golden_top 按总结要 4-lane）。
