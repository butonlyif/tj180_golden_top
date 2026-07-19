////////////////////////////////////////////////////////////////////////////
//  TJ180A484S board top - SOC + SD Host
//
//  Port list matches outflow/TJ180A484S_template.v (Interface Designer).
//  PLL / GPIO binding: TJ180A484S.peri.xml
////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module TJ180A484S
(
  (* syn_peri_port = 0 *) input sd_cd_n,
  (* syn_peri_port = 0 *) input jtag_inst1_CAPTURE,
  (* syn_peri_port = 0 *) input jtag_inst1_DRCK,
  (* syn_peri_port = 0 *) input jtag_inst1_RESET,
  (* syn_peri_port = 0 *) input jtag_inst1_RUNTEST,
  (* syn_peri_port = 0 *) input jtag_inst1_SEL,
  (* syn_peri_port = 0 *) input jtag_inst1_SHIFT,
  (* syn_peri_port = 0 *) input jtag_inst1_TCK,
  (* syn_peri_port = 0 *) input jtag_inst1_TDI,
  (* syn_peri_port = 0 *) input jtag_inst1_TMS,
  (* syn_peri_port = 0 *) input jtag_inst1_UPDATE,
  (* syn_peri_port = 0 *) input sd_cmd_i,
  (* syn_peri_port = 0 *) input [3:0] sd_dat_i,
  (* syn_peri_port = 0 *) input clk_50M,
  (* syn_peri_port = 0 *) input i_ref_clk_ddr,
  (* syn_peri_port = 0 *) input system_uart_0_io_rxd,
  (* syn_peri_port = 0 *) input i_sd_clk,
  (* syn_peri_port = 0 *) input i_soc_clk,
  (* syn_peri_port = 0 *) input pll_sys_CLKOUT0,
  (* syn_peri_port = 0 *) input i_axi0_mem_clk,
  (* syn_peri_port = 0 *) input i_axi1_mem_clk,
  (* syn_peri_port = 0 *) input pll_ddr_CLKOUT0,
  (* syn_peri_port = 0 *) input pll_sys_LOCKED,
  (* syn_peri_port = 0 *) input pll_ddr_LOCKED,
  (* syn_peri_port = 0 *) input ddr_inst_ARREADY_0,
  (* syn_peri_port = 0 *) input ddr_inst_ARREADY_1,
  (* syn_peri_port = 0 *) input ddr_inst_AWREADY_0,
  (* syn_peri_port = 0 *) input ddr_inst_AWREADY_1,
  (* syn_peri_port = 0 *) input [5:0] ddr_inst_BID_0,
  (* syn_peri_port = 0 *) input [5:0] ddr_inst_BID_1,
  (* syn_peri_port = 0 *) input [1:0] ddr_inst_BRESP_0,
  (* syn_peri_port = 0 *) input [1:0] ddr_inst_BRESP_1,
  (* syn_peri_port = 0 *) input ddr_inst_BVALID_0,
  (* syn_peri_port = 0 *) input ddr_inst_BVALID_1,
  (* syn_peri_port = 0 *) input ddr_inst_CFG_DONE,
  (* syn_peri_port = 0 *) input ddr_inst_CTRL_BUSY,
  (* syn_peri_port = 0 *) input [1:0] ddr_inst_CTRL_CKE,
  (* syn_peri_port = 0 *) input ddr_inst_CTRL_CMD_Q_ALMOST_FULL,
  (* syn_peri_port = 0 *) input ddr_inst_CTRL_DP_IDLE,
  (* syn_peri_port = 0 *) input ddr_inst_CTRL_INT,
  (* syn_peri_port = 0 *) input ddr_inst_CTRL_MEM_RST_VALID,
  (* syn_peri_port = 0 *) input [1:0] ddr_inst_CTRL_PORT_BUSY,
  (* syn_peri_port = 0 *) input ddr_inst_CTRL_REFRESH,
  (* syn_peri_port = 0 *) input [511:0] ddr_inst_RDATA_0,
  (* syn_peri_port = 0 *) input [511:0] ddr_inst_RDATA_1,
  (* syn_peri_port = 0 *) input [5:0] ddr_inst_RID_0,
  (* syn_peri_port = 0 *) input [5:0] ddr_inst_RID_1,
  (* syn_peri_port = 0 *) input ddr_inst_RLAST_0,
  (* syn_peri_port = 0 *) input ddr_inst_RLAST_1,
  (* syn_peri_port = 0 *) input [1:0] ddr_inst_RRESP_0,
  (* syn_peri_port = 0 *) input [1:0] ddr_inst_RRESP_1,
  (* syn_peri_port = 0 *) input ddr_inst_RVALID_0,
  (* syn_peri_port = 0 *) input ddr_inst_RVALID_1,
  (* syn_peri_port = 0 *) input ddr_inst_WREADY_0,
  (* syn_peri_port = 0 *) input ddr_inst_WREADY_1,
  (* syn_peri_port = 0 *) input system_spi_0_io_data_0_read,
  (* syn_peri_port = 0 *) input system_spi_0_io_data_1_read,
  (* syn_peri_port = 0 *) output sd_clk_hi,
  (* syn_peri_port = 0 *) output sd_cmd_o,
  (* syn_peri_port = 0 *) output sd_cmd_oe,
  (* syn_peri_port = 0 *) output [3:0] sd_dat_o,
  (* syn_peri_port = 0 *) output [3:0] sd_dat_oe,
  (* syn_peri_port = 0 *) output system_uart_0_io_txd,
  (* syn_peri_port = 0 *) output [32:0] ddr_inst_ARADDR_0,
  (* syn_peri_port = 0 *) output [32:0] ddr_inst_ARADDR_1,
  (* syn_peri_port = 0 *) output ddr_inst_ARAPCMD_0,
  (* syn_peri_port = 0 *) output ddr_inst_ARAPCMD_1,
  (* syn_peri_port = 0 *) output [1:0] ddr_inst_ARBURST_0,
  (* syn_peri_port = 0 *) output [1:0] ddr_inst_ARBURST_1,
  (* syn_peri_port = 0 *) output [5:0] ddr_inst_ARID_0,
  (* syn_peri_port = 0 *) output [5:0] ddr_inst_ARID_1,
  (* syn_peri_port = 0 *) output [7:0] ddr_inst_ARLEN_0,
  (* syn_peri_port = 0 *) output [7:0] ddr_inst_ARLEN_1,
  (* syn_peri_port = 0 *) output ddr_inst_ARLOCK_0,
  (* syn_peri_port = 0 *) output ddr_inst_ARLOCK_1,
  (* syn_peri_port = 0 *) output ddr_inst_ARQOS_0,
  (* syn_peri_port = 0 *) output ddr_inst_ARQOS_1,
  (* syn_peri_port = 0 *) output [2:0] ddr_inst_ARSIZE_0,
  (* syn_peri_port = 0 *) output [2:0] ddr_inst_ARSIZE_1,
  (* syn_peri_port = 0 *) output ddr_inst_ARSTN_0,
  (* syn_peri_port = 0 *) output ddr_inst_ARSTN_1,
  (* syn_peri_port = 0 *) output ddr_inst_ARVALID_0,
  (* syn_peri_port = 0 *) output ddr_inst_ARVALID_1,
  (* syn_peri_port = 0 *) output [32:0] ddr_inst_AWADDR_0,
  (* syn_peri_port = 0 *) output [32:0] ddr_inst_AWADDR_1,
  (* syn_peri_port = 0 *) output ddr_inst_AWALLSTRB_0,
  (* syn_peri_port = 0 *) output ddr_inst_AWALLSTRB_1,
  (* syn_peri_port = 0 *) output ddr_inst_AWAPCMD_0,
  (* syn_peri_port = 0 *) output ddr_inst_AWAPCMD_1,
  (* syn_peri_port = 0 *) output [1:0] ddr_inst_AWBURST_0,
  (* syn_peri_port = 0 *) output [1:0] ddr_inst_AWBURST_1,
  (* syn_peri_port = 0 *) output [3:0] ddr_inst_AWCACHE_0,
  (* syn_peri_port = 0 *) output [3:0] ddr_inst_AWCACHE_1,
  (* syn_peri_port = 0 *) output ddr_inst_AWCOBUF_0,
  (* syn_peri_port = 0 *) output ddr_inst_AWCOBUF_1,
  (* syn_peri_port = 0 *) output [5:0] ddr_inst_AWID_0,
  (* syn_peri_port = 0 *) output [5:0] ddr_inst_AWID_1,
  (* syn_peri_port = 0 *) output [7:0] ddr_inst_AWLEN_0,
  (* syn_peri_port = 0 *) output [7:0] ddr_inst_AWLEN_1,
  (* syn_peri_port = 0 *) output ddr_inst_AWLOCK_0,
  (* syn_peri_port = 0 *) output ddr_inst_AWLOCK_1,
  (* syn_peri_port = 0 *) output ddr_inst_AWQOS_0,
  (* syn_peri_port = 0 *) output ddr_inst_AWQOS_1,
  (* syn_peri_port = 0 *) output [2:0] ddr_inst_AWSIZE_0,
  (* syn_peri_port = 0 *) output [2:0] ddr_inst_AWSIZE_1,
  (* syn_peri_port = 0 *) output ddr_inst_AWVALID_0,
  (* syn_peri_port = 0 *) output ddr_inst_AWVALID_1,
  (* syn_peri_port = 0 *) output ddr_inst_BREADY_0,
  (* syn_peri_port = 0 *) output ddr_inst_BREADY_1,
  (* syn_peri_port = 0 *) output ddr_inst_CFG_RESET,
  (* syn_peri_port = 0 *) output ddr_inst_CFG_SEL,
  (* syn_peri_port = 0 *) output ddr_inst_CFG_START,
  (* syn_peri_port = 0 *) output ddr_inst_RREADY_0,
  (* syn_peri_port = 0 *) output ddr_inst_RREADY_1,
  (* syn_peri_port = 0 *) output [511:0] ddr_inst_WDATA_0,
  (* syn_peri_port = 0 *) output [511:0] ddr_inst_WDATA_1,
  (* syn_peri_port = 0 *) output ddr_inst_WLAST_0,
  (* syn_peri_port = 0 *) output ddr_inst_WLAST_1,
  (* syn_peri_port = 0 *) output [63:0] ddr_inst_WSTRB_0,
  (* syn_peri_port = 0 *) output [63:0] ddr_inst_WSTRB_1,
  (* syn_peri_port = 0 *) output ddr_inst_WVALID_0,
  (* syn_peri_port = 0 *) output ddr_inst_WVALID_1,
  (* syn_peri_port = 0 *) output jtag_inst1_TDO,
  (* syn_peri_port = 0 *) output system_spi_0_io_data_0_write,
  (* syn_peri_port = 0 *) output system_spi_0_io_data_0_writeEnable,
  (* syn_peri_port = 0 *) output system_spi_0_io_data_1_write,
  (* syn_peri_port = 0 *) output system_spi_0_io_data_1_writeEnable,
  (* syn_peri_port = 0 *) output system_spi_0_io_sclk_write,
  (* syn_peri_port = 0 *) output system_spi_0_io_ss
);

    //-------------------------------------------------------------------------
    // Global async reset (active-high w_sysclk_arst -> top_soc_sd.io_asyncReset)
    //
    // Same as ti180_oob_top (without user switch):
    //   io_asyncResetn = pll_sys_LOCKED & pll_ddr_LOCKED
    //   w_sysclk_arst    = ~io_asyncResetn
    //
    // SOC io_memoryReset / io_systemReset are outputs from soc_ti180.
    // DDR cfg FSM below waits for io_memoryReset deassert before starting.
    //-------------------------------------------------------------------------
    wire        io_asyncResetn;
    wire        w_sysclk_arst;
    wire        io_memoryReset;
    wire        io_systemReset;

    assign io_asyncResetn = pll_sys_LOCKED & pll_ddr_LOCKED;
    assign w_sysclk_arst    = ~io_asyncResetn;

    //-------------------------------------------------------------------------
    // LPDDR configuration FSM (same flow as ti180_oob_top / top_soc)
    //-------------------------------------------------------------------------
    localparam [1:0] IDLE      = 2'b00,
                     CFG_START = 2'b01,
                     CFG_DONE  = 2'b11;

    reg  [1:0]  cfg_st, cfg_next;
    reg  [7:0]  cfg_count;
    wire        ddr_cfg_ok;
    reg         r_ddr_reset;

    assign ddr_cfg_ok = (cfg_st == CFG_DONE);

    always @(posedge i_soc_clk or posedge w_sysclk_arst) begin
        if (w_sysclk_arst)
            r_ddr_reset <= 1'b1;
        else
            r_ddr_reset <= io_memoryReset;
    end

    always @(posedge i_soc_clk or posedge r_ddr_reset) begin
        if (r_ddr_reset) begin
            cfg_st    <= IDLE;
            cfg_count <= 8'h0;
        end else begin
            cfg_st <= cfg_next;
            if (cfg_st == IDLE)
                cfg_count <= cfg_count + 1'b1;
            else
                cfg_count <= 8'h0;
        end
    end

    always @(*) begin
        cfg_next = cfg_st;
        case (cfg_st)
            IDLE: begin
                if (cfg_count == 8'hff)
                    cfg_next = CFG_START;
                else
                    cfg_next = IDLE;
            end
            CFG_START: begin
                if (ddr_inst_CFG_DONE)
                    cfg_next = CFG_DONE;
                else
                    cfg_next = CFG_START;
            end
            CFG_DONE: cfg_next = CFG_DONE;
            default:  cfg_next = IDLE;
        endcase
    end

    assign ddr_inst_CFG_START = (cfg_st != IDLE);
    assign ddr_inst_CFG_RESET = (cfg_st == IDLE);
    assign ddr_inst_CFG_SEL   = 1'b0;

    //-------------------------------------------------------------------------
    // SOC io_ddrA <-> ddr_inst AXI port 0 (same glue as ti180_oob_top inst_soc_oob)
    //-------------------------------------------------------------------------
    wire [31:0] io_ddrA_ar_payload_addr_i;
    wire [31:0] io_ddrA_aw_payload_addr_i;
    wire [7:0]  io_ddrA_ar_payload_id_i;
    wire [7:0]  io_ddrA_aw_payload_id_i;
    wire [7:0]  io_ddrA_b_payload_id_i;
    wire [7:0]  io_ddrA_r_payload_id_i;

    assign ddr_inst_ARID_0 = {io_ddrA_ar_payload_id_i[7:6], io_ddrA_ar_payload_id_i[3:0]};
    assign ddr_inst_AWID_0 = {io_ddrA_aw_payload_id_i[7:6], io_ddrA_aw_payload_id_i[3:0]};
    assign io_ddrA_b_payload_id_i = {ddr_inst_BID_0[5:4], 2'b00, ddr_inst_BID_0[3:0]};
    assign io_ddrA_r_payload_id_i = {ddr_inst_RID_0[5:4], 2'b00, ddr_inst_RID_0[3:0]};

    assign ddr_inst_ARSTN_0     = ddr_cfg_ok;
    assign ddr_inst_ARAPCMD_0   = 1'b0;
    assign ddr_inst_AWALLSTRB_0 = 1'b0;
    assign ddr_inst_AWAPCMD_0   = 1'b0;
    assign ddr_inst_AWCOBUF_0   = 1'b0;
    assign ddr_inst_ARADDR_0    = {1'b0, io_ddrA_ar_payload_addr_i};
    assign ddr_inst_AWADDR_0    = {1'b0, io_ddrA_aw_payload_addr_i};

    //-------------------------------------------------------------------------
    // DDR AXI port 1 unused (no DMA engine on this board)
    //-------------------------------------------------------------------------
    assign ddr_inst_ARSTN_1     = ddr_cfg_ok;
    assign ddr_inst_ARVALID_1   = 1'b0;
    assign ddr_inst_ARADDR_1    = 33'h0;
    assign ddr_inst_ARBURST_1   = 2'h0;
    assign ddr_inst_ARID_1      = 6'h0;
    assign ddr_inst_ARLEN_1     = 8'h0;
    assign ddr_inst_ARLOCK_1    = 1'b0;
    assign ddr_inst_ARQOS_1     = 1'b0;
    assign ddr_inst_ARSIZE_1    = 3'h0;
    assign ddr_inst_ARAPCMD_1   = 1'b0;

    assign ddr_inst_AWVALID_1   = 1'b0;
    assign ddr_inst_AWADDR_1    = 33'h0;
    assign ddr_inst_AWALLSTRB_1 = 1'b0;
    assign ddr_inst_AWAPCMD_1   = 1'b0;
    assign ddr_inst_AWBURST_1   = 2'h0;
    assign ddr_inst_AWCACHE_1   = 4'h0;
    assign ddr_inst_AWCOBUF_1   = 1'b0;
    assign ddr_inst_AWID_1      = 6'h0;
    assign ddr_inst_AWLEN_1     = 8'h0;
    assign ddr_inst_AWLOCK_1    = 1'b0;
    assign ddr_inst_AWQOS_1     = 1'b0;
    assign ddr_inst_AWSIZE_1    = 3'h0;

    assign ddr_inst_WVALID_1    = 1'b0;
    assign ddr_inst_WDATA_1     = 512'h0;
    assign ddr_inst_WLAST_1     = 1'b0;
    assign ddr_inst_WSTRB_1     = 64'h0;

    assign ddr_inst_BREADY_1    = 1'b0;
    assign ddr_inst_RREADY_1    = 1'b0;

    //-------------------------------------------------------------------------
    // SOC + SD Host
    //-------------------------------------------------------------------------
    top_soc_sd u_top_soc_sd (
        .i_soc_clk                      (i_soc_clk),
        .io_asyncReset                  (w_sysclk_arst),
        .i_axi0_mem_clk                 (i_axi0_mem_clk),
        .io_memoryReset                 (io_memoryReset),
        .io_systemReset                 (io_systemReset),
        .i_sd_clk                       (i_sd_clk),

        .mem_ar_valid                   (ddr_inst_ARVALID_0),
        .mem_ar_ready                   (ddr_inst_ARREADY_0),
        .mem_ar_payload_addr            (io_ddrA_ar_payload_addr_i),
        .mem_ar_payload_id              (io_ddrA_ar_payload_id_i),
        .mem_ar_payload_region          (),
        .mem_ar_payload_len             (ddr_inst_ARLEN_0),
        .mem_ar_payload_size            (ddr_inst_ARSIZE_0),
        .mem_ar_payload_burst           (ddr_inst_ARBURST_0),
        .mem_ar_payload_lock            (ddr_inst_ARLOCK_0),
        .mem_ar_payload_cache           (),
        .mem_ar_payload_qos             (ddr_inst_ARQOS_0),
        .mem_ar_payload_prot            (),

        .mem_aw_valid                   (ddr_inst_AWVALID_0),
        .mem_aw_ready                   (ddr_inst_AWREADY_0),
        .mem_aw_payload_addr            (io_ddrA_aw_payload_addr_i),
        .mem_aw_payload_id              (io_ddrA_aw_payload_id_i),
        .mem_aw_payload_region          (),
        .mem_aw_payload_len             (ddr_inst_AWLEN_0),
        .mem_aw_payload_size            (ddr_inst_AWSIZE_0),
        .mem_aw_payload_burst           (ddr_inst_AWBURST_0),
        .mem_aw_payload_lock            (ddr_inst_AWLOCK_0),
        .mem_aw_payload_cache           (ddr_inst_AWCACHE_0),
        .mem_aw_payload_qos             (ddr_inst_AWQOS_0),
        .mem_aw_payload_prot            (),

        .mem_w_valid                    (ddr_inst_WVALID_0),
        .mem_w_ready                    (ddr_inst_WREADY_0),
        .mem_w_payload_data             (ddr_inst_WDATA_0),
        .mem_w_payload_strb             (ddr_inst_WSTRB_0),
        .mem_w_payload_last             (ddr_inst_WLAST_0),

        .mem_b_valid                    (ddr_inst_BVALID_0),
        .mem_b_ready                    (ddr_inst_BREADY_0),
        .mem_b_payload_id               (io_ddrA_b_payload_id_i),
        .mem_b_payload_resp             (ddr_inst_BRESP_0),

        .mem_r_valid                    (ddr_inst_RVALID_0),
        .mem_r_ready                    (ddr_inst_RREADY_0),
        .mem_r_payload_data             (ddr_inst_RDATA_0),
        .mem_r_payload_id               (io_ddrA_r_payload_id_i),
        .mem_r_payload_resp             (ddr_inst_RRESP_0),
        .mem_r_payload_last             (ddr_inst_RLAST_0),

        .system_uart_0_io_txd           (system_uart_0_io_txd),
        .system_uart_0_io_rxd           (system_uart_0_io_rxd),

        .system_spi_0_io_sclk_write     (system_spi_0_io_sclk_write),
        .system_spi_0_io_data_0_writeEnable (system_spi_0_io_data_0_writeEnable),
        .system_spi_0_io_data_0_read    (system_spi_0_io_data_0_read),
        .system_spi_0_io_data_0_write   (system_spi_0_io_data_0_write),
        .system_spi_0_io_data_1_writeEnable (system_spi_0_io_data_1_writeEnable),
        .system_spi_0_io_data_1_read    (system_spi_0_io_data_1_read),
        .system_spi_0_io_data_1_write   (system_spi_0_io_data_1_write),
        .system_spi_0_io_ss             (system_spi_0_io_ss),

        .sd_clk_hi                      (sd_clk_hi),
        .sd_cmd_i                       (sd_cmd_i),
        .sd_cmd_o                       (sd_cmd_o),
        .sd_cmd_oe                      (sd_cmd_oe),
        .sd_dat_i                       (sd_dat_i),
        .sd_dat_o                       (sd_dat_o),
        .sd_dat_oe                      (sd_dat_oe),
        .sd_cd_n                        (sd_cd_n),

        // JTAG USER1 (peri jtag_inst1) -> soc_ti180 RISC-V debug
        .jtagCtrl_tck                   (jtag_inst1_TCK),
        .jtagCtrl_tdi                   (jtag_inst1_TDI),
        .jtagCtrl_tdo                   (jtag_inst1_TDO),
        .jtagCtrl_enable                (jtag_inst1_SEL),
        .jtagCtrl_capture               (jtag_inst1_CAPTURE),
        .jtagCtrl_shift                 (jtag_inst1_SHIFT)
    );

    // jtag_inst2_* (USER2): owned by Efinity LA debug core, do not route in user RTL.

    // Suppress unused-peri warnings for clocks consumed inside DDR / PLL blocks
    wire _unused_pll_sys  = pll_sys_CLKOUT0;
    wire _unused_pll_ddr  = pll_ddr_CLKOUT0;
    wire _unused_axi1_clk = i_axi1_mem_clk;
    wire _unused_clk50    = clk_50M;
    wire _unused_ref_ddr  = i_ref_clk_ddr;

endmodule
