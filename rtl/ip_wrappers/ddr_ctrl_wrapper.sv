`default_nettype none
`timescale 1ns / 1ps

//============================================================================
// 模块名称: ddr_ctrl_wrapper
// 功能描述: DDR 控制器包装模块。管理 DDR 硬 IP 的配置 FSM。
//           AXI 数据通路由顶层直接连线（SoC → DDR AXI0 端口），
//           本模块仅负责 DDR 配置时序和 AXI 复位控制。
// 接口说明: DDR 硬 IP 状态输入，配置/复位输出
// 设计约束: 等 ddr_inst_CFG_DONE 拉高后才允许 AXI 访问
//============================================================================
module ddr_ctrl_wrapper (
    // -- Clock & Reset --
    input  wire        soc_clk_i,            // SoC 系统时钟
    input  wire        mem_clk_i,            // DDR AXI 时钟 (i_axi0_mem_clk)
    input  wire        arst_n_i,             // 全局异步复位（低有效）

    // -- DDR 硬 IP 控制信号 (顶层 peri 端口) --
    output wire        ddr_cfg_start_o,
    output wire        ddr_cfg_reset_o,
    output wire        ddr_cfg_sel_o,
    output wire        ddr_axi0_aresetn_o,
    output wire        ddr_axi1_aresetn_o,

    // -- DDR 硬 IP 状态 --
    input  wire        ddr_cfg_done_i,
    input  wire        ddr_ctrl_busy_i,
    input  wire        ddr_ctrl_int_i,
    input  wire        ddr_ctrl_refresh_i,
    input  wire        ddr_ctrl_mem_rst_valid_i,
    input  wire        ddr_ctrl_dp_idle_i,
    input  wire [1:0]  ddr_ctrl_port_busy_i,

    // -- SoC memory reset output --
    output wire        soc_mem_reset_o
);

    //==================================================================
    // DDR 配置 FSM（参考 TJ180A484S.v）
    //==================================================================
    localparam [1:0] FSM_IDLE      = 2'b00;
    localparam [1:0] FSM_CFG_START = 2'b01;
    localparam [1:0] FSM_CFG_DONE  = 2'b11;

    (* fsm_encoding = "one-hot" *) reg [1:0] cfg_st;
    reg [1:0]  cfg_next;
    reg [7:0]  cfg_count;

    wire ddr_cfg_ok = (cfg_st == FSM_CFG_DONE);

    // 同步 io_memoryReset 到 soc_clk 域
    reg mem_rst_r;
    always @(posedge soc_clk_i or negedge arst_n_i) begin
        if (!arst_n_i)
            mem_rst_r <= 1'b1;
        else
            mem_rst_r <= 1'b0; // SoC 不提供 memoryReset 时默认 0
    end
    assign soc_mem_reset_o = mem_rst_r;

    // DDR 配置 FSM
    always @(posedge soc_clk_i or negedge arst_n_i) begin
        if (!arst_n_i) begin
            cfg_st    <= FSM_IDLE;
            cfg_count <= 8'h0;
        end else begin
            cfg_st <= cfg_next;
            if (cfg_st == FSM_IDLE)
                cfg_count <= cfg_count + 1'b1;
            else
                cfg_count <= 8'h0;
        end
    end

    // 组合逻辑 — 顶部默认值
    always @(*) begin
        cfg_next = cfg_st;
        case (cfg_st)
            FSM_IDLE: begin
                if (cfg_count == 8'hff)
                    cfg_next = FSM_CFG_START;
                else
                    cfg_next = FSM_IDLE;
            end
            FSM_CFG_START: begin
                if (ddr_cfg_done_i)
                    cfg_next = FSM_CFG_DONE;
                else
                    cfg_next = FSM_CFG_START;
            end
            FSM_CFG_DONE: cfg_next = FSM_CFG_DONE;
            default:      cfg_next = FSM_IDLE;
        endcase
    end

    //==================================================================
    // DDR 控制
    //==================================================================
    assign ddr_cfg_start_o = (cfg_st != FSM_IDLE);
    assign ddr_cfg_reset_o = (cfg_st == FSM_IDLE);
    assign ddr_cfg_sel_o   = 1'b0;

    // AXI reset — DDR 配置完成后释放
    assign ddr_axi0_aresetn_o = ddr_cfg_ok;
    assign ddr_axi1_aresetn_o = ddr_cfg_ok;

    //==================================================================
    // AXI 数据通路说明:
    // Stage 1 中 SoC 32-bit AXI 由顶层直接连线到 DDR AXI0 端口。
    // 位宽转换（32↔512）将在 DDR 硬 IP 端口宽度确认后添加
    // axi_dwidth_converter 层。
    //==================================================================

    // 防止未使用信号产生 warning
    wire _unused = &{1'b0, mem_clk_i, ddr_ctrl_busy_i,
        ddr_ctrl_refresh_i, ddr_ctrl_mem_rst_valid_i,
        ddr_ctrl_dp_idle_i, ddr_ctrl_port_busy_i, 1'b0};

endmodule

`default_nettype wire
