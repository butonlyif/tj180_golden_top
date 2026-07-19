`default_nettype none
`timescale 1ns / 1ps

//============================================================================
// 模块名称: sdhost_slot_wrapper
// 功能描述: SD Host 控制器槽位包装。
//
//   ⚠️ 现状（2026-07-18）：仓库内 `ip/apb3_2_axi4_lite_sdhost/` 只是一个
//      APB3↔AXI4-Lite 总线桥 IP（Efinitix efx_apb3_2_axi4_lite v5.2），
//      目录名里的 "sdhost" 是误导 —— 它不是真正的 SD Host 控制器。
//      真正的 SD Host 控制器 IP 在仓库内不存在（参考 ip/tj180a484s_sdhost/
//      的 `top_soc_sd` 集成方式，SD Host 是 Sapphire SoC 变体的内置 IP）。
//
//   本包装做三件事：
//     1) 例化 `apb3_2_axi4_lite_sdhost` 桥（建立 APB→AXI-Lite 总线拓扑）。
//     2) 在 AXI-Lite 总线远端挂一个 axilite_idle_slave：对所有访问回
//        OKAY + prdata=0xDEAD_BEEF（魔数标识"无设备"），避免 SoC APB 主控
//        探测该区域时挂死。
//     3) 暴露 SD 物理引脚（sd_clk/sd_cmd/sd_dat），但当前保持安全默认
//        （sd_clk=0, oe=0, dat=0）—— 真正驱动 SD 卡需要后续接入 SD Host IP。
//
//   将来替换：当真正的 SD Host 控制器 IP 进仓库后，把 u_axilite_idle 换成
//   控制器 IP 的 AXI-Lite slave 端口，并把 SD 引脚直接接到控制器顶层即可。
//
// 接口说明: APB3 Slave + SD 物理引脚（输出形式，匹配顶层 _o/_oe 风格）
// 设计约束: 同 sys_clk 域，无 CDC；SD 引脚输出保持安全静态默认。
//============================================================================
module sdhost_slot_wrapper #(
    parameter DW = 32
)(
    input  wire        clk_i,          // = sys_clk
    input  wire        rst_n_i,        // 同 sys_rst_n

    // -- APB3 Slave (来自 apb_decoder 的 slave 2) --
    input  wire [15:0] apb_paddr_i,
    input  wire        apb_psel_i,
    input  wire        apb_penable_i,
    input  wire        apb_pwrite_i,
    input  wire [DW-1:0] apb_pwdata_i,
    output wire [DW-1:0] apb_prdata_o,
    output wire        apb_pready_o,
    output wire        apb_pslverror_o,

    // -- SD 物理引脚（输出形式，安全默认） --
    output wire        sd_clk_o,       // 当前 = 1'b0
    output wire        sd_cmd_o,       // 当前 = 1'b0
    output wire        sd_cmd_oe,      // 当前 = 1'b0（高阻）
    input  wire        sd_cmd_i,       // 输入悬空，吸收 lint 用
    output wire [3:0]  sd_dat_o,       // 当前 = 4'h0
    output wire [3:0]  sd_dat_oe,      // 当前 = 4'h0（高阻）
    input  wire [3:0]  sd_dat_i,       // 输入悬空，吸收 lint 用
    input  wire        sd_cd_n         // 卡检测（输入；当前仅观测）
);

    //==================================================================
    // 1. APB3 ↔ AXI4-Lite 桥例化（IP v5.2, ADDR_WTH=10）
    //==================================================================
    wire [9:0]   axi_awaddr;
    wire         axi_awvalid;
    wire         axi_awready;
    wire [31:0]  axi_wdata;
    wire         axi_wvalid;
    wire         axi_wready;
    wire [1:0]   axi_bresp;
    wire         axi_bvalid;
    wire         axi_bready;
    wire [9:0]   axi_araddr;
    wire         axi_arvalid;
    wire         axi_arready;
    wire [31:0]  axi_rdata;
    wire [1:0]   axi_rresp;
    wire         axi_rvalid;
    wire         axi_rready;

    apb3_2_axi4_lite_sdhost u_bridge (
        .s_apb3_paddr    ( apb_paddr_i[9:0] ),
        .s_apb3_psel     ( apb_psel_i       ),
        .s_apb3_penable  ( apb_penable_i    ),
        .s_apb3_pwrite   ( apb_pwrite_i     ),
        .s_apb3_pwdata   ( apb_pwdata_i     ),
        .s_apb3_pready   ( apb_pready_o     ),
        .s_apb3_prdata   ( apb_prdata_o     ),
        .s_apb3_pslverror( apb_pslverror_o),
        .clk             ( clk_i            ),
        .rstn            ( rst_n_i          ),

        .m_axi_awaddr    ( axi_awaddr       ),
        .m_axi_awvalid   ( axi_awvalid      ),
        .m_axi_awready   ( axi_awready      ),
        .m_axi_wdata     ( axi_wdata        ),
        .m_axi_wvalid    ( axi_wvalid       ),
        .m_axi_wready    ( axi_wready       ),
        .m_axi_araddr    ( axi_araddr       ),
        .m_axi_arvalid   ( axi_arvalid      ),
        .m_axi_arready   ( axi_arready      ),
        .m_axi_rdata     ( axi_rdata        ),
        .m_axi_rvalid    ( axi_rvalid       ),
        .m_axi_rready    ( axi_rready       )
    );

    //==================================================================
    // 2. AXI4-Lite "无设备" Slave：所有访问立刻 OKAY 回 0xDEAD_BEEF
    //   - 单拍写：收到 AW+W 后立刻回 BVALID=1, BRESP=OKAY
    //   - 单拍读：收到 AR 后立刻回 RVALID=1, RRESP=OKAY, RDATA=magic
    //   - 这是一个 minimum footprint 占位实现，等真正的 SD Host IP 替换。
    //==================================================================
    // 写通道：始终准备好接收
    assign axi_awready = axi_awvalid;
    assign axi_wready  = axi_wvalid;
    assign axi_bresp   = 2'b00;          // OKAY
    // bvalid 在 aw&w 都握手后拉高一拍
    reg         bvalid_r;
    reg         bvalid_next;
    wire        aw_w_done = (axi_awvalid & axi_awready) &&
                            (axi_wvalid  & axi_wready);
    always @(*) begin
        bvalid_next = bvalid_r;
        if (bvalid_r & axi_bready) bvalid_next = 1'b0;     // 主控取走
        else if (aw_w_done & ~bvalid_r) bvalid_next = 1'b1; // 新事务完成
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) bvalid_r <= 1'b0;
        else          bvalid_r <= bvalid_next;
    end
    assign axi_bvalid  = bvalid_r;
    assign axi_bready  = 1'b1;           // 始终接受 B

    // 读通道：arready=arvalid 单拍握手；下一拍回 RVALID
    assign axi_arready = axi_arvalid;
    reg         rvalid_r;
    reg         rvalid_next;
    always @(*) begin
        rvalid_next = rvalid_r;
        if (rvalid_r & axi_rready) rvalid_next = 1'b0;
        else if (axi_arvalid & axi_arready & ~rvalid_r) rvalid_next = 1'b1;
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) rvalid_r <= 1'b0;
        else          rvalid_r <= rvalid_next;
    end
    assign axi_rvalid  = rvalid_r;
    assign axi_rresp   = 2'b00;          // OKAY
    assign axi_rdata   = 32'hDEAD_BEEF;  // 标识"无设备"
    assign axi_rready  = 1'b1;           // 始终接受 R（占位用，桥驱动）

    //==================================================================
    // 3. SD 物理引脚 — 安全默认（OE=0 高阻，输出 0）
    //==================================================================
    assign sd_clk_o  = 1'b0;
    assign sd_cmd_o  = 1'b0;
    assign sd_cmd_oe = 1'b0;
    assign sd_dat_o  = 4'h0;
    assign sd_dat_oe = 4'h0;

    // 消除输入未使用警告
    wire _unused_ok = &{1'b0, sd_cmd_i, sd_dat_i[3:0], sd_cd_n, 1'b0};

endmodule

`default_nettype wire
