---
name: AweSOM RTL rules
description: Mandatory RTL, CDC, reset and verification rules
applyTo: "**/*.{v,sv,vh,sdc}"
---

# RTL 编码规范（按需加载）

> 涉及 FPGA 开发时加载此文件。

## Efinity 格式兼容性（硬性规则）

**严禁自创或简化 Efinity 的文件格式。** 所有 Efinity 相关的文件（工程 XML、约束、IP、报告等）必须严格使用 Efinity 原生格式，否则会造成兼容性问题。

- **工程 XML**：必须使用 Efinity `enf_proj` schema（`xmlns:efx="http://www.efinixinc.com/enf_proj"`），结构对齐 `$EFINITY_HOME/examples/helloworld-unified/helloworld.xml`。
- **约束文件**：引脚约束必须使用 Efinity **ISF (Interface Script Format)**，即 `design.set_device_property(...)`、`design.create_input_gpio(...)`、`design.assign_pkg_pin(...)` 等 API。ISF 由 Efinity 的 `efx_run_pt_unified.py` 消费，翻译成 `<design>.peri.xml`。
  - ❌ 不要自创 `<efx:gpio>` 标签的简化 XML 格式——Efinity 工具链不认。
  - ❌ 不要自己写 XML→ISF 转换器——Efinity 已提供 `efx_run_pt_gen_isf.py`（peri.xml → ISF）和 `efx_run_pt_import_isf.py`（ISF → peri.xml）。
- **`<design>.peri.xml`**：这是 PT 工具产出的 `efxpt:design_db` 命名空间 XML，**只有 Efinity 的 PT 工具/GUI 能产出**，用户和 SDK 都不应手工编写。
- **目录布局**：工程文件放在工程根目录（Efinity 原生布局），不要放进 `efinity_project/` 之类的自创子目录。
- **通用原则**：任何"为了简化而自创格式"的冲动都必须停止。Efinity 工具链是完整自洽的，参考 `$EFINITY_HOME/examples/` 和 `$EFINITY_HOME/scripts/` 下的官方资源。详细命令清单见 [docs/efinity-toolchain-reference.md](../docs/efinity-toolchain-reference.md)。

---

# RTL Coding Style for Efinix FPGA

ALL Verilog/SystemVerilog code MUST follow these rules. This is the complete
style reference — do NOT just link to an external file.

## 1. File Naming & Organization

- One module per file. File name = module name: `mipi_csi_rx.sv`
- lowercase + underscore (NOT kebab-case): `ddr3_controller.sv` ✅, `ddr3-controller.sv` ❌
- Extension: `.sv` preferred for new code, `.v` for Verilog
- Top-level: `_top` suffix → `awesom_golden_top.v`
- Directory: `rtl/top/`, `rtl/clk_rst/`, `rtl/data_path/`, `rtl/ctrl/`, `rtl/cdc/`, `rtl/ip_wrappers/`

## 2. Module Template

