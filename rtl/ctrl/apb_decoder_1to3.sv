`default_nettype none
`timescale 1ns / 1ps

//============================================================================
// 模块名称: apb_decoder_1to3
// 功能描述: APB3 1-to-3 地址译码器。
//           把 SoC APB Slave 0 端口按高位地址拆分到 3 个下游 APB 从设备：
//             • Slave 0 (CSI RX) : apb_paddr[15:11] == 5'b00000
//             • Slave 1 (TSE MAC): apb_paddr[15:11] == 5'b00001
//             • Slave 2 (SD Host): apb_paddr[15:11] == 5'b00010
//           其它地址 → 默认路由到 Slave 0（保持与 Stage 2/3 行为兼容）。
//           所有下游 APB 共享同一组 penable/pwrite/pwdata（无 CDC，同 sys_clk 域），
//           每个从设备单独的 psel 用于门控，返回信号 (pready/prdata/pslverror) 经
//           译码 MUX 选择后回 SoC。
// 接口说明: APB3 (16-bit addr / 32-bit data) 输入 → 3 组 APB3 输出
// 设计约束: 纯组合译码；psel 在 setup/access 阶段保持稳定；遵循 APB3 单从设备
//           激活原则（同一拍仅 1 个 psel=1）。
//============================================================================
module apb_decoder_1to3 #(
    parameter AW   = 16,     // APB 地址位宽（与 SoC 一致）
    parameter DW   = 32      // 数据位宽
)(
    input  wire              clk_i,        // 时钟（仅用于复位同步，组合译码不用）
    input  wire              rst_n_i,      // 异步低有效复位（保留接口，当前未用）

    // -- APB3 Master (来自 SoC) --
    input  wire [AW-1:0]     apb_paddr_i,
    input  wire              apb_psel_i,
    input  wire              apb_penable_i,
    input  wire              apb_pwrite_i,
    input  wire [DW-1:0]     apb_pwdata_i,
    output wire [DW-1:0]     apb_prdata_o,
    output wire              apb_pready_o,
    output wire              apb_pslverror_o,

    // -- APB3 Slave 0 (CSI RX) --
    output wire [AW-1:0]     s0_paddr_o,
    output wire              s0_psel_o,
    output wire              s0_penable_o,
    output wire              s0_pwrite_o,
    output wire [DW-1:0]     s0_pwdata_o,
    input  wire [DW-1:0]     s0_prdata_i,
    input  wire              s0_pready_i,
    input  wire              s0_pslverror_i,

    // -- APB3 Slave 1 (TSE MAC) --
    output wire [AW-1:0]     s1_paddr_o,
    output wire              s1_psel_o,
    output wire              s1_penable_o,
    output wire              s1_pwrite_o,
    output wire [DW-1:0]     s1_pwdata_o,
    input  wire [DW-1:0]     s1_prdata_i,
    input  wire              s1_pready_i,
    input  wire              s1_pslverror_i,

    // -- APB3 Slave 2 (SD Host slot) --
    output wire [AW-1:0]     s2_paddr_o,
    output wire              s2_psel_o,
    output wire              s2_penable_o,
    output wire              s2_pwrite_o,
    output wire [DW-1:0]     s2_pwdata_o,
    input  wire [DW-1:0]     s2_prdata_i,
    input  wire              s2_pready_i,
    input  wire              s2_pslverror_i
);

    //==================================================================
    // 地址译码（apb_paddr[15:11] 高 5 位用作 slave select）
    //==================================================================
    localparam [2:0] SEL_CSI_RX = 3'd0;   // 5'b00000 → 默认/CSI RX
    localparam [2:0] SEL_TSE_MAC = 3'd1;  // 5'b00001 → TSE MAC
    localparam [2:0] SEL_SD_HOST = 3'd2;  // 5'b00010 → SD Host

    // 综合友好：把 5-bit 区段映射成 3-bit sel（仅 3 个有效编码 + 默认）
    function automatic [2:0] addr2sel(input [4:0] hi);
        case (hi)
            5'b00000: addr2sel = SEL_CSI_RX;
            5'b00001: addr2sel = SEL_TSE_MAC;
            5'b00010: addr2sel = SEL_SD_HOST;
            default : addr2sel = SEL_CSI_RX;   // 默认落到 CSI RX（兼容旧行为）
        endcase
    endfunction

    wire [2:0] sel;
    assign sel = addr2sel(apb_paddr_i[15:11]);

    // 单从设备选择信号（psel 不能两从设备同时拉高）
    wire sel_s0 = apb_psel_i & (sel == SEL_CSI_RX);
    wire sel_s1 = apb_psel_i & (sel == SEL_TSE_MAC);
    wire sel_s2 = apb_psel_i & (sel == SEL_SD_HOST);

    //==================================================================
    // 下游 APB 公共信号广播（penable/pwrite/pwdata/paddr 全部下传）
    //==================================================================
    assign s0_paddr_o   = apb_paddr_i;
    assign s0_psel_o    = sel_s0;
    assign s0_penable_o = apb_penable_i;
    assign s0_pwrite_o  = apb_pwrite_i;
    assign s0_pwdata_o  = apb_pwdata_i;

    assign s1_paddr_o   = apb_paddr_i;
    assign s1_psel_o    = sel_s1;
    assign s1_penable_o = apb_penable_i;
    assign s1_pwrite_o  = apb_pwrite_i;
    assign s1_pwdata_o  = apb_pwdata_i;

    assign s2_paddr_o   = apb_paddr_i;
    assign s2_psel_o    = sel_s2;
    assign s2_penable_o = apb_penable_i;
    assign s2_pwrite_o  = apb_pwrite_i;
    assign s2_pwdata_o  = apb_pwdata_i;

    //==================================================================
    // 返回路径 MUX（仅在选中的从设备上取 pready/prdata/pslverror）
    // 未选中拍 pready=0（SoC APB 主控自然等待），但只有 psel=1 时才会真正
    // 触发 access，所以不会挂死。
    //==================================================================
    assign apb_prdata_o = (sel == SEL_TSE_MAC) ? s1_prdata_i :
                          (sel == SEL_SD_HOST) ? s2_prdata_i :
                                                 s0_prdata_i;

    assign apb_pready_o = (sel == SEL_TSE_MAC) ? s1_pready_i :
                          (sel == SEL_SD_HOST) ? s2_pready_i :
                                                 s0_pready_i;

    assign apb_pslverror_o = (sel == SEL_TSE_MAC) ? s1_pslverror_i :
                             (sel == SEL_SD_HOST) ? s2_pslverror_i :
                                                    s0_pslverror_i;

endmodule

`default_nettype wire
