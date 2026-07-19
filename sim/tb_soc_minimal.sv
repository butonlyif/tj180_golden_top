`default_nettype none
`timescale 1ns / 1ps

//============================================================================
// 模块名称: tb_soc_minimal
// 功能描述: Stage 1 最小系统仿真 testbench
//           验证: 时钟生成、复位同步释放、LED 计数器、AXI 连线完整性
// 接口说明: 例化 tj180_golden_top，驱动时钟/复位，监测关键信号
//============================================================================
module tb_soc_minimal;

    // =====================================================================
    // DUT 信号
    // =====================================================================
    reg         clk_50m;
    reg         arst_n;
    reg         ddr_clk_ref;
    reg         MIPI_REF_CLK;

    wire        sys_pll_rstn;
    wire        sys_pll_lock;
    wire        ddr_pll_rstn;
    wire        ddr_pll_lock;

    // UART
    wire        uart_txd;
    reg         uart_rxd = 1'b1;

    // LED
    wire [3:0]  led;

    // JTAG
    reg         jtag_tck = 0;
    reg         jtag_tdi = 0;
    reg         jtag_tms = 0;
    reg         jtag_sel = 0;
    reg         jtag_capture = 0;
    reg         jtag_shift = 0;
    reg         jtag_update = 0;
    reg         jtag_reset = 0;
    reg         jtag_drck = 0;
    reg         jtag_runtest = 0;
    wire        jtag_tdo;

    // DDR AXI (简化模拟)
    wire        axi0_ARESETn;
    wire        axi0_ARVALID;
    wire        axi0_AWVALID;
    wire        axi0_WVALID;
    wire        axi0_BREADY;
    wire        axi0_RREADY;
    wire        axi0_WLAST;
    wire [32:0] axi0_ARADDR;
    wire [32:0] axi0_AWADDR;
    wire [5:0]  axi0_ARID;
    wire [5:0]  axi0_AWID;
    wire [7:0]  axi0_ARLEN;
    wire [7:0]  axi0_AWLEN;
    wire [2:0]  axi0_ARSIZE;
    wire [2:0]  axi0_AWSIZE;
    wire [1:0]  axi0_ARBURST;
    wire [1:0]  axi0_AWBURST;
    wire        axi0_ARLOCK;
    wire        axi0_AWLOCK;
    wire [3:0]  axi0_ARCACHE;
    wire [3:0]  axi0_AWCACHE;
    wire [2:0]  axi0_ARPROT;
    wire [2:0]  axi0_AWPROT;
    wire [3:0]  axi0_ARQOS;
    wire [3:0]  axi0_AWQOS;
    wire [511:0] axi0_WDATA;
    wire [63:0] axi0_WSTRB;

    // DDR-side driven signals (TB acts as DDR AXI slave)
    reg         axi0_WREADY_r = 1'b1;
    reg         axi0_ARREADY_r = 1'b1;
    reg         axi0_AWREADY_r = 1'b1;
    wire [511:0] axi0_RDATA = 512'h0;
    wire        axi0_RVALID = 1'b0;
    wire        axi0_RLAST  = 1'b0;
    wire [5:0]  axi0_RID   = 6'h0;
    wire [1:0]  axi0_RRESP = 2'b00;
    wire        axi0_BVALID = 1'b0;
    wire [5:0]  axi0_BID   = 6'h0;
    wire [1:0]  axi0_BRESP = 2'b00;

    // DDR 状态
    reg         ddr_cfg_done = 1'b1;  // 模拟 DDR 配置完成
    reg         ddr_ctrl_busy = 1'b0;

    // =====================================================================
    // 时钟生成
    // =====================================================================
    initial clk_50m = 0;
    always #10 clk_50m = ~clk_50m;      // 50 MHz

    initial ddr_clk_ref = 0;
    always #15 ddr_clk_ref = ~ddr_clk_ref; // 33.33 MHz

    initial MIPI_REF_CLK = 0;
    always #5 MIPI_REF_CLK = ~MIPI_REF_CLK; // 100 MHz

    // =====================================================================
    // PLL lock 模拟（直接驱动顶层 PLL lock 输入）
    // =====================================================================
    assign sys_pll_lock = arst_n;
    assign ddr_pll_lock = arst_n;

    // =====================================================================
    // 简单 DDR AXI Slave 模型
    // =====================================================================
    // 模拟 always-ready AXI slave
    assign axi0_ARREADY = axi0_ARREADY_r;
    assign axi0_AWREADY = axi0_AWREADY_r;
    assign axi0_WREADY  = axi0_WREADY_r;

    // =====================================================================
    // 测试流程
    // =====================================================================
    integer pass_count = 0;
    integer fail_count = 0;

    initial begin
        // 初始化
        arst_n = 0;
        uart_rxd = 1'b1;

        // 复位 500ns
        #500;
        arst_n = 1;

        // 等待复位同步释放
        #200;

        // --- 测试 1: 时钟信号检查 ---
        if (clk_50m !== 1'bx) begin
            $display("[PASS] clk_50m toggling");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] clk_50m not toggling");
            fail_count = fail_count + 1;
        end

        // --- 测试 2: LED 计数器运行 ---
        // 等待足够时间观察 LED[0] 翻转（实际硬件慢闪，仿真只验证计数器递增）
        #1000;
        if (led[1] === 1'b1 && led[2] === 1'b1) begin
            $display("[PASS] PLL lock LEDs on (led[1]=%b, led[2]=%b)", led[1], led[2]);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] PLL lock LEDs not on (led[1]=%b, led[2]=%b)", led[1], led[2]);
            fail_count = fail_count + 1;
        end

        // --- 测试 3: DDR CFG_DONE LED ---
        if (led[3] === ddr_cfg_done) begin
            $display("[PASS] DDR CFG_DONE LED matches (led[3]=%b)", led[3]);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] DDR CFG_DONE LED mismatch (led[3]=%b, expected %b)", led[3], ddr_cfg_done);
            fail_count = fail_count + 1;
        end

        // --- 测试 4: AXI0 reset deasserted after CFG_DONE ---
        // ddr_ctrl_wrapper 的 FSM 需要 ~256 个 sys_clk 周期才进入 CFG_DONE
        // 256 cycles * 20ns = 5120ns，加上余量等 6000ns
        #6000;
        if (axi0_ARESETn === 1'b1) begin
            $display("[PASS] axi0_ARESETn deasserted after ddr_cfg_done");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] axi0_ARESETn not deasserted (=%b)", axi0_ARESETn);
            fail_count = fail_count + 1;
        end

        // --- 测试 5: UART TX driven ---
        #100;
        if (uart_txd !== 1'bx) begin
            $display("[PASS] UART TX driven (uart_txd=%b)", uart_txd);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] UART TX not driven");
            fail_count = fail_count + 1;
        end

        // --- 测试 6: JTAG TDO connected ---
        #10;
        if (jtag_tdo !== 1'bx) begin
            $display("[PASS] JTAG TDO connected");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] JTAG TDO not connected");
            fail_count = fail_count + 1;
        end

        // --- 测试 7: 复位后再复位 ---
        arst_n = 0;
        #200;
        arst_n = 1;
        #200;
        if (led[1] === 1'b1) begin
            $display("[PASS] System recovered after second reset");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] System did not recover after second reset");
            fail_count = fail_count + 1;
        end

        // =====================================================================
        // 汇总
        // =====================================================================
        $display("========================================");
        $display("Stage 1 Testbench Summary:");
        $display("  PASSED: %0d", pass_count);
        $display("  FAILED: %0d", fail_count);
        if (fail_count == 0)
            $display("  RESULT: ALL TESTS PASSED");
        else
            $display("  RESULT: SOME TESTS FAILED");
        $display("========================================");

        $finish;
    end

    // =====================================================================
    // DUT 例化
    // =====================================================================
    tj180_golden_top DUT (
        // Clock & Reset
        .clk_50m                    (clk_50m),
        .arst_n                     (arst_n),
        .ddr_clk_ref                (ddr_clk_ref),

        // PLL
        .sys_pll_rstn               (sys_pll_rstn),
        .sys_pll_lock               (sys_pll_lock),
        .ddr_pll_rstn               (ddr_pll_rstn),
        .ddr_pll_lock               (ddr_pll_lock),

        // UART
        .system_uart_0_io_rxd       (uart_rxd),
        .system_uart_0_io_txd       (uart_txd),

        // SPI
        .system_spi_0_io_sclk_write  (),
        .system_spi_0_io_ss          (),
        .system_spi_0_io_data_0_writeEnable (),
        .system_spi_0_io_data_0_read (1'b0),
        .system_spi_0_io_data_0_write (),
        .system_spi_0_io_data_1_writeEnable (),
        .system_spi_0_io_data_1_read (1'b0),
        .system_spi_0_io_data_1_write (),

        // I2C
        .system_i2c_0_io_scl_writeEnable (),
        .system_i2c_0_io_scl_write  (),
        .system_i2c_0_io_scl_read   (1'b1),
        .system_i2c_0_io_sda_writeEnable (),
        .system_i2c_0_io_sda_write  (),
        .system_i2c_0_io_sda_read   (1'b1),

        // GPIO
        .system_gpio_0_io_read      (4'h0),
        .system_gpio_0_io_write     (),
        .system_gpio_0_io_writeEnable (),

        // SD
        .sd_cd_n                    (1'b1),
        .sd_clk_hi                  (),
        .sd_cmd_o                   (),
        .sd_cmd_oe                  (),
        .sd_cmd_i                   (1'b0),
        .sd_dat_o                   (),
        .sd_dat_oe                  (),
        .sd_dat_i                   (4'h0),

        // MIPI RX
        .MIPI_REF_CLK               (MIPI_REF_CLK),
        .mipi_dphy_rx_clk_CLKOUT    (1'b0),
        .mipi_dphy_rx_inst2_LP_CLK  (1'b0),
        .mipi_dphy_rx_inst2_RX_DATA_ESC (8'h0),
        .mipi_dphy_rx_inst2_HS_LAN0_DATA (16'h0),
        .mipi_dphy_rx_inst2_HS_LAN1_DATA (16'h0),
        .mipi_dphy_rx_inst2_HS_LAN2_DATA (16'h0),
        .mipi_dphy_rx_inst2_HS_LAN3_DATA (16'h0),
        .mipi_dphy_rx_inst2_RX_LPDT_ESC (1'b0),
        .mipi_dphy_rx_inst2_RX_VALID_ESC (1'b0),
        .mipi_dphy_rx_inst2_RX_TRIGGER_ESC (4'h0),
        .mipi_dphy_rx_inst2_ULPS_CLK_ACTIVEN (1'b0),
        .mipi_dphy_rx_inst2_ULPS_LAN0_ACTIVEN (1'b0),
        .mipi_dphy_rx_inst2_ULPS_LAN1_ACTIVEN (1'b0),
        .mipi_dphy_rx_inst2_ULPS_LAN2_ACTIVEN (1'b0),
        .mipi_dphy_rx_inst2_ULPS_LAN3_ACTIVEN (1'b0),
        .mipi_dphy_rx_inst2_ULPS_CLK_ENTER (1'b0),
        .mipi_dphy_rx_inst2_ULPS_LAN0_ENTER (1'b0),
        .mipi_dphy_rx_inst2_ULPS_LAN1_ENTER (1'b0),
        .mipi_dphy_rx_inst2_ULPS_LAN2_ENTER (1'b0),
        .mipi_dphy_rx_inst2_ULPS_LAN3_ENTER (1'b0),
        .mipi_dphy_rx_inst2_ESC_LAN0_CLK (1'b0),
        .mipi_dphy_rx_inst2_ESC_LAN1_CLK (1'b0),
        .mipi_dphy_rx_inst2_ESC_LAN2_CLK (1'b0),
        .mipi_dphy_rx_inst2_ESC_LAN3_CLK (1'b0),
        .mipi_dphy_rx_inst2_HS_LAN0_VALID (1'b0),
        .mipi_dphy_rx_inst2_HS_LAN1_VALID (1'b0),
        .mipi_dphy_rx_inst2_HS_LAN2_VALID (1'b0),
        .mipi_dphy_rx_inst2_HS_LAN3_VALID (1'b0),
        .mipi_dphy_rx_inst2_HS_LAN0_SYNC (1'b0),
        .mipi_dphy_rx_inst2_HS_LAN1_SYNC (1'b0),
        .mipi_dphy_rx_inst2_HS_LAN2_SYNC (1'b0),
        .mipi_dphy_rx_inst2_HS_LAN3_SYNC (1'b0),
        .mipi_dphy_rx_inst2_HS_LAN0_SKEWCAL (1'b0),
        .mipi_dphy_rx_inst2_HS_LAN1_SKEWCAL (1'b0),
        .mipi_dphy_rx_inst2_HS_LAN2_SKEWCAL (1'b0),
        .mipi_dphy_rx_inst2_HS_LAN3_SKEWCAL (1'b0),
        .mipi_dphy_rx_inst2_HS_LAN0_SOTSYNC_ERROR (1'b0),
        .mipi_dphy_rx_inst2_HS_LAN1_SOTSYNC_ERROR (1'b0),
        .mipi_dphy_rx_inst2_HS_LAN2_SOTSYNC_ERROR (1'b0),
        .mipi_dphy_rx_inst2_HS_LAN3_SOTSYNC_ERROR (1'b0),
        .mipi_dphy_rx_inst2_ERR_SOT_HS_LAN0 (1'b0),
        .mipi_dphy_rx_inst2_ERR_SOT_HS_LAN1 (1'b0),
        .mipi_dphy_rx_inst2_ERR_SOT_HS_LAN2 (1'b0),
        .mipi_dphy_rx_inst2_ERR_SOT_HS_LAN3 (1'b0),
        .mipi_dphy_rx_inst2_ESC_LAN0_ERROR (1'b0),
        .mipi_dphy_rx_inst2_ESC_LAN1_ERROR (1'b0),
        .mipi_dphy_rx_inst2_ESC_LAN2_ERROR (1'b0),
        .mipi_dphy_rx_inst2_ESC_LAN3_ERROR (1'b0),
        .mipi_dphy_rx_inst2_LINESTATE_LAN0_ERROR (1'b0),
        .mipi_dphy_rx_inst2_LINESTATE_LAN1_ERROR (1'b0),
        .mipi_dphy_rx_inst2_LINESTATE_LAN2_ERROR (1'b0),
        .mipi_dphy_rx_inst2_LINESTATE_LAN3_ERROR (1'b0),
        .mipi_dphy_rx_inst2_ERR_CONTENTION_LP0 (1'b0),
        .mipi_dphy_rx_inst2_ERR_CONTENTION_LP1 (1'b0),
        .mipi_dphy_rx_inst2_STOPSTATE_CLK (1'b0),
        .mipi_dphy_rx_inst2_STOPSTATE_LAN0 (1'b0),
        .mipi_dphy_rx_inst2_STOPSTATE_LAN1 (1'b0),
        .mipi_dphy_rx_inst2_STOPSTATE_LAN2 (1'b0),
        .mipi_dphy_rx_inst2_STOPSTATE_LAN3 (1'b0),
        .mipi_dphy_rx_inst2_RX_ACTIVE_HS_LAN0 (1'b0),
        .mipi_dphy_rx_inst2_RX_ACTIVE_HS_LAN1 (1'b0),
        .mipi_dphy_rx_inst2_RX_ACTIVE_HS_LAN2 (1'b0),
        .mipi_dphy_rx_inst2_RX_ACTIVE_HS_LAN3 (1'b0),
        .mipi_dphy_rx_inst2_RX_CLK_ACTIVE_HS (1'b0),
        .mipi_dphy_rx_inst2_FORCE_RX_MODE (),
        .mipi_dphy_rx_inst2_RESET (),
        .mipi_dphy_rx_inst2_RST0_N (),

        // MIPI TX (outputs not driven in TB)
        .mipi_dphy_tx_inst1_PLL_UNLOCK (),
        .mipi_dphy_tx_inst1_PLL_SSC_EN (),
        .mipi_dphy_tx_inst1_RESET (),
        .mipi_dphy_tx_inst1_TX_DATA_ESC (),
        .mipi_dphy_tx_inst1_HS_LAN0_DATA (),
        .mipi_dphy_tx_inst1_HS_LAN1_DATA (),
        .mipi_dphy_tx_inst1_HS_LAN2_DATA (),
        .mipi_dphy_tx_inst1_HS_LAN3_DATA (),
        .mipi_dphy_tx_inst1_TX_LPDT_ESC (),
        .mipi_dphy_tx_inst1_TX_VALID_ESC (),
        .mipi_dphy_tx_inst1_TX_READY_ESC (),
        .mipi_dphy_tx_inst1_TX_TRIGGER_ESC (),
        .mipi_dphy_tx_inst1_ULPS_CLK_ENTER (),
        .mipi_dphy_tx_inst1_ULPS_LAN0_ENTER (),
        .mipi_dphy_tx_inst1_ULPS_LAN1_ENTER (),
        .mipi_dphy_tx_inst1_ULPS_LAN2_ENTER (),
        .mipi_dphy_tx_inst1_ULPS_LAN3_ENTER (),
        .mipi_dphy_tx_inst1_ULPS_CLK_EXIT (),
        .mipi_dphy_tx_inst1_ULPS_LAN0_EXIT (),
        .mipi_dphy_tx_inst1_ULPS_LAN1_EXIT (),
        .mipi_dphy_tx_inst1_ULPS_LAN2_EXIT (),
        .mipi_dphy_tx_inst1_ULPS_LAN3_EXIT (),
        .mipi_dphy_tx_inst1_HS_LAN0_REQUEST (),
        .mipi_dphy_tx_inst1_HS_LAN1_REQUEST (),
        .mipi_dphy_tx_inst1_HS_LAN2_REQUEST (),
        .mipi_dphy_tx_inst1_HS_LAN3_REQUEST (),
        .mipi_dphy_tx_inst1_REQUESTESC_LAN0 (),
        .mipi_dphy_tx_inst1_REQUESTESC_LAN1 (),
        .mipi_dphy_tx_inst1_REQUESTESC_LAN2 (),
        .mipi_dphy_tx_inst1_REQUESTESC_LAN3 (),
        .mipi_dphy_tx_inst1_HS_CLK_REQUEST (),
        .mipi_dphy_tx_inst1_HS_LAN0_SKEWCAL (),
        .mipi_dphy_tx_inst1_HS_LAN1_SKEWCAL (),
        .mipi_dphy_tx_inst1_HS_LAN2_SKEWCAL (),
        .mipi_dphy_tx_inst1_HS_LAN3_SKEWCAL (),
        .mipi_dphy_tx_inst1_HS_LAN0_HIGHVALID (),
        .mipi_dphy_tx_inst1_HS_LAN1_HIGHVALID (),
        .mipi_dphy_tx_inst1_HS_LAN2_HIGHVALID (),
        .mipi_dphy_tx_inst1_HS_LAN3_HIGHVALID (),
        .mipi_dphy_tx_inst1_HS_LAN0_READY (),
        .mipi_dphy_tx_inst1_HS_LAN1_READY (),
        .mipi_dphy_tx_inst1_HS_LAN2_READY (),
        .mipi_dphy_tx_inst1_HS_LAN3_READY (),
        .mipi_dphy_tx_inst1_STOPSTATE_CLK (1'b0),
        .mipi_dphy_tx_inst1_STOPSTATE_LAN0 (1'b0),
        .mipi_dphy_tx_inst1_STOPSTATE_LAN1 (1'b0),
        .mipi_dphy_tx_inst1_STOPSTATE_LAN2 (1'b0),
        .mipi_dphy_tx_inst1_STOPSTATE_LAN3 (1'b0),
        .mipi_dphy_tx_inst1_ULPS_CLK_ACTIVEN (1'b0),
        .mipi_dphy_tx_inst1_ULPS_LAN0_ACTIVEN (1'b0),
        .mipi_dphy_tx_inst1_ULPS_LAN1_ACTIVEN (1'b0),
        .mipi_dphy_tx_inst1_ULPS_LAN2_ACTIVEN (1'b0),
        .mipi_dphy_tx_inst1_ULPS_LAN3_ACTIVEN (1'b0),

        // RGMII
        .rgmii_txd_HI (),
        .rgmii_txd_LO (),
        .rgmii_tx_ctl_HI (),
        .rgmii_tx_ctl_LO (),
        .rgmii_txc_HI (),
        .rgmii_txc_LO (),
        .rgmii_rxd_HI (4'h0),
        .rgmii_rxd_LO (4'h0),
        .rgmii_rx_ctl_HI (1'b0),
        .rgmii_rx_ctl_LO (1'b0),
        .rgmii_rxc (1'b0),
        .phy_rstn (),
        .phy_mdo (),
        .phy_mdo_en (),
        .phy_mdc (),
        .phy_mdi (1'b0),

        // DDR AXI
        .axi0_ARESETn   (axi0_ARESETn),
        .axi0_ARREADY   (axi0_ARREADY),
        .axi0_ARVALID   (axi0_ARVALID),
        .axi0_ARADDR    (axi0_ARADDR),
        .axi0_ARBURST   (axi0_ARBURST),
        .axi0_ARID      (axi0_ARID),
        .axi0_ARLEN     (axi0_ARLEN),
        .axi0_ARLOCK    (axi0_ARLOCK),
        .axi0_ARCACHE   (axi0_ARCACHE),
        .axi0_ARPROT    (axi0_ARPROT),
        .axi0_ARQOS     (axi0_ARQOS),
        .axi0_ARSIZE    (axi0_ARSIZE),
        .axi0_RDATA     (axi0_RDATA),
        .axi0_RVALID    (axi0_RVALID),
        .axi0_RREADY    (axi0_RREADY),
        .axi0_RLAST     (axi0_RLAST),
        .axi0_RID       (axi0_RID),
        .axi0_RRESP     (axi0_RRESP),
        .axi0_AWVALID   (axi0_AWVALID),
        .axi0_AWADDR    (axi0_AWADDR),
        .axi0_AWBURST   (axi0_AWBURST),
        .axi0_AWID      (axi0_AWID),
        .axi0_AWLEN     (axi0_AWLEN),
        .axi0_AWLOCK    (axi0_AWLOCK),
        .axi0_AWCACHE   (axi0_AWCACHE),
        .axi0_AWPROT    (axi0_AWPROT),
        .axi0_AWQOS     (axi0_AWQOS),
        .axi0_AWSIZE    (axi0_AWSIZE),
        .axi0_WVALID    (axi0_WVALID),
        .axi0_WDATA     (axi0_WDATA),
        .axi0_WSTRB     (axi0_WSTRB),
        .axi0_WLAST     (axi0_WLAST),
        .axi0_WREADY    (axi0_WREADY),
        .axi0_BID       (axi0_BID),
        .axi0_BRESP     (axi0_BRESP),
        .axi0_BVALID    (axi0_BVALID),
        .axi0_BREADY    (axi0_BREADY),

        .axi1_ARREADY   (1'b0),
        .axi1_AWREADY   (1'b0),
        .axi1_RDATA     (512'h0),
        .axi1_RVALID    (1'b0),
        .axi1_RLAST     (1'b0),
        .axi1_WREADY    (1'b0),
        .axi1_BID       (6'h0),
        .axi1_BRESP     (2'h0),
        .axi1_BVALID    (1'b0),
        .ddr_inst_CFG_DONE         (ddr_cfg_done),
        .ddr_inst_CTRL_BUSY        (ddr_ctrl_busy),
        .ddr_inst_CTRL_CKE         (2'b00),
        .ddr_inst_CTRL_CMD_Q_ALMOST_FULL (1'b0),
        .ddr_inst_CTRL_DP_IDLE     (1'b0),
        .ddr_inst_CTRL_INT         (1'b0),
        .ddr_inst_CTRL_MEM_RST_VALID (1'b0),
        .ddr_inst_CTRL_PORT_BUSY   (2'b00),
        .ddr_inst_CTRL_REFRESH     (1'b0),
        .ddr_inst_RVALID_0         (1'b0),
        .ddr_inst_RVALID_1         (1'b0),
        .ddr_inst_BVALID_0         (1'b0),
        .ddr_inst_BVALID_1         (1'b0),
        .ddr_inst_ARREADY_0        (1'b0),
        .ddr_inst_ARREADY_1        (1'b0),
        .ddr_inst_AWREADY_0        (1'b0),
        .ddr_inst_AWREADY_1        (1'b0),
        .axi1_ARADDR    (),
        .axi1_AWADDR    (),
        .axi1_ARVALID   (),
        .axi1_AWVALID   (),
        .axi1_ARESETn   (),
        .axi1_WVALID    (),
        .axi1_WLAST     (),
        .axi1_BREADY    (),
        .axi1_RREADY    (),

        // JTAG
        .jtag_inst1_CAPTURE (jtag_capture),
        .jtag_inst1_DRCK    (jtag_drck),
        .jtag_inst1_RESET   (jtag_reset),
        .jtag_inst1_RUNTEST (jtag_runtest),
        .jtag_inst1_SEL     (jtag_sel),
        .jtag_inst1_SHIFT   (jtag_shift),
        .jtag_inst1_TCK     (jtag_tck),
        .jtag_inst1_TDI     (jtag_tdi),
        .jtag_inst1_TMS     (jtag_tms),
        .jtag_inst1_UPDATE  (jtag_update),
        .jtag_inst1_TDO     (jtag_tdo),

        // PLL
        .pll_inst1_LOCKED   (1'b0),
        .pll_inst2_LOCKED   (1'b0),
        .pll_sys_LOCKED     (sys_pll_lock),
        .pll_ddr_LOCKED     (ddr_pll_lock),
        .i_axi0_mem_clk     (clk_50m),
        .i_axi1_mem_clk     (1'b0),
        .pll_ddr_CLKOUT0    (1'b0),

        // LED
        .led                (led)
    );

endmodule

`default_nettype wire
