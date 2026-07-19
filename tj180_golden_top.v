`default_nettype none
`timescale 1ns / 1ps

//============================================================================
// 模块名称: tj180_golden_top
// 功能描述: TJ180A484S Golden Top — Stage 4 集成
//           Stage 1: SoC + DDR + PLL + UART/SPI/I2C/GPIO/JTAG
//           Stage 2: MIPI CSI-2 RX 链路（hard_csi_rx 例化 + APB→AXI-Lite 桥
//                    + DPHY RX 解复位 + IRQ CDC 到 SoC userInterruptA）
//           Stage 3: MIPI CSI-2 TX + RX→TX Pixel 异步 FIFO + Loopback 控制
//                    （hard_csi_tx 例化 + async_pixel_fifo + loopback_ctrl；
//                     DPHY TX 解复位；TX IRQ CDC 到 SoC userInterruptB）
//           Stage 4: RGMII Ethernet MAC (test_tse/TSE IP) + SD Host 总线槽位
//                    （apb_decoder_1to3 拆分 SoC APB 到 CSI RX/TSE MAC/SD 槽；
//                     TSE MAC 直走 RGMII 管脚，无内环回；SD Host 槽位 axilite idle slave 占位）
// 接口说明: 全部外设 IO 端口（与 Efinity Interface Designer peri.xml 对齐）
// 设计约束: sys_clk 100MHz, ddr_clk ~600MHz, clk_byte_HS 来自 DPHY RX,
//           clk_pixel_rx = clk_byte_HS（Stage 2 简化），
//           clk_pixel_tx = clk_byte_hs（Stage 3 简化，后续可由 PLL 生成）
//============================================================================
module tj180_golden_top
(
    //====================================================================
    // Clock & Reset
    //====================================================================
    (* syn_peri_port = 0 *) input  wire        clk_50m,
    (* syn_peri_port = 0 *) input  wire        arst_n,
    (* syn_peri_port = 0 *) input  wire        ddr_clk_ref,

    //====================================================================
    // PLL Lock Signals
    //====================================================================
    (* syn_peri_port = 0 *) output wire        sys_pll_rstn,
    (* syn_peri_port = 0 *) input  wire        sys_pll_lock,
    (* syn_peri_port = 0 *) output wire        ddr_pll_rstn,
    (* syn_peri_port = 0 *) input  wire        ddr_pll_lock,

    //====================================================================
    // UART (System Debug)
    //====================================================================
    (* syn_peri_port = 0 *) input  wire        system_uart_0_io_rxd,
    (* syn_peri_port = 0 *) output wire        system_uart_0_io_txd,

    //====================================================================
    // SPI (Flash/Memory)
    //====================================================================
    (* syn_peri_port = 0 *) output wire        system_spi_0_io_sclk_write,
    (* syn_peri_port = 0 *) output wire        system_spi_0_io_ss,
    (* syn_peri_port = 0 *) output wire        system_spi_0_io_data_0_writeEnable,
    (* syn_peri_port = 0 *) input  wire        system_spi_0_io_data_0_read,
    (* syn_peri_port = 0 *) output wire        system_spi_0_io_data_0_write,
    (* syn_peri_port = 0 *) output wire        system_spi_0_io_data_1_writeEnable,
    (* syn_peri_port = 0 *) input  wire        system_spi_0_io_data_1_read,
    (* syn_peri_port = 0 *) output wire        system_spi_0_io_data_1_write,

    //====================================================================
    // I2C (Sensor Control)
    //====================================================================
    (* syn_peri_port = 0 *) output wire        system_i2c_0_io_scl_writeEnable,
    (* syn_peri_port = 0 *) output wire        system_i2c_0_io_scl_write,
    (* syn_peri_port = 0 *) input  wire        system_i2c_0_io_scl_read,
    (* syn_peri_port = 0 *) output wire        system_i2c_0_io_sda_writeEnable,
    (* syn_peri_port = 0 *) output wire        system_i2c_0_io_sda_write,
    (* syn_peri_port = 0 *) input  wire        system_i2c_0_io_sda_read,

    //====================================================================
    // GPIO
    //====================================================================
    (* syn_peri_port = 0 *) input  wire [3:0]  system_gpio_0_io_read,
    (* syn_peri_port = 0 *) output wire [3:0]  system_gpio_0_io_write,
    (* syn_peri_port = 0 *) output wire [3:0]  system_gpio_0_io_writeEnable,

    //====================================================================
    // SD Card Interface
    //====================================================================
    (* syn_peri_port = 0 *) input  wire        sd_cd_n,
    (* syn_peri_port = 0 *) output wire        sd_clk_hi,
    (* syn_peri_port = 0 *) output wire        sd_cmd_o,
    (* syn_peri_port = 0 *) output wire        sd_cmd_oe,
    (* syn_peri_port = 0 *) input  wire        sd_cmd_i,
    (* syn_peri_port = 0 *) output wire [3:0]  sd_dat_o,
    (* syn_peri_port = 0 *) output wire [3:0]  sd_dat_oe,
    (* syn_peri_port = 0 *) input  wire [3:0]  sd_dat_i,

    //====================================================================
    // MIPI RX (Camera Input) - Stage 2+
    //====================================================================
    (* syn_peri_port = 0 *) input  wire        MIPI_REF_CLK,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_clk_CLKOUT,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_LP_CLK,
    (* syn_peri_port = 0 *) input  wire [7:0]  mipi_dphy_rx_inst2_RX_DATA_ESC,
    (* syn_peri_port = 0 *) input  wire [15:0] mipi_dphy_rx_inst2_HS_LAN0_DATA,
    (* syn_peri_port = 0 *) input  wire [15:0] mipi_dphy_rx_inst2_HS_LAN1_DATA,
    (* syn_peri_port = 0 *) input  wire [15:0] mipi_dphy_rx_inst2_HS_LAN2_DATA,
    (* syn_peri_port = 0 *) input  wire [15:0] mipi_dphy_rx_inst2_HS_LAN3_DATA,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_RX_LPDT_ESC,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_RX_VALID_ESC,
    (* syn_peri_port = 0 *) input  wire [3:0]  mipi_dphy_rx_inst2_RX_TRIGGER_ESC,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_ULPS_CLK_ACTIVEN,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_ULPS_LAN0_ACTIVEN,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_ULPS_LAN1_ACTIVEN,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_ULPS_LAN2_ACTIVEN,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_ULPS_LAN3_ACTIVEN,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_ULPS_CLK_ENTER,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_ULPS_LAN0_ENTER,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_ULPS_LAN1_ENTER,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_ULPS_LAN2_ENTER,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_ULPS_LAN3_ENTER,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_ESC_LAN0_CLK,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_ESC_LAN1_CLK,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_ESC_LAN2_CLK,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_ESC_LAN3_CLK,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_HS_LAN0_VALID,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_HS_LAN1_VALID,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_HS_LAN2_VALID,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_HS_LAN3_VALID,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_HS_LAN0_SYNC,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_HS_LAN1_SYNC,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_HS_LAN2_SYNC,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_HS_LAN3_SYNC,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_HS_LAN0_SKEWCAL,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_HS_LAN1_SKEWCAL,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_HS_LAN2_SKEWCAL,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_HS_LAN3_SKEWCAL,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_HS_LAN0_SOTSYNC_ERROR,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_HS_LAN1_SOTSYNC_ERROR,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_HS_LAN2_SOTSYNC_ERROR,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_HS_LAN3_SOTSYNC_ERROR,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_ERR_SOT_HS_LAN0,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_ERR_SOT_HS_LAN1,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_ERR_SOT_HS_LAN2,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_ERR_SOT_HS_LAN3,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_ESC_LAN0_ERROR,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_ESC_LAN1_ERROR,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_ESC_LAN2_ERROR,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_ESC_LAN3_ERROR,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_LINESTATE_LAN0_ERROR,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_LINESTATE_LAN1_ERROR,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_LINESTATE_LAN2_ERROR,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_LINESTATE_LAN3_ERROR,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_ERR_CONTENTION_LP0,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_ERR_CONTENTION_LP1,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_STOPSTATE_CLK,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_STOPSTATE_LAN0,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_STOPSTATE_LAN1,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_STOPSTATE_LAN2,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_STOPSTATE_LAN3,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_RX_ACTIVE_HS_LAN0,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_RX_ACTIVE_HS_LAN1,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_RX_ACTIVE_HS_LAN2,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_RX_ACTIVE_HS_LAN3,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_rx_inst2_RX_CLK_ACTIVE_HS,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_rx_inst2_FORCE_RX_MODE,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_rx_inst2_RESET,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_rx_inst2_RST0_N,

    //====================================================================
    // MIPI TX (Video Output) - Stage 3+
    //====================================================================
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_PLL_UNLOCK,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_PLL_SSC_EN,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_RESET,
    (* syn_peri_port = 0 *) output wire [7:0]  mipi_dphy_tx_inst1_TX_DATA_ESC,
    (* syn_peri_port = 0 *) output wire [15:0] mipi_dphy_tx_inst1_HS_LAN0_DATA,
    (* syn_peri_port = 0 *) output wire [15:0] mipi_dphy_tx_inst1_HS_LAN1_DATA,
    (* syn_peri_port = 0 *) output wire [15:0] mipi_dphy_tx_inst1_HS_LAN2_DATA,
    (* syn_peri_port = 0 *) output wire [15:0] mipi_dphy_tx_inst1_HS_LAN3_DATA,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_TX_LPDT_ESC,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_TX_VALID_ESC,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_TX_READY_ESC,
    (* syn_peri_port = 0 *) output wire [3:0]  mipi_dphy_tx_inst1_TX_TRIGGER_ESC,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_ULPS_CLK_ENTER,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_ULPS_LAN0_ENTER,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_ULPS_LAN1_ENTER,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_ULPS_LAN2_ENTER,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_ULPS_LAN3_ENTER,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_ULPS_CLK_EXIT,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_ULPS_LAN0_EXIT,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_ULPS_LAN1_EXIT,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_ULPS_LAN2_EXIT,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_ULPS_LAN3_EXIT,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_HS_LAN0_REQUEST,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_HS_LAN1_REQUEST,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_HS_LAN2_REQUEST,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_HS_LAN3_REQUEST,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_REQUESTESC_LAN0,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_REQUESTESC_LAN1,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_REQUESTESC_LAN2,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_REQUESTESC_LAN3,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_HS_CLK_REQUEST,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_HS_LAN0_SKEWCAL,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_HS_LAN1_SKEWCAL,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_HS_LAN2_SKEWCAL,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_HS_LAN3_SKEWCAL,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_HS_LAN0_HIGHVALID,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_HS_LAN1_HIGHVALID,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_HS_LAN2_HIGHVALID,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_HS_LAN3_HIGHVALID,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_HS_LAN0_READY,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_HS_LAN1_READY,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_HS_LAN2_READY,
    (* syn_peri_port = 0 *) output wire        mipi_dphy_tx_inst1_HS_LAN3_READY,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_tx_inst1_STOPSTATE_CLK,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_tx_inst1_STOPSTATE_LAN0,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_tx_inst1_STOPSTATE_LAN1,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_tx_inst1_STOPSTATE_LAN2,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_tx_inst1_STOPSTATE_LAN3,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_tx_inst1_ULPS_CLK_ACTIVEN,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_tx_inst1_ULPS_LAN0_ACTIVEN,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_tx_inst1_ULPS_LAN1_ACTIVEN,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_tx_inst1_ULPS_LAN2_ACTIVEN,
    (* syn_peri_port = 0 *) input  wire        mipi_dphy_tx_inst1_ULPS_LAN3_ACTIVEN,

    //====================================================================
    // RGMII Ethernet (Stage 4+)
    //====================================================================
    (* syn_peri_port = 0 *) output wire [3:0]  rgmii_txd_HI,
    (* syn_peri_port = 0 *) output wire [3:0]  rgmii_txd_LO,
    (* syn_peri_port = 0 *) output wire        rgmii_tx_ctl_HI,
    (* syn_peri_port = 0 *) output wire        rgmii_tx_ctl_LO,
    (* syn_peri_port = 0 *) output wire        rgmii_txc_HI,
    (* syn_peri_port = 0 *) output wire        rgmii_txc_LO,
    (* syn_peri_port = 0 *) input  wire [3:0]  rgmii_rxd_HI,
    (* syn_peri_port = 0 *) input  wire [3:0]  rgmii_rxd_LO,
    (* syn_peri_port = 0 *) input  wire        rgmii_rx_ctl_HI,
    (* syn_peri_port = 0 *) input  wire        rgmii_rx_ctl_LO,
    (* syn_peri_port = 0 *) input  wire        rgmii_rxc,
    (* syn_peri_port = 0 *) output wire        phy_rstn,
    (* syn_peri_port = 0 *) output wire        phy_mdo,
    (* syn_peri_port = 0 *) output wire        phy_mdo_en,
    (* syn_peri_port = 0 *) output wire        phy_mdc,
    (* syn_peri_port = 0 *) input  wire        phy_mdi,

    //====================================================================
    // DDR AXI Interface (�?IP 连接)
    //====================================================================
    (* syn_peri_port = 0 *) output wire        axi0_ARESETn,
    (* syn_peri_port = 0 *) input  wire        axi0_ARREADY,
    (* syn_peri_port = 0 *) output wire        axi0_ARVALID,
    (* syn_peri_port = 0 *) output wire [32:0] axi0_ARADDR,
    (* syn_peri_port = 0 *) output wire [1:0]  axi0_ARBURST,
    (* syn_peri_port = 0 *) output wire [5:0]  axi0_ARID,
    (* syn_peri_port = 0 *) output wire [7:0]  axi0_ARLEN,
    (* syn_peri_port = 0 *) output wire        axi0_ARLOCK,
    (* syn_peri_port = 0 *) output wire [3:0]  axi0_ARCACHE,
    (* syn_peri_port = 0 *) output wire [2:0]  axi0_ARPROT,
    (* syn_peri_port = 0 *) output wire [3:0]  axi0_ARQOS,
    (* syn_peri_port = 0 *) output wire [2:0]  axi0_ARSIZE,
    (* syn_peri_port = 0 *) input  wire [511:0] axi0_RDATA,
    (* syn_peri_port = 0 *) input  wire        axi0_RVALID,
    (* syn_peri_port = 0 *) output wire        axi0_RREADY,
    (* syn_peri_port = 0 *) input  wire        axi0_RLAST,
    (* syn_peri_port = 0 *) input  wire [5:0]  axi0_RID,
    (* syn_peri_port = 0 *) input  wire [1:0]  axi0_RRESP,
    (* syn_peri_port = 0 *) input  wire        axi0_AWREADY,
    (* syn_peri_port = 0 *) output wire        axi0_AWVALID,
    (* syn_peri_port = 0 *) output wire [32:0] axi0_AWADDR,
    (* syn_peri_port = 0 *) output wire [1:0]  axi0_AWBURST,
    (* syn_peri_port = 0 *) output wire [5:0]  axi0_AWID,
    (* syn_peri_port = 0 *) output wire [7:0]  axi0_AWLEN,
    (* syn_peri_port = 0 *) output wire        axi0_AWLOCK,
    (* syn_peri_port = 0 *) output wire [3:0]  axi0_AWCACHE,
    (* syn_peri_port = 0 *) output wire [2:0]  axi0_AWPROT,
    (* syn_peri_port = 0 *) output wire [3:0]  axi0_AWQOS,
    (* syn_peri_port = 0 *) output wire [2:0]  axi0_AWSIZE,
    (* syn_peri_port = 0 *) output wire        axi0_WVALID,
    (* syn_peri_port = 0 *) output wire [511:0] axi0_WDATA,
    (* syn_peri_port = 0 *) output wire [63:0] axi0_WSTRB,
    (* syn_peri_port = 0 *) output wire        axi0_WLAST,
    (* syn_peri_port = 0 *) input  wire        axi0_WREADY,
    (* syn_peri_port = 0 *) input  wire [5:0]  axi0_BID,
    (* syn_peri_port = 0 *) input  wire [1:0]  axi0_BRESP,
    (* syn_peri_port = 0 *) input  wire        axi0_BVALID,
    (* syn_peri_port = 0 *) output wire        axi0_BREADY,

    // AXI1 (未使用端�?�?Stage 4+)
    (* syn_peri_port = 0 *) input  wire        axi1_ARREADY,
    (* syn_peri_port = 0 *) input  wire        axi1_AWREADY,
    (* syn_peri_port = 0 *) input  wire [511:0] axi1_RDATA,
    (* syn_peri_port = 0 *) input  wire        axi1_RVALID,
    (* syn_peri_port = 0 *) input  wire        axi1_RLAST,
    (* syn_peri_port = 0 *) input  wire        axi1_WREADY,
    (* syn_peri_port = 0 *) input  wire [5:0]  axi1_BID,
    (* syn_peri_port = 0 *) input  wire [1:0]  axi1_BRESP,
    (* syn_peri_port = 0 *) input  wire        axi1_BVALID,
    (* syn_peri_port = 0 *) input  wire        ddr_inst_CFG_DONE,
    (* syn_peri_port = 0 *) input  wire        ddr_inst_CTRL_BUSY,
    (* syn_peri_port = 0 *) input  wire [1:0]  ddr_inst_CTRL_CKE,
    (* syn_peri_port = 0 *) input  wire        ddr_inst_CTRL_CMD_Q_ALMOST_FULL,
    (* syn_peri_port = 0 *) input  wire        ddr_inst_CTRL_DP_IDLE,
    (* syn_peri_port = 0 *) input  wire        ddr_inst_CTRL_INT,
    (* syn_peri_port = 0 *) input  wire        ddr_inst_CTRL_MEM_RST_VALID,
    (* syn_peri_port = 0 *) input  wire [1:0]  ddr_inst_CTRL_PORT_BUSY,
    (* syn_peri_port = 0 *) input  wire        ddr_inst_CTRL_REFRESH,
    (* syn_peri_port = 0 *) input  wire        ddr_inst_RVALID_0,
    (* syn_peri_port = 0 *) input  wire        ddr_inst_RVALID_1,
    (* syn_peri_port = 0 *) input  wire        ddr_inst_BVALID_0,
    (* syn_peri_port = 0 *) input  wire        ddr_inst_BVALID_1,
    (* syn_peri_port = 0 *) input  wire        ddr_inst_ARREADY_0,
    (* syn_peri_port = 0 *) input  wire        ddr_inst_ARREADY_1,
    (* syn_peri_port = 0 *) input  wire        ddr_inst_AWREADY_0,
    (* syn_peri_port = 0 *) input  wire        ddr_inst_AWREADY_1,
    (* syn_peri_port = 0 *) output wire [32:0] axi1_ARADDR,
    (* syn_peri_port = 0 *) output wire [32:0] axi1_AWADDR,
    (* syn_peri_port = 0 *) output wire        axi1_ARVALID,
    (* syn_peri_port = 0 *) output wire        axi1_AWVALID,
    (* syn_peri_port = 0 *) output wire        axi1_ARESETn,
    (* syn_peri_port = 0 *) output wire        axi1_WVALID,
    (* syn_peri_port = 0 *) output wire        axi1_WLAST,
    (* syn_peri_port = 0 *) output wire        axi1_BREADY,
    (* syn_peri_port = 0 *) output wire        axi1_RREADY,

    //====================================================================
    // JTAG Debug Interface
    //====================================================================
    (* syn_peri_port = 0 *) input  wire        jtag_inst1_CAPTURE,
    (* syn_peri_port = 0 *) input  wire        jtag_inst1_DRCK,
    (* syn_peri_port = 0 *) input  wire        jtag_inst1_RESET,
    (* syn_peri_port = 0 *) input  wire        jtag_inst1_RUNTEST,
    (* syn_peri_port = 0 *) input  wire        jtag_inst1_SEL,
    (* syn_peri_port = 0 *) input  wire        jtag_inst1_SHIFT,
    (* syn_peri_port = 0 *) input  wire        jtag_inst1_TCK,
    (* syn_peri_port = 0 *) input  wire        jtag_inst1_TDI,
    (* syn_peri_port = 0 *) input  wire        jtag_inst1_TMS,
    (* syn_peri_port = 0 *) input  wire        jtag_inst1_UPDATE,
    (* syn_peri_port = 0 *) output wire        jtag_inst1_TDO,

    //====================================================================
    // Internal Clocks (from PLLs)
    //====================================================================
    (* syn_peri_port = 0 *) input  wire        pll_inst1_LOCKED,
    (* syn_peri_port = 0 *) input  wire        pll_inst2_LOCKED,
    (* syn_peri_port = 0 *) input  wire        pll_sys_LOCKED,
    (* syn_peri_port = 0 *) input  wire        pll_ddr_LOCKED,
    (* syn_peri_port = 0 *) input  wire        i_axi0_mem_clk,
    (* syn_peri_port = 0 *) input  wire        i_axi1_mem_clk,
    (* syn_peri_port = 0 *) input  wire        pll_ddr_CLKOUT0,
    // 2026-07-19 P0/4K60: pll_sys_CLKOUT0 = 真 100 MHz sys_clk 源（替代 wrapper clk_50m 穿透）
    (* syn_peri_port = 0 *) input  wire        pll_sys_CLKOUT0,
    // 2026-07-19 Pixel PLL: 200 MHz pixel 时钟源（4K60 YUV422 余量 60%）
    (* syn_peri_port = 0 *) input  wire        pll_pixel_CLKOUT0,
    (* syn_peri_port = 0 *) input  wire        pll_pixel_LOCKED,

    //====================================================================
    // LED Outputs
    //====================================================================
    (* syn_peri_port = 0 *) output wire [3:0]  led
);

    //====================================================================
    // 内部连线
    //====================================================================

    // -- 时钟 --
    wire sys_clk;
    wire ddr_clk;

    // -- 全局复位 --
    wire reset_n_global;   // 全局复位（低有效），= arst_n & pll_lock
    // 内部 PLL lock（来自 wrapper 的 lock_sync 同步链）：
    //   peri.xml 未配置 PLL 硬块时，外部 sys_pll_lock/ddr_pll_lock 输入悬空
    //   （综合 tied 0），不能直接用于复位公式。改用 wrapper 内部 lock，
    //   wrapper 当前同步 1'b1（穿透 PLL 模式），等价于 arst_n 同步释放。
    //   一旦 Interface Designer 配置真 PLL，wrapper 内 lock_sync 同步真 LOCKED
    //   信号，此公式自动正确，无需再改顶层。
    wire sys_pll_lock_int; // pll_sys_wrapper pll_locked_o
    wire ddr_pll_lock_int; // pll_ddr_wrapper pll_locked_o
    wire soc_arst;         // SoC 高有效复�?
    // -- 域内同步复位 --
    wire sys_rst_n;
    wire ddr_rst_n;

    // -- SoC AXI-A 总线 --
    wire [31:0] soc_axi_awaddr;
    wire [7:0]  soc_axi_awid;
    wire [7:0]  soc_axi_awlen;
    wire [2:0]  soc_axi_awsize;
    wire [1:0]  soc_axi_awburst;
    wire        soc_axi_awlock;
    wire [3:0]  soc_axi_awcache;
    wire [3:0]  soc_axi_awqos;
    wire [2:0]  soc_axi_awprot;
    wire [3:0]  soc_axi_awregion;
    wire        soc_axi_awvalid;
    wire        soc_axi_awready;
    wire        soc_axi_wvalid;
    wire [31:0] soc_axi_wdata;
    wire [3:0]  soc_axi_wstrb;
    wire        soc_axi_wlast;
    wire        soc_axi_wready;
    wire        soc_axi_bvalid;
    wire        soc_axi_bready;
    wire [7:0]  soc_axi_bid;
    wire [1:0]  soc_axi_bresp;
    wire        soc_axi_arvalid;
    wire [31:0] soc_axi_araddr;
    wire [7:0]  soc_axi_arid;
    wire [7:0]  soc_axi_arlen;
    wire [2:0]  soc_axi_arsize;
    wire [1:0]  soc_axi_arburst;
    wire        soc_axi_arlock;
    wire [3:0]  soc_axi_arcache;
    wire [3:0]  soc_axi_arqos;
    wire [2:0]  soc_axi_arprot;
    wire [3:0]  soc_axi_arregion;
    wire        soc_axi_arready;
    wire        soc_axi_rvalid;
    wire        soc_axi_rready;
    wire [31:0] soc_axi_rdata;
    wire [7:0]  soc_axi_rid;
    wire [1:0]  soc_axi_rresp;
    wire        soc_axi_rlast;

    // -- SoC 其他 --
    wire        soc_sys_reset;
    wire [15:0] soc_apb_paddr;
    wire        soc_apb_penable;
    wire        soc_apb_psel;
    wire        soc_apb_pwrite;
    wire [31:0] soc_apb_pwdata;
    wire [31:0] soc_apb_prdata;     // Stage 2: 从 CSI RX 经 APB 桥返回
    wire        soc_apb_pready;      // Stage 2: 从 CSI RX 经 APB 桥返回
    wire        soc_apb_pslverror;   // Stage 2: 从 CSI RX 经 APB 桥返回

    // -- DDR 配置 --
    wire        soc_mem_reset;

    // -- SPI data 2/3 (SoC 有但顶层未引脚) --
    wire        spi_data_2_write;
    wire        spi_data_2_writeEnable;
    wire        spi_data_3_write;
    wire        spi_data_3_writeEnable;

    //==================================================================
    // Stage 2: MIPI CSI-2 RX 内部总线
    //==================================================================
    // -- 时钟 --
    wire        clk_byte_hs;        // = mipi_dphy_rx_clk_CLKOUT（DPHY 输出）
    wire        clk_pixel_rx;       // Stage 2: = clk_byte_hs（简化）

    // -- 域内同步复位 --
    wire        byte_hs_rst_n;
    wire        pixel_rst_n;

    // -- APB → AXI-Lite 桥（sys_clk 域） --
    wire [5:0]  csi_axi_awaddr;
    wire        csi_axi_awvalid;
    wire        csi_axi_awready;
    wire [31:0] csi_axi_wdata;
    wire        csi_axi_wvalid;
    wire        csi_axi_wready;
    wire        csi_axi_bvalid;
    wire        csi_axi_bready;
    wire [5:0]  csi_axi_araddr;
    wire        csi_axi_arvalid;
    wire        csi_axi_arready;
    wire [31:0] csi_axi_rdata;
    wire        csi_axi_rvalid;
    wire        csi_axi_rready;

    // -- CSI RX 输出 (pixel 域) --
    wire        csi_pixel_valid;   // pixel 域
    wire [63:0] csi_pixel_data;
    wire [3:0]  csi_pixel_per_clk;
    wire [5:0]  csi_datatype;
    wire [15:0] csi_word_count;
    wire [15:0] csi_shortpkt;
    wire [1:0]  csi_vc;
    wire [1:0]  csi_vcx;
    wire        csi_vsync_vc0;
    wire        csi_hsync_vc0;
    wire        csi_irq_raw;       // pixel 域原始 IRQ

    // -- IRQ CDC：pixel → sys_clk --
    wire        csi_irq_sys;

    //==================================================================
    // Stage 3: MIPI CSI-2 TX 链路内部总线
    //==================================================================
    // -- TX 时钟 / 复位（Stage 3 简化：与 RX byte_hs 共源） --
    wire        clk_pixel_tx;       // = clk_byte_hs（Stage 3 简化）
    wire        pixel_tx_rst_n;

    // -- APB → AXI-Lite 桥（sys_clk 域） → CSI TX 寄存器 --
    wire [5:0]  ctxi_axi_awaddr;
    wire        ctxi_axi_awvalid;
    wire        ctxi_axi_awready;
    wire [31:0] ctxi_axi_wdata;
    wire        ctxi_axi_wvalid;
    wire        ctxi_axi_wready;
    wire        ctxi_axi_bvalid;
    wire        ctxi_axi_bready;
    wire [5:0]  ctxi_axi_araddr;
    wire        ctxi_axi_arvalid;
    wire        ctxi_axi_arready;
    wire [31:0] ctxi_axi_rdata;
    wire        ctxi_axi_rvalid;
    wire        ctxi_axi_rready;

    // -- SoC APB Slave 1 (Stage 3: 经第二组 APB→AXI-Lite 桥接 CSI TX) --
    // 注：SoC wrapper 当前仅暴露 APB Slave 0；本阶段先用一组共享或预留，
    //     寄存器配置可在 Stage 4 通过 SoC AXI 总线扩展或 APB Slave 1 接入。
    //     为推进 Stage 3 编译，此处将 CSI TX 的 AXI-Lite 暂时接成
    //     "主机不发起"的安全默认，由软件后续通过另一通道配置。
    //     （见 §4c 处的 ctxi_axi_*_valid = 1'b0 注释）

    // -- async_pixel_fifo (RX pixel 域 → TX pixel 域) --
    wire        fifo_wr_en;
    wire [63:0] fifo_wr_data;
    wire [7:0]  fifo_wr_side;
    wire        fifo_wr_full;
    wire [11:0] fifo_wr_level;
    wire        fifo_rd_en;
    wire [63:0] fifo_rd_data;
    wire [7:0]  fifo_rd_side;
    wire        fifo_rd_empty;
    wire [11:0] fifo_rd_level;

    // -- loopback_ctrl → CSI TX (TX pixel 域) --
    wire [63:0] tx_pixel_data;
    wire        tx_pixel_valid;
    wire [5:0]  tx_datatype;
    wire [15:0] tx_line_num;
    wire [15:0] tx_haddr;
    wire [15:0] tx_frame_num;
    wire        tx_vsync_vc0;
    wire        tx_hsync_vc0;
    wire        tx_skip_frame;

    // -- CSI TX DPHY 反馈 (顶层 peri → IP) — 4K60: 4-lane --
    wire [3:0]  tx_ready_hs;
    wire [3:0]  tx_stop_state_d;
    wire        tx_stop_state_c;
    wire [3:0]  tx_ulps_active_not;
    wire        tx_ulps_active_clk_not;

    // -- CSI TX IRQ (pixel 域原始 → CDC 到 sys_clk) --
    wire        ctxi_irq_raw;
    wire        ctxi_irq_sys;

    // -- CSI TX IP 输出 (DPHY TX 驱动)，从 wrapper 引出到顶层 peri 端口 --
    // 4K60: 4-lane 全启用 (mipi_csi_tx_2p5g, 2.5 Gbps/lane = 10 Gbps)
    wire [15:0] ctxi_tx_data_hs0;
    wire [15:0] ctxi_tx_data_hs1;
    wire [15:0] ctxi_tx_data_hs2;   // 4K60 lane2
    wire [15:0] ctxi_tx_data_hs3;   // 4K60 lane3
    wire [3:0]  ctxi_tx_request_hs;     // 4-lane bundled
    wire        ctxi_tx_request_hsc;
    wire [1:0]  ctxi_tx_req_valid_hs0;
    wire [1:0]  ctxi_tx_req_valid_hs1;
    wire [1:0]  ctxi_tx_req_valid_hs2;   // 4K60 lane2
    wire [1:0]  ctxi_tx_req_valid_hs3;   // 4K60 lane3
    wire [3:0]  ctxi_tx_skew_cal_hs;    // 4-lane bundled
    wire [3:0]  ctxi_tx_ulps_esc;       // 4-lane bundled
    wire [3:0]  ctxi_tx_ulps_exit;      // 4-lane bundled
    wire [3:0]  ctxi_tx_request_esc;    // 4-lane bundled
    wire        ctxi_tx_ulps_clk;
    wire        ctxi_tx_ulps_exit_clk;

    //====================================================================
    // 1. 时钟�?PLL
    //====================================================================
    pll_sys_wrapper u_pll_sys (
        .clk_50m_i      (clk_50m),
        .pll_clkout_i   (pll_sys_CLKOUT0),  // 2026-07-19: 真 100 MHz PLL 输出
        .pll_locked_i   (pll_sys_LOCKED),   // 真硬块 LOCKED
        .arst_n_i       (arst_n),
        .sys_clk_o      (sys_clk),
        .pll_locked_o   (sys_pll_lock_int)
    );

    pll_ddr_wrapper u_pll_ddr (
        .ddr_clk_ref_i  (ddr_clk_ref),
        .pll_locked_i   (pll_ddr_LOCKED),   // 2026-07-19: 真硬块 LOCKED
        .arst_n_i       (arst_n),
        .ddr_clk_o      (ddr_clk),
        .pll_locked_o   (ddr_pll_lock_int)
    );

    //====================================================================
    // 2. 复位策略
    //====================================================================

    // 全局复位组合：arst_n �?sys_pll_lock �?ddr_pll_lock
    assign reset_n_global = arst_n & sys_pll_lock_int & ddr_pll_lock_int;

    // SoC 高有效复�?    assign soc_arst = ~reset_n_global;

    // PLL reset outputs
    assign sys_pll_rstn = arst_n;
    assign ddr_pll_rstn = arst_n;

    // sys_clk 域复位同�?
    rst_sync u_rst_sys (
        .clk_i      (sys_clk),
        .rst_n_i    (reset_n_global),
        .rst_n_o    (sys_rst_n)
    );

    // ddr_clk 域复位同�?
    rst_sync u_rst_ddr (
        .clk_i      (ddr_clk),
        .rst_n_i    (reset_n_global),
        .rst_n_o    (ddr_rst_n)
    );
    //====================================================================
    // 2b. Stage 2: MIPI RX 时钟与复位
    //   clk_byte_hs / 由 DPHY RX 输出驱动；
    //   clk_pixel_rx / clk_pixel_tx 由独立的 pll_pixel (PLL_TL1, 200 MHz) 驱动，
    //   不再共用 byte_hs（4K60 生产路径）。
    //   复位采用与全局 reset_n_global 异步、本域同步释放的标准模式。
    //====================================================================
    assign clk_byte_hs  = mipi_dphy_rx_clk_CLKOUT;
    assign clk_pixel_rx = pll_pixel_CLKOUT0;   // 2026-07-19: 独立 pixel PLL (200 MHz)
    assign clk_pixel_tx = pll_pixel_CLKOUT0;   // 同源（4K60 loopback 对称）

    rst_sync u_rst_byte_hs (
        .clk_i      (clk_byte_hs),
        .rst_n_i    (reset_n_global),
        .rst_n_o    (byte_hs_rst_n)
    );

    rst_sync u_rst_pixel (
        .clk_i      (clk_pixel_rx),
        .rst_n_i    (reset_n_global),
        .rst_n_o    (pixel_rst_n)
    );

    //====================================================================
    // 2c. Stage 2: CSI IRQ CDC（pixel 域 → sys_clk 域，3 级同步）
    //   CSI IRQ 为电平有效，多级 FF 同步足够（RTL Rules §7）。
    //====================================================================
    (* ASYNC_REG = "TRUE" *) reg [2:0] csi_irq_sync;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            csi_irq_sync <= 3'b0;
        else
            csi_irq_sync <= {csi_irq_sync[1:0], csi_irq_raw};
    end
    assign csi_irq_sys = csi_irq_sync[2];

    //====================================================================
    // 2d. Stage 3: TX pixel 时钟与复位
    //   clk_pixel_tx 由 pll_pixel (PLL_TL1, 200 MHz) 驱动，与 clk_pixel_rx 同源
    //   （assign 在 §2b 与 clk_pixel_rx 一起，保持 rx/tx 平行结构）。
    //====================================================================
    rst_sync u_rst_pixel_tx (
        .clk_i      (clk_pixel_tx),
        .rst_n_i    (reset_n_global),
        .rst_n_o    (pixel_tx_rst_n)
    );

    //====================================================================
    // 2e. Stage 3: CSI TX IRQ CDC（pixel 域 → sys_clk 域，3 级同步）
    //====================================================================
    (* ASYNC_REG = "TRUE" *) reg [2:0] ctxi_irq_sync;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            ctxi_irq_sync <= 3'b0;
        else
            ctxi_irq_sync <= {ctxi_irq_sync[1:0], ctxi_irq_raw};
    end
    assign ctxi_irq_sys = ctxi_irq_sync[2];
    //====================================================================
    // 3. Sapphire SoC
    //====================================================================
    sapphire_soc_wrapper u_soc (
        .clk_i                      (sys_clk),
        .arst_i                     (soc_arst),        // 高有�?        .sys_reset_o                (soc_sys_reset),

        // AXI-A Master �?DDR
        .axiA_awaddr_o              (soc_axi_awaddr),
        .axiA_awid_o                (soc_axi_awid),
        .axiA_awlen_o               (soc_axi_awlen),
        .axiA_awsize_o              (soc_axi_awsize),
        .axiA_awburst_o             (soc_axi_awburst),
        .axiA_awlock_o              (soc_axi_awlock),
        .axiA_awcache_o             (soc_axi_awcache),
        .axiA_awqos_o               (soc_axi_awqos),
        .axiA_awprot_o              (soc_axi_awprot),
        .axiA_awregion_o            (soc_axi_awregion),
        .axiA_awvalid_o             (soc_axi_awvalid),
        .axiA_awready_i             (soc_axi_awready),
        .axiA_wvalid_o              (soc_axi_wvalid),
        .axiA_wdata_o               (soc_axi_wdata),
        .axiA_wstrb_o               (soc_axi_wstrb),
        .axiA_wlast_o               (soc_axi_wlast),
        .axiA_wready_i              (soc_axi_wready),
        .axiA_bvalid_i              (soc_axi_bvalid),
        .axiA_bready_o              (soc_axi_bready),
        .axiA_bid_i                 (soc_axi_bid),
        .axiA_bresp_i               (soc_axi_bresp),
        .axiA_arvalid_o             (soc_axi_arvalid),
        .axiA_araddr_o              (soc_axi_araddr),
        .axiA_arid_o                (soc_axi_arid),
        .axiA_arlen_o               (soc_axi_arlen),
        .axiA_arsize_o              (soc_axi_arsize),
        .axiA_arburst_o             (soc_axi_arburst),
        .axiA_arlock_o              (soc_axi_arlock),
        .axiA_arcache_o             (soc_axi_arcache),
        .axiA_arqos_o               (soc_axi_arqos),
        .axiA_arprot_o              (soc_axi_arprot),
        .axiA_arregion_o            (soc_axi_arregion),
        .axiA_arready_i             (soc_axi_arready),
        .axiA_rvalid_i              (soc_axi_rvalid),
        .axiA_rready_o              (soc_axi_rready),
        .axiA_rdata_i               (soc_axi_rdata),
        .axiA_rid_i                 (soc_axi_rid),
        .axiA_rresp_i               (soc_axi_rresp),
        .axiA_rlast_i               (soc_axi_rlast),

        // Interrupts (Stage 2: CSI RX IRQ；Stage 3: 叠加 CSI TX IRQ；均经 CDC 到 sys_clk 域)
        .user_interrupt_a_i         (csi_irq_sys | ctxi_irq_sys),
        .axi_a_interrupt_i          (ddr_inst_CTRL_INT),

        // JTAG
        .jtag_tck_i                 (jtag_inst1_TCK),
        .jtag_tdi_i                 (jtag_inst1_TDI),
        .jtag_enable_i              (jtag_inst1_SEL),
        .jtag_capture_i             (jtag_inst1_CAPTURE),
        .jtag_shift_i               (jtag_inst1_SHIFT),
        .jtag_update_i              (jtag_inst1_UPDATE),
        .jtag_reset_i               (jtag_inst1_RESET),
        .jtag_tdo_o                 (jtag_inst1_TDO),

        // UART
        .uart_txd_o                 (system_uart_0_io_txd),
        .uart_rxd_i                 (system_uart_0_io_rxd),

        // SPI
        .spi_sclk_write_o           (system_spi_0_io_sclk_write),
        .spi_ss_o                   (system_spi_0_io_ss),
        .spi_data_0_write_o         (system_spi_0_io_data_0_write),
        .spi_data_0_writeEnable_o   (system_spi_0_io_data_0_writeEnable),
        .spi_data_0_read_i          (system_spi_0_io_data_0_read),
        .spi_data_1_write_o         (system_spi_0_io_data_1_write),
        .spi_data_1_writeEnable_o   (system_spi_0_io_data_1_writeEnable),
        .spi_data_1_read_i          (system_spi_0_io_data_1_read),
        .spi_data_2_write_o         (spi_data_2_write),
        .spi_data_2_writeEnable_o   (spi_data_2_writeEnable),
        .spi_data_2_read_i          (1'b0),
        .spi_data_3_write_o         (spi_data_3_write),
        .spi_data_3_writeEnable_o   (spi_data_3_writeEnable),
        .spi_data_3_read_i          (1'b0),

        // I2C
        .i2c_scl_read_i             (system_i2c_0_io_scl_read),
        .i2c_scl_write_o            (system_i2c_0_io_scl_write),
        .i2c_sda_read_i             (system_i2c_0_io_sda_read),
        .i2c_sda_write_o            (system_i2c_0_io_sda_write),

        // GPIO
        .gpio_read_i                (system_gpio_0_io_read),
        .gpio_write_o               (system_gpio_0_io_write),
        .gpio_writeEnable_o         (system_gpio_0_io_writeEnable),

        // APB Slave 0 (Stage 2: 经 apb_to_axilite 桥接 CSI RX 配置寄存器)
        .apb_paddr_o                (soc_apb_paddr),
        .apb_penable_o              (soc_apb_penable),
        .apb_psel_o                 (soc_apb_psel),
        .apb_pwrite_o               (soc_apb_pwrite),
        .apb_pwdata_o               (soc_apb_pwdata),
        .apb_prdata_i               (soc_apb_prdata),
        .apb_pready_i               (soc_apb_pready),
        .apb_pslverror_i            (soc_apb_pslverror)
    );

    //====================================================================
    // 3b. Stage 4: APB 1-to-3 地址译码器（sys_clk 域）
    //   把 SoC APB Slave 0 按 apb_paddr[15:11] 拆分到三个下游：
    //     • Slave 0 (0x0000-0x07FF) → CSI RX 配置（保留原 AW=6 路径）
    //     • Slave 1 (0x0800-0x0FFF) → TSE MAC CSR（AW=10）
    //     • Slave 2 (0x1000-0x17FF) → SD Host 总线槽位（AW=10）
    //   下游 APB 总线在内部声明；CSI RX 桥改接 s0_apb_*。
    //====================================================================
    wire [15:0] s0_apb_paddr;
    wire        s0_apb_psel;
    wire        s0_apb_penable;
    wire        s0_apb_pwrite;
    wire [31:0] s0_apb_pwdata;
    wire [31:0] s0_apb_prdata;
    wire        s0_apb_pready;
    wire        s0_apb_pslverror;

    wire [15:0] s1_apb_paddr;
    wire        s1_apb_psel;
    wire        s1_apb_penable;
    wire        s1_apb_pwrite;
    wire [31:0] s1_apb_pwdata;
    wire [31:0] s1_apb_prdata;
    wire        s1_apb_pready;
    wire        s1_apb_pslverror;

    wire [15:0] s2_apb_paddr;
    wire        s2_apb_psel;
    wire        s2_apb_penable;
    wire        s2_apb_pwrite;
    wire [31:0] s2_apb_pwdata;
    wire [31:0] s2_apb_prdata;
    wire        s2_apb_pready;
    wire        s2_apb_pslverror;

    apb_decoder_1to3 #(
        .AW ( 16 ),
        .DW ( 32 )
    ) u_apb_decoder (
        .clk_i           ( sys_clk          ),
        .rst_n_i         ( sys_rst_n        ),

        .apb_paddr_i     ( soc_apb_paddr    ),
        .apb_psel_i      ( soc_apb_psel     ),
        .apb_penable_i   ( soc_apb_penable  ),
        .apb_pwrite_i    ( soc_apb_pwrite   ),
        .apb_pwdata_i    ( soc_apb_pwdata   ),
        .apb_prdata_o    ( soc_apb_prdata   ),
        .apb_pready_o    ( soc_apb_pready   ),
        .apb_pslverror_o ( soc_apb_pslverror),

        .s0_paddr_o      ( s0_apb_paddr     ),
        .s0_psel_o       ( s0_apb_psel      ),
        .s0_penable_o    ( s0_apb_penable   ),
        .s0_pwrite_o     ( s0_apb_pwrite    ),
        .s0_pwdata_o     ( s0_apb_pwdata    ),
        .s0_prdata_i     ( s0_apb_prdata    ),
        .s0_pready_i     ( s0_apb_pready    ),
        .s0_pslverror_i  ( s0_apb_pslverror ),

        .s1_paddr_o      ( s1_apb_paddr     ),
        .s1_psel_o       ( s1_apb_psel      ),
        .s1_penable_o    ( s1_apb_penable   ),
        .s1_pwrite_o     ( s1_apb_pwrite    ),
        .s1_pwdata_o     ( s1_apb_pwdata    ),
        .s1_prdata_i     ( s1_apb_prdata    ),
        .s1_pready_i     ( s1_apb_pready    ),
        .s1_pslverror_i  ( s1_apb_pslverror ),

        .s2_paddr_o      ( s2_apb_paddr     ),
        .s2_psel_o       ( s2_apb_psel      ),
        .s2_penable_o    ( s2_apb_penable   ),
        .s2_pwrite_o     ( s2_apb_pwrite    ),
        .s2_pwdata_o     ( s2_apb_pwdata    ),
        .s2_prdata_i     ( s2_apb_prdata    ),
        .s2_pready_i     ( s2_apb_pready    ),
        .s2_pslverror_i  ( s2_apb_pslverror )
    );

    //====================================================================
    // 3c. Stage 2: APB3 → AXI4-Lite 桥（sys_clk 域）
    //   接 APB decoder 的 slave 0 输出，翻译成 CSI RX 的 6-bit AXI-Lite 总线。
    //====================================================================
    apb_to_axilite #(
        .AW     (6),
        .DW     (32)
    ) u_apb_to_axilite_csi (
        .clk_i              (sys_clk),
        .rst_n_i            (sys_rst_n),

        // APB3 Slave (来自 apb_decoder slave 0)
        .apb_paddr_i        (s0_apb_paddr),
        .apb_psel_i         (s0_apb_psel),
        .apb_penable_i      (s0_apb_penable),
        .apb_pwrite_i       (s0_apb_pwrite),
        .apb_pwdata_i       (s0_apb_pwdata),
        .apb_prdata_o       (s0_apb_prdata),
        .apb_pready_o       (s0_apb_pready),
        .apb_pslverror_o    (s0_apb_pslverror),

        // AXI4-Lite Master (去 CSI RX)
        .axi_awaddr_o       (csi_axi_awaddr),
        .axi_awvalid_o      (csi_axi_awvalid),
        .axi_awready_i      (csi_axi_awready),
        .axi_wdata_o        (csi_axi_wdata),
        .axi_wvalid_o       (csi_axi_wvalid),
        .axi_wready_i       (csi_axi_wready),
        .axi_bvalid_i       (csi_axi_bvalid),
        .axi_bready_o       (csi_axi_bready),
        .axi_araddr_o       (csi_axi_araddr),
        .axi_arvalid_o      (csi_axi_arvalid),
        .axi_arready_i      (csi_axi_arready),
        .axi_rdata_i        (csi_axi_rdata),
        .axi_rvalid_i       (csi_axi_rvalid),
        .axi_rready_o       (csi_axi_rready)
    );

    //====================================================================
    // 4. DDR 控制器包装（配置 FSM + AXI 复位控制�?    //====================================================================
    ddr_ctrl_wrapper u_ddr_ctrl (
        .soc_clk_i                  (sys_clk),
        .mem_clk_i                  (i_axi0_mem_clk),
        .arst_n_i                   (reset_n_global),

        // DDR 控制
        .ddr_cfg_start_o            (),
        .ddr_cfg_reset_o            (),
        .ddr_cfg_sel_o              (),
        .ddr_axi0_aresetn_o         (axi0_ARESETn),
        .ddr_axi1_aresetn_o         (axi1_ARESETn),

        // DDR 状�?        .ddr_cfg_done_i             (ddr_inst_CFG_DONE),
        .ddr_ctrl_busy_i            (ddr_inst_CTRL_BUSY),
        .ddr_ctrl_int_i             (ddr_inst_CTRL_INT),
        .ddr_ctrl_refresh_i         (ddr_inst_CTRL_REFRESH),
        .ddr_ctrl_mem_rst_valid_i   (ddr_inst_CTRL_MEM_RST_VALID),
        .ddr_ctrl_dp_idle_i         (ddr_inst_CTRL_DP_IDLE),
        .ddr_ctrl_port_busy_i       (ddr_inst_CTRL_PORT_BUSY),

        .soc_mem_reset_o            (soc_mem_reset)
    );

    //====================================================================
    // 4b. Stage 2: MIPI CSI-2 RX 例化
    //   - AXI-Lite 配置寄存器接 APB→AXI-Lite 桥
    //   - DPHY RX 物理层信号直接接顶层 peri 端口
    //   - Pixel 输出 Stage 2 仅观测（Stage 3 接 TX），IRQ 经 CDC 接 SoC
    //====================================================================
    hard_csi_rx_wrapper u_hard_csi_rx (
        // -- 时钟与复位 --
        .axi_clk_i                  (sys_clk),
        .axi_rst_n_i                (sys_rst_n),
        .clk_byte_hs_i              (clk_byte_hs),
        .rst_byte_hs_n_i            (byte_hs_rst_n),
        .clk_pixel_i                (clk_pixel_rx),
        .rst_pixel_n_i              (pixel_rst_n),
        .rst_n_global_i             (reset_n_global),

        // -- AXI-Lite Slave (来自 APB→AXI-Lite 桥) --
        .axi_awaddr_i               (csi_axi_awaddr),
        .axi_awvalid_i              (csi_axi_awvalid),
        .axi_awready_o              (csi_axi_awready),
        .axi_wdata_i                (csi_axi_wdata),
        .axi_wvalid_i               (csi_axi_wvalid),
        .axi_wready_o               (csi_axi_wready),
        .axi_bready_i               (csi_axi_bready),
        .axi_bvalid_o               (csi_axi_bvalid),
        .axi_araddr_i               (csi_axi_araddr),
        .axi_arvalid_i              (csi_axi_arvalid),
        .axi_arready_o              (csi_axi_arready),
        .axi_rdata_o                (csi_axi_rdata),
        .axi_rvalid_o               (csi_axi_rvalid),
        .axi_rready_i               (csi_axi_rready),

        // -- DPHY RX 物理层（顶层 peri 端口直接转发）--
        .rx_ulps_clk_not_i          (mipi_dphy_rx_inst2_ULPS_CLK_ACTIVEN),
        .rx_ulps_active_clk_not_i   (mipi_dphy_rx_inst2_ULPS_CLK_ACTIVEN),
        .rx_clk_esc_i               ({
            mipi_dphy_rx_inst2_ESC_LAN3_CLK,
            mipi_dphy_rx_inst2_ESC_LAN2_CLK,
            mipi_dphy_rx_inst2_ESC_LAN1_CLK,
            mipi_dphy_rx_inst2_ESC_LAN0_CLK
        }),
        .rx_err_esc_i               ({
            mipi_dphy_rx_inst2_ESC_LAN3_ERROR,
            mipi_dphy_rx_inst2_ESC_LAN2_ERROR,
            mipi_dphy_rx_inst2_ESC_LAN1_ERROR,
            mipi_dphy_rx_inst2_ESC_LAN0_ERROR
        }),
        .rx_err_control_i           (4'h0),                              // 暂不接（无对应 peri 端口）
        .rx_err_sot_sync_hs_i       ({
            mipi_dphy_rx_inst2_HS_LAN3_SOTSYNC_ERROR,
            mipi_dphy_rx_inst2_HS_LAN2_SOTSYNC_ERROR,
            mipi_dphy_rx_inst2_HS_LAN1_SOTSYNC_ERROR,
            mipi_dphy_rx_inst2_HS_LAN0_SOTSYNC_ERROR
        }),
        .rx_ulps_esc_i              ({
            mipi_dphy_rx_inst2_ULPS_LAN3_ACTIVEN,
            mipi_dphy_rx_inst2_ULPS_LAN2_ACTIVEN,
            mipi_dphy_rx_inst2_ULPS_LAN1_ACTIVEN,
            mipi_dphy_rx_inst2_ULPS_LAN0_ACTIVEN
        }),
        .rx_ulps_active_not_i       (4'hF),                              // ULPS ESC not active
        .rx_skew_cal_hs_i           ({
            mipi_dphy_rx_inst2_HS_LAN3_SKEWCAL,
            mipi_dphy_rx_inst2_HS_LAN2_SKEWCAL,
            mipi_dphy_rx_inst2_HS_LAN1_SKEWCAL,
            mipi_dphy_rx_inst2_HS_LAN0_SKEWCAL
        }),
        .rx_stop_state_i            ({
            mipi_dphy_rx_inst2_STOPSTATE_LAN3,
            mipi_dphy_rx_inst2_STOPSTATE_LAN2,
            mipi_dphy_rx_inst2_STOPSTATE_LAN1,
            mipi_dphy_rx_inst2_STOPSTATE_LAN0
        }),
        .rx_sync_hs_i               ({
            mipi_dphy_rx_inst2_HS_LAN3_SYNC,
            mipi_dphy_rx_inst2_HS_LAN2_SYNC,
            mipi_dphy_rx_inst2_HS_LAN1_SYNC,
            mipi_dphy_rx_inst2_HS_LAN0_SYNC
        }),
        // 4-lane HS 数据
        .rx_data_hs0_i              (mipi_dphy_rx_inst2_HS_LAN0_DATA),
        .rx_data_hs1_i              (mipi_dphy_rx_inst2_HS_LAN1_DATA),
        .rx_data_hs2_i              (mipi_dphy_rx_inst2_HS_LAN2_DATA),
        .rx_data_hs3_i              (mipi_dphy_rx_inst2_HS_LAN3_DATA),
        // 4-lane HS valid（每 lane 是 2-bit，DPHY 端口提供 1-bit，扩展到 [0]）
        .rx_valid_hs0_i             ({1'b0, mipi_dphy_rx_inst2_HS_LAN0_VALID}),
        .rx_valid_hs1_i             ({1'b0, mipi_dphy_rx_inst2_HS_LAN1_VALID}),
        .rx_valid_hs2_i             ({1'b0, mipi_dphy_rx_inst2_HS_LAN2_VALID}),
        .rx_valid_hs3_i             ({1'b0, mipi_dphy_rx_inst2_HS_LAN3_VALID}),

        // -- Pixel 输出（Stage 2 仅观测，Stage 3 接 TX）--
        .pixel_data_valid_o         (csi_pixel_valid),
        .pixel_data_o               (csi_pixel_data),
        .pixel_per_clk_o            (csi_pixel_per_clk),
        .datatype_o                 (csi_datatype),
        .word_count_o               (csi_word_count),
        .shortpkt_data_field_o      (csi_shortpkt),
        .vc_o                       (csi_vc),
        .vcx_o                      (csi_vcx),
        .vsync_vc0_o                (csi_vsync_vc0),
        .hsync_vc0_o                (csi_hsync_vc0),

        // -- IRQ (pixel 域原始，由顶层经 CDC 后接 SoC)--
        .irq_raw_o                  (csi_irq_raw)
    );

    //====================================================================
    //====================================================================
    // 5. SoC AXI-A → DDR AXI0 位宽转换桥（Stage 5）
    //    SoC 32-bit AXI4 主口经 axi_dwidth_converter 适配到 DDR 512-bit AXI0：
    //      · 写：聚集 16 拍 narrow W → 1 拍 wide W（按 dword 偏移拼装 + WSTRB 合并）
    //      · 读：1 拍 wide R → 拆成 narrow R 序列（按 ARADDR 偏移选起始 dword）
    //    单时钟 sys_clk（与 Stage 1~4 的 SoC↔DDR 单时钟假设一致）；
    //    CDC（sys_clk ↔ mem_clk）不在本桥内处理，见模块备注与设计说明书 §5.4。
    //    仿真：sim/tb_axi_dwidth.sv（单 dword / 16-beat line / 邻位隔离 全 PASS）。
    //====================================================================
    axi_dwidth_converter #(
        .M_DW  ( 32  ),
        .S_DW  ( 512 ),
        .M_AW  ( 32  ),
        .S_AW  ( 33  ),
        .M_IDW ( 8   ),
        .S_IDW ( 6   )
    ) u_axi_dwidth (
        .clk_i           ( sys_clk     ),
        .rst_n_i         ( sys_rst_n   ),

        // ===== Manager 侧：SoC 32-bit AXI-A =====
        .m_axi_awid_i    ( soc_axi_awid    ),
        .m_axi_awaddr_i  ( soc_axi_awaddr  ),
        .m_axi_awlen_i   ( soc_axi_awlen   ),
        .m_axi_awsize_i  ( soc_axi_awsize  ),
        .m_axi_awburst_i ( soc_axi_awburst ),
        .m_axi_awlock_i  ( soc_axi_awlock  ),
        .m_axi_awcache_i ( soc_axi_awcache ),
        .m_axi_awprot_i  ( soc_axi_awprot  ),
        .m_axi_awqos_i   ( soc_axi_awqos   ),
        .m_axi_awvalid_i ( soc_axi_awvalid ),
        .m_axi_awready_o ( soc_axi_awready ),
        .m_axi_wdata_i   ( soc_axi_wdata   ),
        .m_axi_wstrb_i   ( soc_axi_wstrb   ),
        .m_axi_wlast_i   ( soc_axi_wlast   ),
        .m_axi_wvalid_i  ( soc_axi_wvalid  ),
        .m_axi_wready_o  ( soc_axi_wready  ),
        .m_axi_bid_o     ( soc_axi_bid     ),
        .m_axi_bresp_o   ( soc_axi_bresp   ),
        .m_axi_bvalid_o  ( soc_axi_bvalid  ),
        .m_axi_bready_i  ( soc_axi_bready  ),
        .m_axi_arid_i    ( soc_axi_arid    ),
        .m_axi_araddr_i  ( soc_axi_araddr  ),
        .m_axi_arlen_i   ( soc_axi_arlen   ),
        .m_axi_arsize_i  ( soc_axi_arsize  ),
        .m_axi_arburst_i ( soc_axi_arburst ),
        .m_axi_arlock_i  ( soc_axi_arlock  ),
        .m_axi_arcache_i ( soc_axi_arcache ),
        .m_axi_arprot_i  ( soc_axi_arprot  ),
        .m_axi_arqos_i   ( soc_axi_arqos   ),
        .m_axi_arvalid_i ( soc_axi_arvalid ),
        .m_axi_arready_o ( soc_axi_arready ),
        .m_axi_rid_o     ( soc_axi_rid     ),
        .m_axi_rdata_o   ( soc_axi_rdata   ),
        .m_axi_rresp_o   ( soc_axi_rresp   ),
        .m_axi_rlast_o   ( soc_axi_rlast   ),
        .m_axi_rvalid_o  ( soc_axi_rvalid  ),
        .m_axi_rready_i  ( soc_axi_rready  ),

        // ===== Subordinate 侧：DDR 512-bit AXI0 =====
        .s_axi_awid_o    ( axi0_AWID    ),
        .s_axi_awaddr_o  ( axi0_AWADDR  ),
        .s_axi_awlen_o   ( axi0_AWLEN   ),
        .s_axi_awsize_o  ( axi0_AWSIZE  ),
        .s_axi_awburst_o ( axi0_AWBURST ),
        .s_axi_awlock_o  ( axi0_AWLOCK  ),
        .s_axi_awcache_o ( axi0_AWCACHE ),
        .s_axi_awprot_o  ( axi0_AWPROT  ),
        .s_axi_awqos_o   ( axi0_AWQOS   ),
        .s_axi_awvalid_o ( axi0_AWVALID ),
        .s_axi_awready_i ( axi0_AWREADY ),
        .s_axi_wdata_o   ( axi0_WDATA   ),
        .s_axi_wstrb_o   ( axi0_WSTRB   ),
        .s_axi_wlast_o   ( axi0_WLAST   ),
        .s_axi_wvalid_o  ( axi0_WVALID  ),
        .s_axi_wready_i  ( axi0_WREADY  ),
        .s_axi_bid_i     ( axi0_BID     ),
        .s_axi_bresp_i   ( axi0_BRESP   ),
        .s_axi_bvalid_i  ( axi0_BVALID  ),
        .s_axi_bready_o  ( axi0_BREADY  ),
        .s_axi_arid_o    ( axi0_ARID    ),
        .s_axi_araddr_o  ( axi0_ARADDR  ),
        .s_axi_arlen_o   ( axi0_ARLEN   ),
        .s_axi_arsize_o  ( axi0_ARSIZE  ),
        .s_axi_arburst_o ( axi0_ARBURST ),
        .s_axi_arlock_o  ( axi0_ARLOCK  ),
        .s_axi_arcache_o ( axi0_ARCACHE ),
        .s_axi_arprot_o  ( axi0_ARPROT  ),
        .s_axi_arqos_o   ( axi0_ARQOS   ),
        .s_axi_arvalid_o ( axi0_ARVALID ),
        .s_axi_arready_i ( axi0_ARREADY ),
        .s_axi_rid_i     ( axi0_RID     ),
        .s_axi_rdata_i   ( axi0_RDATA   ),
        .s_axi_rresp_i   ( axi0_RRESP   ),
        .s_axi_rlast_i   ( axi0_RLAST   ),
        .s_axi_rvalid_i  ( axi0_RVALID  ),
        .s_axi_rready_o  ( axi0_RREADY  )
    );

    // -- AXI1 端口禁用 --
    assign axi1_ARVALID   = 1'b0;
    assign axi1_ARADDR    = 33'h0;
    assign axi1_AWVALID   = 1'b0;
    assign axi1_AWADDR    = 33'h0;
    assign axi1_WVALID    = 1'b0;
    assign axi1_WLAST     = 1'b0;
    assign axi1_BREADY    = 1'b0;
    assign axi1_RREADY    = 1'b0;

    //====================================================================
    // 6. 外设三态转�?    //====================================================================
    assign system_i2c_0_io_scl_writeEnable = ~system_i2c_0_io_scl_write;
    assign system_i2c_0_io_sda_writeEnable = ~system_i2c_0_io_sda_write;
    assign phy_rstn = arst_n;

    // SD Host (Stage 4 �?暂为 stub)
    // Stage 4: SD Host stub 下线，改由 u_sdhost_slot 驱动物理引脚（见下方实例）。
    sdhost_slot_wrapper u_sdhost_slot (
        .clk_i          ( sys_clk       ),
        .rst_n_i        ( sys_rst_n     ),

        // APB3 Slave (来自 apb_decoder slave 2)
        .apb_paddr_i    ( s2_apb_paddr  ),
        .apb_psel_i     ( s2_apb_psel   ),
        .apb_penable_i  ( s2_apb_penable),
        .apb_pwrite_i   ( s2_apb_pwrite ),
        .apb_pwdata_i   ( s2_apb_pwdata ),
        .apb_prdata_o   ( s2_apb_prdata ),
        .apb_pready_o   ( s2_apb_pready ),
        .apb_pslverror_o( s2_apb_pslverror),

        // SD 物理引脚（wrapper 内部 OE=0 高阻，安全默认）
        .sd_clk_o       ( sd_clk_hi     ),
        .sd_cmd_o       ( sd_cmd_o      ),
        .sd_cmd_oe      ( sd_cmd_oe     ),
        .sd_cmd_i       ( sd_cmd_i      ),
        .sd_dat_o       ( sd_dat_o      ),
        .sd_dat_oe      ( sd_dat_oe     ),
        .sd_dat_i       ( sd_dat_i      ),
        .sd_cd_n        ( sd_cd_n       )
    );

    //====================================================================
    // 7. Stage 3: MIPI CSI-2 TX + Pixel 异步 FIFO + Loopback
    //====================================================================

    //----------------------------------------------------------------
    // 7a. async_pixel_fifo — RX pixel 域 → TX pixel 域（DW=64, depth=2048,
    //     sideband=8-bit {vsync, hsync, datatype[5:0]}）
    //----------------------------------------------------------------
    async_fifo #(
        .DW         (64),
        .AW         (11),         // 深度 2048
        .AWIDTH     (8),          // {vsync, hsync, datatype[5:0]}
        .SYNC_DEPTH (2)
    ) u_async_pixel_fifo (
        // 写侧（RX pixel 域）
        .wr_clk_i       (clk_pixel_rx),
        .wr_rst_n_i     (pixel_rst_n),
        .wr_en_i        (fifo_wr_en),
        .wr_data_i      (fifo_wr_data),
        .wr_side_i      (fifo_wr_side),
        .wr_full_o      (fifo_wr_full),
        .wr_level_o     (fifo_wr_level),
        // 读侧（TX pixel 域）
        .rd_clk_i       (clk_pixel_tx),
        .rd_rst_n_i     (pixel_tx_rst_n),
        .rd_en_i        (fifo_rd_en),
        .rd_data_o      (fifo_rd_data),
        .rd_side_o      (fifo_rd_side),
        .rd_empty_o     (fifo_rd_empty),
        .rd_level_o     (fifo_rd_level)
    );

    //----------------------------------------------------------------
    // 7b. loopback_ctrl — RX 域写 FIFO / TX 域读 FIFO + 重建 sync/计数
    //----------------------------------------------------------------
    loopback_ctrl #(
        .FIFO_HALF_FULL (12'd1024)     // 半满即丢帧
    ) u_loopback_ctrl (
        // RX 域
        .clk_rx_i               (clk_pixel_rx),
        .rst_rx_n_i             (pixel_rst_n),
        .rx_pixel_valid_i       (csi_pixel_valid),
        .rx_pixel_data_i        (csi_pixel_data),
        .rx_datatype_i          (csi_datatype),
        .rx_vsync_vc0_i         (csi_vsync_vc0),
        .rx_hsync_vc0_i         (csi_hsync_vc0),
        // FIFO 写侧（RX 域）
        .fifo_wr_en_o           (fifo_wr_en),
        .fifo_wr_data_o         (fifo_wr_data),
        .fifo_wr_side_o         (fifo_wr_side),
        .fifo_wr_full_i         (fifo_wr_full),
        .fifo_wr_level_i        (fifo_wr_level),
        // FIFO 读侧（TX 域）
        .clk_tx_i               (clk_pixel_tx),
        .rst_tx_n_i             (pixel_tx_rst_n),
        .fifo_rd_en_o           (fifo_rd_en),
        .fifo_rd_data_i         (fifo_rd_data),
        .fifo_rd_side_i         (fifo_rd_side),
        .fifo_rd_empty_i        (fifo_rd_empty),
        .fifo_rd_level_i        (fifo_rd_level),
        // 拥塞观测
        .tx_skip_frame_o        (tx_skip_frame),
        // TX pixel 域输出 → CSI TX
        .tx_pixel_data_o        (tx_pixel_data),
        .tx_pixel_data_valid_o  (tx_pixel_valid),
        .tx_datatype_o          (tx_datatype),
        .tx_line_num_o          (tx_line_num),
        .tx_haddr_o             (tx_haddr),
        .tx_frame_num_o         (tx_frame_num),
        .tx_vsync_vc0_o         (tx_vsync_vc0),
        .tx_hsync_vc0_o         (tx_hsync_vc0)
    );

    //----------------------------------------------------------------
    // 7c. CSI TX 寄存器 AXI-Lite 默认（safe-idle）
    //   当前 SoC wrapper 仅暴露 APB Slave 0（已用于 CSI RX）；
    //   Stage 3 暂不让软件发起对 CSI TX 的 AXI-Lite 访问。
    //   → 所有 valid 拉零，ready 丢弃，软件后续可经 APB Slave 1/AXI 扩展。
    //----------------------------------------------------------------
    assign ctxi_axi_awvalid = 1'b0;
    assign ctxi_axi_wvalid  = 1'b0;
    assign ctxi_axi_arvalid = 1'b0;
    assign ctxi_axi_awaddr  = 6'h0;
    assign ctxi_axi_wdata   = 32'h0;
    assign ctxi_axi_araddr  = 6'h0;
    assign ctxi_axi_bready  = 1'b1;       // 总能接收写响应（实际不会来）
    assign ctxi_axi_rready  = 1'b1;

    //----------------------------------------------------------------
    // 7d. mipi_csi_tx_2p5g IP 例化（4K60 4-lane 包装）
    //   2026-07-19: 从 hard_csi_tx (2-lane@960Mbps=1.92Gbps) 升级到
    //              mipi_csi_tx_2p5g (4-lane@2.5Gbps=10Gbps)，足够 4K60 YUV422
    //              (7.96 Gbps active，余量 26%)。
    //----------------------------------------------------------------
    mipi_csi_tx_2p5g_wrapper u_mipi_csi_tx_2p5g (
        // 时钟与复位
        .axi_clk_i              (sys_clk),
        .axi_rst_n_i            (sys_rst_n),
        .clk_byte_hs_i          (clk_byte_hs),
        .rst_byte_hs_n_i        (byte_hs_rst_n),
        .clk_pixel_i            (clk_pixel_tx),
        .rst_pixel_n_i          (pixel_tx_rst_n),
        .rst_n_global_i         (reset_n_global),

        // AXI-Lite Slave (safe-idle，见 §7c)
        .axi_awaddr_i           (ctxi_axi_awaddr),
        .axi_awvalid_i          (ctxi_axi_awvalid),
        .axi_awready_o          (ctxi_axi_awready),
        .axi_wdata_i            (ctxi_axi_wdata),
        .axi_wvalid_i           (ctxi_axi_wvalid),
        .axi_wready_o           (ctxi_axi_wready),
        .axi_bready_i           (ctxi_axi_bready),
        .axi_bvalid_o           (ctxi_axi_bvalid),
        .axi_araddr_i           (ctxi_axi_araddr),
        .axi_arvalid_i          (ctxi_axi_arvalid),
        .axi_arready_o          (ctxi_axi_arready),
        .axi_rdata_o            (ctxi_axi_rdata),
        .axi_rvalid_o           (ctxi_axi_rvalid),
        .axi_rready_i           (ctxi_axi_rready),

        // Pixel 输入（TX pixel 域，来自 loopback_ctrl）
        .pixel_data_valid_i     (tx_pixel_valid),
        .pixel_data_i           (tx_pixel_data),
        .datatype_i             (tx_datatype),
        .line_num_i             (tx_line_num),
        .haddr_i                (tx_haddr),
        .frame_num_i            (tx_frame_num),
        .vsync_vc0_i            (tx_vsync_vc0),
        .hsync_vc0_i            (tx_hsync_vc0),

        // DPHY TX 驱动输出 → 顶层 peri 端口（见 §7f） — 4-lane 全启用
        .tx_data_hs0_o          (ctxi_tx_data_hs0),
        .tx_data_hs1_o          (ctxi_tx_data_hs1),
        .tx_data_hs2_o          (ctxi_tx_data_hs2),
        .tx_data_hs3_o          (ctxi_tx_data_hs3),
        .tx_request_hs_o        (ctxi_tx_request_hs),
        .tx_request_hsc_o       (ctxi_tx_request_hsc),
        .tx_req_valid_hs0_o     (ctxi_tx_req_valid_hs0),
        .tx_req_valid_hs1_o     (ctxi_tx_req_valid_hs1),
        .tx_req_valid_hs2_o     (ctxi_tx_req_valid_hs2),
        .tx_req_valid_hs3_o     (ctxi_tx_req_valid_hs3),
        .tx_skew_cal_hs_o       (ctxi_tx_skew_cal_hs),
        .tx_ulps_esc_o          (ctxi_tx_ulps_esc),
        .tx_ulps_exit_o         (ctxi_tx_ulps_exit),
        .tx_request_esc_o       (ctxi_tx_request_esc),
        .tx_ulps_clk_o          (ctxi_tx_ulps_clk),
        .tx_ulps_exit_clk_o     (ctxi_tx_ulps_exit_clk),

        // DPHY TX 反馈输入
        .tx_ready_hs_i          (tx_ready_hs),
        .tx_stop_state_d_i      (tx_stop_state_d),
        .tx_stop_state_c_i      (tx_stop_state_c),
        .tx_ulps_active_not_i   (tx_ulps_active_not),
        .tx_ulps_active_clk_not_i(tx_ulps_active_clk_not),

        // IRQ
        .irq_raw_o              (ctxi_irq_raw)
    );

    //----------------------------------------------------------------
    // 7e. 顶层 peri TX 端口映射（wrapper 内部 IP 输出 → 顶层）
    //   4K60: 4-lane 全启用（lane0..3 由 IP 驱动）
    //----------------------------------------------------------------
    // DPHY TX 反馈输入（顶层 peri 输入 → IP） — 4-lane
    assign tx_ready_hs            = 4'b1111;   // FPGA 永远 ready (4-lane)
    assign tx_stop_state_d        = {
        mipi_dphy_tx_inst1_STOPSTATE_LAN3,
        mipi_dphy_tx_inst1_STOPSTATE_LAN2,
        mipi_dphy_tx_inst1_STOPSTATE_LAN1,
        mipi_dphy_tx_inst1_STOPSTATE_LAN0
    };
    assign tx_stop_state_c        = mipi_dphy_tx_inst1_STOPSTATE_CLK;
    assign tx_ulps_active_not     = {
        mipi_dphy_tx_inst1_ULPS_LAN3_ACTIVEN,
        mipi_dphy_tx_inst1_ULPS_LAN2_ACTIVEN,
        mipi_dphy_tx_inst1_ULPS_LAN1_ACTIVEN,
        mipi_dphy_tx_inst1_ULPS_LAN0_ACTIVEN
    };
    assign tx_ulps_active_clk_not = mipi_dphy_tx_inst1_ULPS_CLK_ACTIVEN;

    // DPHY TX 驱动输出（IP → 顶层 peri 输出，4-lane 全启用）
    assign mipi_dphy_tx_inst1_HS_LAN0_DATA = ctxi_tx_data_hs0;
    assign mipi_dphy_tx_inst1_HS_LAN1_DATA = ctxi_tx_data_hs1;
    assign mipi_dphy_tx_inst1_HS_LAN2_DATA = ctxi_tx_data_hs2;
    assign mipi_dphy_tx_inst1_HS_LAN3_DATA = ctxi_tx_data_hs3;

    assign mipi_dphy_tx_inst1_HS_LAN0_REQUEST   = ctxi_tx_request_hs[0];
    assign mipi_dphy_tx_inst1_HS_LAN1_REQUEST   = ctxi_tx_request_hs[1];
    assign mipi_dphy_tx_inst1_HS_LAN2_REQUEST   = ctxi_tx_request_hs[2];
    assign mipi_dphy_tx_inst1_HS_LAN3_REQUEST   = ctxi_tx_request_hs[3];
    assign mipi_dphy_tx_inst1_HS_CLK_REQUEST    = ctxi_tx_request_hsc;

    assign mipi_dphy_tx_inst1_HS_LAN0_HIGHVALID = ctxi_tx_req_valid_hs0[0];
    assign mipi_dphy_tx_inst1_HS_LAN1_HIGHVALID = ctxi_tx_req_valid_hs1[0];
    assign mipi_dphy_tx_inst1_HS_LAN2_HIGHVALID = ctxi_tx_req_valid_hs2[0];
    assign mipi_dphy_tx_inst1_HS_LAN3_HIGHVALID = ctxi_tx_req_valid_hs3[0];

    assign mipi_dphy_tx_inst1_HS_LAN0_SKEWCAL   = ctxi_tx_skew_cal_hs[0];
    assign mipi_dphy_tx_inst1_HS_LAN1_SKEWCAL   = ctxi_tx_skew_cal_hs[1];
    assign mipi_dphy_tx_inst1_HS_LAN2_SKEWCAL   = ctxi_tx_skew_cal_hs[2];
    assign mipi_dphy_tx_inst1_HS_LAN3_SKEWCAL   = ctxi_tx_skew_cal_hs[3];

    assign mipi_dphy_tx_inst1_REQUESTESC_LAN0   = ctxi_tx_request_esc[0];
    assign mipi_dphy_tx_inst1_REQUESTESC_LAN1   = ctxi_tx_request_esc[1];
    assign mipi_dphy_tx_inst1_REQUESTESC_LAN2   = ctxi_tx_request_esc[2];
    assign mipi_dphy_tx_inst1_REQUESTESC_LAN3   = ctxi_tx_request_esc[3];

    assign mipi_dphy_tx_inst1_ULPS_CLK_ENTER    = ctxi_tx_ulps_clk;
    assign mipi_dphy_tx_inst1_ULPS_CLK_EXIT     = ctxi_tx_ulps_exit_clk;
    assign mipi_dphy_tx_inst1_ULPS_LAN0_ENTER   = ctxi_tx_ulps_esc[0];
    assign mipi_dphy_tx_inst1_ULPS_LAN1_ENTER   = ctxi_tx_ulps_esc[1];
    assign mipi_dphy_tx_inst1_ULPS_LAN2_ENTER   = ctxi_tx_ulps_esc[2];
    assign mipi_dphy_tx_inst1_ULPS_LAN3_ENTER   = ctxi_tx_ulps_esc[3];
    assign mipi_dphy_tx_inst1_ULPS_LAN0_EXIT    = ctxi_tx_ulps_exit[0];
    assign mipi_dphy_tx_inst1_ULPS_LAN1_EXIT    = ctxi_tx_ulps_exit[1];
    assign mipi_dphy_tx_inst1_ULPS_LAN2_EXIT    = ctxi_tx_ulps_exit[2];
    assign mipi_dphy_tx_inst1_ULPS_LAN3_EXIT    = ctxi_tx_ulps_exit[3];

    //----------------------------------------------------------------
    // 7f. DPHY TX 硬块顶层控制位（顶层输出，由 fabric 驱动 DPHY 硬 IP）
    //----------------------------------------------------------------
    // RESET (高有效硬复位)：byte_hs 域复位期间保持高，释放后拉低
    reg dphy_tx_reset_r;
    always @(posedge clk_byte_hs or negedge byte_hs_rst_n) begin
        if (!byte_hs_rst_n)
            dphy_tx_reset_r <= 1'b1;        // 复位期间保持 DPHY in reset
        else
            dphy_tx_reset_r <= 1'b0;        // 稳定后释放
    end
    assign mipi_dphy_tx_inst1_RESET       = dphy_tx_reset_r;
    assign mipi_dphy_tx_inst1_PLL_UNLOCK  = 1'b0;   // PLL locked indication
    assign mipi_dphy_tx_inst1_PLL_SSC_EN  = 1'b0;   // no spread spectrum

    // ESC 层顶层输出（CSI TX IP 未驱动，留安全默认；后续按需扩展）
    assign mipi_dphy_tx_inst1_TX_DATA_ESC   = 8'h0;
    assign mipi_dphy_tx_inst1_TX_TRIGGER_ESC = 4'h0;
    assign mipi_dphy_tx_inst1_TX_LPDT_ESC   = 1'b0;
    assign mipi_dphy_tx_inst1_TX_VALID_ESC  = 1'b0;
    assign mipi_dphy_tx_inst1_TX_READY_ESC  = 1'b1;  // ESC ready idle

    //====================================================================
    // 7g. Stage 2: MIPI DPHY RX 控制位驱动
    //   - RESET (高有效硬复位) 跟随 byte_hs 域复位取反
    //   - RST0_N (低有效软复位) 跟随 byte_hs 域复位
    //   - FORCE_RX_MODE：byte_hs 稳定后强制 RX 模式（接收 HS 数据）
    //   时钟域：byte_hs（与 DPHY RX 同源），无需 CDC
    //====================================================================
    // FORCE_RX_MODE 经一拍同步，避免复位释放瞬间毛刺
    reg force_rx_mode_r;
    always @(posedge clk_byte_hs or negedge byte_hs_rst_n) begin
        if (!byte_hs_rst_n)
            force_rx_mode_r <= 1'b0;
        else
            force_rx_mode_r <= 1'b1;     // 复位释放后强制 RX 模式
    end

    assign mipi_dphy_rx_inst2_FORCE_RX_MODE = force_rx_mode_r;
    assign mipi_dphy_rx_inst2_RESET         = ~byte_hs_rst_n;   // 高有效
    assign mipi_dphy_rx_inst2_RST0_N        = byte_hs_rst_n;    // 低有效

    //====================================================================
    // 7d. Stage 4: TSE MAC 例化（RGMII + MDIO + APB CSR）
    //   APB decoder slave 1 → 内部 apb_to_axilite (AW=10) → TSE CSR。
    //   AXI4-Stream 直走 RGMII 物理管脚（已移除 bring-up 阶段的 RX→TX 内环回；
    //   TX 静态 idle，RX 持续排空），后续由 SoC DMA 接管 TX/RX 数据通路。
    //   MAC 时钟 = sys_clk（50MHz，参考 temac_ex.v）；rgmii_rxc 异步。
    //====================================================================
    wire [2:0]  tse_eth_speed;   // 链路速度观测（未接 LED；进 _unused）

    tse_mac_wrapper u_tse_mac (
        .mac_clk_i           ( sys_clk           ),
        .mac_rst_n_i         ( sys_rst_n         ),
        .mac_sw_rst_i        ( 1'b0              ),  // 软复位由 CSR 触发，暂静态 0
        .phy_locked_i        ( sys_pll_lock      ),  // PLL 锁定后释放 MAC 复位

        // RGMII DDR 物理引脚（顶层 peri 直连）
        .rgmii_txd_HI_o      ( rgmii_txd_HI      ),
        .rgmii_txd_LO_o      ( rgmii_txd_LO      ),
        .rgmii_tx_ctl_HI_o   ( rgmii_tx_ctl_HI   ),
        .rgmii_tx_ctl_LO_o   ( rgmii_tx_ctl_LO   ),
        .rgmii_txc_HI_o      ( rgmii_txc_HI      ),
        .rgmii_txc_LO_o      ( rgmii_txc_LO      ),
        .rgmii_rxd_HI_i      ( rgmii_rxd_HI      ),
        .rgmii_rxd_LO_i      ( rgmii_rxd_LO      ),
        .rgmii_rx_ctl_HI_i   ( rgmii_rx_ctl_HI   ),
        .rgmii_rx_ctl_LO_i   ( rgmii_rx_ctl_LO   ),
        .rgmii_rxc_i         ( rgmii_rxc         ),

        // MDIO
        .phy_mdc_o           ( phy_mdc           ),
        .phy_mdo_o           ( phy_mdo           ),
        .phy_mdo_en_o        ( phy_mdo_en        ),
        .phy_mdi_i           ( phy_mdi           ),

        // APB3 Slave (来自 apb_decoder slave 1)
        .apb_paddr_i         ( s1_apb_paddr      ),
        .apb_psel_i          ( s1_apb_psel       ),
        .apb_penable_i       ( s1_apb_penable    ),
        .apb_pwrite_i        ( s1_apb_pwrite     ),
        .apb_pwdata_i        ( s1_apb_pwdata     ),
        .apb_prdata_o        ( s1_apb_prdata     ),
        .apb_pready_o        ( s1_apb_pready     ),
        .apb_pslverror_o     ( s1_apb_pslverror  ),

        // 链路状态
        .eth_speed_o         ( tse_eth_speed     )
    );

    //====================================================================
    // 8. LED 状态指�?    //====================================================================
    reg [25:0] led_counter;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            led_counter <= 26'd0;
        else
            led_counter <= led_counter + 1'b1;
    end

    assign led[0] = led_counter[25];          // 慢闪 — 系统运行
    assign led[1] = sys_pll_lock_int;         // PLL sys lock（wrapper 内同步后）
    assign led[2] = ddr_pll_lock_int;         // PLL ddr lock（wrapper 内同步后）
    assign led[3] = ddr_inst_CFG_DONE;        // DDR 配置完成

    //====================================================================
    // 8b. Stage 2: Pixel heartbeat — pixel_data_valid 经 CDC 到 sys_clk 域
    //   供 Stage 2 验收（chipscope / 寄存器读）和后续扩展使用。
    //   像素有效脉冲在 pixel 域，先打 3 级 FF 同步到 sys_clk 域。
    //====================================================================
    (* ASYNC_REG = "TRUE" *) reg [2:0] pixel_valid_sync;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            pixel_valid_sync <= 3'b0;
        else
            pixel_valid_sync <= {pixel_valid_sync[1:0], csi_pixel_valid};
    end
    wire csi_pixel_valid_sys = pixel_valid_sync[2];

    //====================================================================
    // 9. 未使用信号抑制
    //====================================================================
    wire _unused = &{1'b0,
        jtag_inst1_DRCK, jtag_inst1_RUNTEST, jtag_inst1_TMS,
        pll_inst1_LOCKED, pll_inst2_LOCKED,
        pll_ddr_CLKOUT0, i_axi1_mem_clk,
        // 外部 PLL lock 输入（旧命名，与 peri.xml 硬块输出 pll_sys_LOCKED/
        // pll_ddr_LOCKED 不同的两条线）：peri.xml 没有这两个信号，悬空 tied 0。
        // 复位逻辑用 wrapper 内部 sys_pll_lock_int/ddr_pll_lock_int，
        // 它们同步的是真硬块 pll_sys_LOCKED / pll_ddr_LOCKED（见 §1 PLL 例化）。
        sys_pll_lock, ddr_pll_lock,
        ddr_inst_CTRL_CKE, ddr_inst_CTRL_CMD_Q_ALMOST_FULL,
        ddr_inst_CTRL_DP_IDLE, ddr_inst_RVALID_0, ddr_inst_RVALID_1,
        ddr_inst_BVALID_0, ddr_inst_BVALID_1,
        ddr_inst_ARREADY_0, ddr_inst_ARREADY_1,
        ddr_inst_AWREADY_0, ddr_inst_AWREADY_1,
        spi_data_2_write, spi_data_2_writeEnable,
        spi_data_3_write, spi_data_3_writeEnable,
        soc_sys_reset, soc_mem_reset,
        ddr_clk, ddr_rst_n,
        // Stage 2 CSI RX 输出（Stage 3 已用于 loopback；这些是观测残留）
        csi_pixel_per_clk, csi_shortpkt, csi_vc, csi_vcx,
        csi_word_count,
        csi_pixel_valid_sys,
        // Stage 3 CSI TX 拥塞观测 / safe-idle AXI ready（暂未接外部观测点）
        tx_skip_frame,
        ctxi_axi_awready, ctxi_axi_wready, ctxi_axi_bvalid,
        ctxi_axi_arready, ctxi_axi_rdata, ctxi_axi_rvalid,
        ctxi_irq_sys,
        // Stage 4 TSE MAC 链路速度观测（未接 LED）
        tse_eth_speed,
        // CSI RX 时钟线（DPHY 输出，本模块仅取作为时钟源）
        MIPI_REF_CLK,
        1'b0};

endmodule

`default_nettype wire