```systemverilog
`default_nettype none
`timescale 1ns / 1ps

//============================================================================
// 模块名称: <module_name>
// 功能描述: <one-line description>
// 接口说明: <AXI-Stream / Avalon-MM / custom handshake>
// 设计约束: <clock freq, latency, throughput>
//============================================================================
module module_name #(
    parameter DATA_WIDTH = 16
)(
    input  wire                    clk_i,
    input  wire                    rst_n_i,
    input  wire [DATA_WIDTH-1:0]   data_i,
    input  wire                    valid_i,
    output wire                    ready_o,
    output wire [DATA_WIDTH-1:0]   data_o,
    output wire                    valid_o,
    input  wire                    ready_i
);
    // ... implementation ...
endmodule

`default_nettype wire
```

## 3. Port & Signal Naming

| Direction | Suffix | Example |
|-----------|--------|---------|
| Input     | `_i`   | `clk_i`, `data_i`, `valid_i` |
| Output    | `_o`   | `data_o`, `valid_o`, `led_o` |
| Bidir     | `_io`  | `sda_io` |
| Active-low| `_n`   | `rst_n_i`, `cs_n_o` |

Internal: `cnt_r`, `fifo_full`, `ST_IDLE`, localparam `DATA_WIDTH` / `MAX_BURST`.

❌ NEVER: `inout` inside the design (only top-level IO). Use `_i`/`_o`/`_oe` triplet.
❌ NEVER: `.*` wildcard port connections. Always explicit: `.clk_i(clk_i)`.
❌ NEVER: complex logic in top-level module (only instantiations + wiring).

## 4. Clock & Reset

### Async Reset, Sync Release (MANDATORY)

```systemverilog
// 3-stage sync release — always use this pattern
reg [2:0] rst_sync;
always @(posedge clk or negedge rst_n_i) begin
    if (!rst_n_i)
        rst_sync <= 3'b000;
    else
        rst_sync <= {rst_sync[1:0], 1'b1};
end
wire rst_n = rst_sync[2];
```

- Top-level provides one `rst_n_i` (async, active-low)
- Each clock domain has its own sync-release `rst_n`
- Reset ONLY control logic. Data-path registers use valid-based gating.
- ❌ NEVER: async reset without sync release → metastability on de-assertion.

### Clock Enable, NOT Divided Clock

❌ NEVER use divided clocks to drive logic:
```systemverilog
always @(posedge clk_div2) cnt <= cnt + 1;  // ❌ BAD
```

✅ Always use clock enable:
```systemverilog
reg clk_en;
always @(posedge sys_clk) clk_en <= ~clk_en;
always @(posedge sys_clk) if (clk_en) cnt <= cnt + 1;  // ✅ GOOD
```

Clock naming: `clk_50m_i` (input), `sys_clk` (system), `video_clk` (domain), `pll_200m` (PLL).

## 5. Timing-Friendly Coding

### Register Outputs (STRONGLY RECOMMENDED)

```systemverilog
always @(posedge clk) begin
    data_o  <= data_next;
    valid_o <= valid_next;
end
```

- Data and control (valid/last/user) MUST be in the SAME always block.
- Output reg: on the SENDER side if there's cross-module timing violation.

### Pipeline Insertion

When ≥3 consecutive LUTs without register AND logic delay > 60% of period:
```systemverilog
// ❌ assign result = stage3(stage2(stage1(data)));
// ✅
reg [W-1:0] pipe1, pipe2;
always @(posedge clk) pipe1 <= stage1(data);
always @(posedge clk) pipe2 <= stage2(pipe1);
assign result = stage3(pipe2);
```

### High Fanout (>200)

```systemverilog
(* max_fanout = 100 *) reg shared_enable;
// OR manually replicate:
reg [3:0] en_replica;
always @(posedge clk) en_replica <= {4{en_src}};
```

## 6. Synthesis-Friendly Coding

### FSM: One-Hot Encoding

```systemverilog
(* fsm_encoding = "one-hot" *)
reg [3:0] state, state_next;
localparam ST_IDLE  = 4'b0001;
localparam ST_READ  = 4'b0010;
```

### Latch Prevention (CRITICAL)

Every `case` MUST have `default`. Every `if-else` chain MUST have final `else`.

✅ Combinational `always @(*)`: assign defaults to ALL outputs at the TOP of the block:
```systemverilog
always @(*) begin
    next_state = state;   // default
    out_valid = 1'b0;     // default
    case (state)
        ST_IDLE: if (start) next_state = ST_RUN;
        ST_RUN:  if (done)  begin next_state = ST_IDLE; out_valid = 1'b1; end
        default: next_state = ST_IDLE;
    endcase
end
```

Latch causes: missing `else`, missing `default`, `<=` in combinational block.

## 7. CDC (Cross-Domain Clocking)

### Single-Bit: 2/3-Stage Synchronizer

```systemverilog
(* ASYNC_REG = "TRUE" *) reg [2:0] sync_ff;
always @(posedge clk_dst)
    sync_ff <= {sync_ff[1:0], src_signal};
wire signal_synced = sync_ff[2];
```

### Multi-Bit Bus: Toggle-Valid MUX Sync

```systemverilog
// Send side (clk_src)
always @(posedge clk_src)
    if (send) begin data_bus <= new_data; valid_toggle <= ~valid_toggle; end

// Receive side (clk_dst)
(* ASYNC_REG = "TRUE" *) reg [2:0] toggle_sync;
reg toggle_prev;
always @(posedge clk_dst) begin
    toggle_sync <= {toggle_sync[1:0], valid_toggle};
    toggle_prev <= toggle_sync[2];
    if (toggle_sync[2] != toggle_prev)
        captured_data <= data_bus;  // stable now
end
```

CDC rules:
- ANY cross-clock signal MUST pass through synchronizer.
- ❌ NEVER set `set_false_path` on entire CDC path in SDC.
- Use `set_clock_groups -asynchronous` + `set_false_path` on sync chain only.
- Fast→slow single-cycle pulse: stretch before sync.

## 8. Resource Inference

### BRAM

```systemverilog
(* ram_style = "block" *)
reg [DATA_W-1:0] mem [0:DEPTH-1];
reg [DATA_W-1:0] mem_rd;
always @(posedge clk) begin
    if (wr_en) mem[wr_addr] <= wr_data;
    mem_rd <= mem[rd_addr];  // output register — FREE in BRAM
end
```

### DSP

```systemverilog
(* use_dsp = "yes" *)
reg [17:0] mult_result;
always @(posedge clk)
    mult_result <= $signed(a) * $signed(b);  // registered I/O
```

### PLL

Configured in Interface Designer (hard IP). In RTL only declare the clock ports:
```systemverilog
input wire pll_clk_out,   // PLL output clock
input wire pll_locked,     // PLL lock indicator
```

## 9. Efinix-Specific Attributes

| Attribute | Use |
|-----------|-----|
| `(* ASYNC_REG = "TRUE" *)` | CDC sync chain marker |
| `(* max_fanout = N *)` | Fanout control |
| `(* ram_style = "block" *)` | Force BRAM inference |
| `(* use_dsp = "yes" *)` | Force DSP inference |
| `(* syn_keep = "true" *)` | Prevent optimization removal |
| `(* fsm_encoding = "one-hot" *)` | FSM encoding hint |

## 10. Anti-Patterns — NEVER

1. Combinational `always @(*)` without defaults → latch
2. `case` without `default` / `if` without `else` → latch
3. Divided clock driving logic → use clock enable
4. CDC without synchronizer → metastability
5. Async reset without sync release → metastability on de-assert
6. data and valid in DIFFERENT always blocks → misalignment
7. Mixing `=` and `<=` in same always block → sim/synth mismatch
8. `inout` ports inside the design → only top-level IO
9. BRAM read without output register → wasted free register
10. Multiplier without registered I/O → long combinational path
11. Signal name conflicts with Verilog keywords → compilation error
12. High fanout signal (>200) without replication → routing congestion

## 11. RTL Change Checklist (verify BEFORE completing)

**Structure:**
- [ ] File name = module name, lowercase + underscore
- [ ] Module header comment block present
- [ ] `` `default_nettype none `` / `` `default_nettype wire `` bookends
- [ ] Ports have `_i` / `_o` / `_n` direction suffixes

**Timing:**
- [ ] Module outputs are registered
- [ ] data + valid/last/user in same always block
- [ ] High-fanout signals have `max_fanout` or replication
- [ ] CDC signals have synchronizer + `ASYNC_REG` attribute

**Synthesis:**
- [ ] Every `case` has `default`
- [ ] Combinational `always @(*)` has defaults at top
- [ ] BRAM read uses output register
- [ ] Multiplier I/O are registered
- [ ] FSM uses `(* fsm_encoding = "one-hot" *)`

**Constraint:**
- [ ] SDC has `create_clock` for each clock (matches RTL port name)
- [ ] Async clock domains have `set_clock_groups -asynchronous`
- [ ] IO has `set_input_delay` / `set_output_delay`
