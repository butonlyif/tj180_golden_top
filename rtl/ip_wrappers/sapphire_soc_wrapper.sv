`default_nettype none
`timescale 1ns / 1ps

//============================================================================
// 模块名称: sapphire_soc_wrapper
// 功能描述: Sapphire SoC IP 包装模块。封装 soc.v 复杂端口为分类总线，
//           便于顶层连线。内部仅做端口转发，无额外逻辑。
// 接口说明: AXI-A Master (32-bit) / JTAG / UART / SPI / I2C / GPIO / APB
// 设计约束: io_systemClk = sys_clk, io_asyncReset 为高有效复位
//============================================================================
module sapphire_soc_wrapper (
    // -- Clock & Reset --
    input  wire        clk_i,               // io_systemClk = sys_clk
    input  wire        arst_i,              // io_asyncReset（高有效！）
    output wire        sys_reset_o,         // io_systemReset

    // -- AXI-A Master (32-bit, 去 DDR 位宽桥) --
    output wire [31:0] axiA_awaddr_o,
    output wire [7:0]  axiA_awid_o,
    output wire [7:0]  axiA_awlen_o,
    output wire [2:0]  axiA_awsize_o,
    output wire [1:0]  axiA_awburst_o,
    output wire        axiA_awlock_o,
    output wire [3:0]  axiA_awcache_o,
    output wire [3:0]  axiA_awqos_o,
    output wire [2:0]  axiA_awprot_o,
    output wire [3:0]  axiA_awregion_o,
    output wire        axiA_awvalid_o,
    input  wire        axiA_awready_i,
    output wire        axiA_wvalid_o,
    output wire [31:0] axiA_wdata_o,
    output wire [3:0]  axiA_wstrb_o,
    output wire        axiA_wlast_o,
    input  wire        axiA_wready_i,
    input  wire        axiA_bvalid_i,
    output wire        axiA_bready_o,
    input  wire [7:0]  axiA_bid_i,
    input  wire [1:0]  axiA_bresp_i,
    output wire        axiA_arvalid_o,
    output wire [31:0] axiA_araddr_o,
    output wire [7:0]  axiA_arid_o,
    output wire [7:0]  axiA_arlen_o,
    output wire [2:0]  axiA_arsize_o,
    output wire [1:0]  axiA_arburst_o,
    output wire        axiA_arlock_o,
    output wire [3:0]  axiA_arcache_o,
    output wire [3:0]  axiA_arqos_o,
    output wire [2:0]  axiA_arprot_o,
    output wire [3:0]  axiA_arregion_o,
    input  wire        axiA_arready_i,
    input  wire        axiA_rvalid_i,
    output wire        axiA_rready_o,
    input  wire [31:0] axiA_rdata_i,
    input  wire [7:0]  axiA_rid_i,
    input  wire [1:0]  axiA_rresp_i,
    input  wire        axiA_rlast_i,

    // -- Interrupts --
    input  wire        user_interrupt_a_i,   // userInterruptA
    input  wire        axi_a_interrupt_i,    // axiAInterrupt

    // -- JTAG --
    input  wire        jtag_tck_i,
    input  wire        jtag_tdi_i,
    input  wire        jtag_enable_i,        // = jtag SEL
    input  wire        jtag_capture_i,
    input  wire        jtag_shift_i,
    input  wire        jtag_update_i,
    input  wire        jtag_reset_i,
    output wire        jtag_tdo_o,

    // -- UART --
    output wire        uart_txd_o,
    input  wire        uart_rxd_i,

    // -- SPI --
    output wire        spi_sclk_write_o,
    output wire [0:0]  spi_ss_o,
    output wire        spi_data_0_write_o,
    output wire        spi_data_0_writeEnable_o,
    input  wire        spi_data_0_read_i,
    output wire        spi_data_1_write_o,
    output wire        spi_data_1_writeEnable_o,
    input  wire        spi_data_1_read_i,
    output wire        spi_data_2_write_o,
    output wire        spi_data_2_writeEnable_o,
    input  wire        spi_data_2_read_i,
    output wire        spi_data_3_write_o,
    output wire        spi_data_3_writeEnable_o,
    input  wire        spi_data_3_read_i,

    // -- I2C --
    input  wire        i2c_scl_read_i,
    output wire        i2c_scl_write_o,
    input  wire        i2c_sda_read_i,
    output wire        i2c_sda_write_o,

    // -- GPIO --
    input  wire [3:0]  gpio_read_i,
    output wire [3:0]  gpio_write_o,
    output wire [3:0]  gpio_writeEnable_o,

    // -- APB Slave 0 (去外设配置总线, Stage 2+) --
    output wire [15:0] apb_paddr_o,
    output wire        apb_penable_o,
    output wire        apb_psel_o,
    output wire        apb_pwrite_o,
    output wire [31:0] apb_pwdata_o,
    input  wire [31:0] apb_prdata_i,
    input  wire        apb_pready_i,
    input  wire        apb_pslverror_i
);

    //==================================================================
    // SoC IP 实例化 — 纯端口转发
    //==================================================================
    soc u_soc (
        // -- Clock & Reset --
        .io_systemClk          (clk_i),
        .io_asyncReset         (arst_i),
        .io_systemReset        (sys_reset_o),

        // -- AXI-A Master --
        .axiA_awaddr           (axiA_awaddr_o),
        .axiA_awid             (axiA_awid_o),
        .axiA_awlen            (axiA_awlen_o),
        .axiA_awsize           (axiA_awsize_o),
        .axiA_awburst          (axiA_awburst_o),
        .axiA_awlock           (axiA_awlock_o),
        .axiA_awcache          (axiA_awcache_o),
        .axiA_awqos            (axiA_awqos_o),
        .axiA_awprot           (axiA_awprot_o),
        .axiA_awregion         (axiA_awregion_o),
        .axiA_awvalid          (axiA_awvalid_o),
        .axiA_awready          (axiA_awready_i),
        .axiA_wvalid           (axiA_wvalid_o),
        .axiA_wdata            (axiA_wdata_o),
        .axiA_wstrb            (axiA_wstrb_o),
        .axiA_wlast            (axiA_wlast_o),
        .axiA_wready           (axiA_wready_i),
        .axiA_bvalid           (axiA_bvalid_i),
        .axiA_bready           (axiA_bready_o),
        .axiA_bid              (axiA_bid_i),
        .axiA_bresp            (axiA_bresp_i),
        .axiA_arvalid          (axiA_arvalid_o),
        .axiA_araddr           (axiA_araddr_o),
        .axiA_arid             (axiA_arid_o),
        .axiA_arlen            (axiA_arlen_o),
        .axiA_arsize           (axiA_arsize_o),
        .axiA_arburst          (axiA_arburst_o),
        .axiA_arlock           (axiA_arlock_o),
        .axiA_arcache          (axiA_arcache_o),
        .axiA_arqos            (axiA_arqos_o),
        .axiA_arprot           (axiA_arprot_o),
        .axiA_arregion         (axiA_arregion_o),
        .axiA_arready          (axiA_arready_i),
        .axiA_rvalid           (axiA_rvalid_i),
        .axiA_rready           (axiA_rready_o),
        .axiA_rdata            (axiA_rdata_i),
        .axiA_rid              (axiA_rid_i),
        .axiA_rresp            (axiA_rresp_i),
        .axiA_rlast            (axiA_rlast_i),

        // -- Interrupts --
        .userInterruptA        (user_interrupt_a_i),
        .axiAInterrupt         (axi_a_interrupt_i),

        // -- JTAG --
        .jtagCtrl_tck          (jtag_tck_i),
        .jtagCtrl_tdi          (jtag_tdi_i),
        .jtagCtrl_enable       (jtag_enable_i),
        .jtagCtrl_capture      (jtag_capture_i),
        .jtagCtrl_shift        (jtag_shift_i),
        .jtagCtrl_update       (jtag_update_i),
        .jtagCtrl_reset        (jtag_reset_i),
        .jtagCtrl_tdo          (jtag_tdo_o),

        // -- UART --
        .system_uart_0_io_txd  (uart_txd_o),
        .system_uart_0_io_rxd  (uart_rxd_i),

        // -- SPI --
        .system_spi_0_io_sclk_write     (spi_sclk_write_o),
        .system_spi_0_io_ss             (spi_ss_o),
        .system_spi_0_io_data_0_write   (spi_data_0_write_o),
        .system_spi_0_io_data_0_writeEnable (spi_data_0_writeEnable_o),
        .system_spi_0_io_data_0_read    (spi_data_0_read_i),
        .system_spi_0_io_data_1_write   (spi_data_1_write_o),
        .system_spi_0_io_data_1_writeEnable (spi_data_1_writeEnable_o),
        .system_spi_0_io_data_1_read    (spi_data_1_read_i),
        .system_spi_0_io_data_2_write   (spi_data_2_write_o),
        .system_spi_0_io_data_2_writeEnable (spi_data_2_writeEnable_o),
        .system_spi_0_io_data_2_read    (spi_data_2_read_i),
        .system_spi_0_io_data_3_write   (spi_data_3_write_o),
        .system_spi_0_io_data_3_writeEnable (spi_data_3_writeEnable_o),
        .system_spi_0_io_data_3_read    (spi_data_3_read_i),

        // -- I2C --
        .system_i2c_0_io_scl_read    (i2c_scl_read_i),
        .system_i2c_0_io_scl_write   (i2c_scl_write_o),
        .system_i2c_0_io_sda_read    (i2c_sda_read_i),
        .system_i2c_0_io_sda_write   (i2c_sda_write_o),

        // -- GPIO --
        .system_gpio_0_io_read           (gpio_read_i),
        .system_gpio_0_io_write          (gpio_write_o),
        .system_gpio_0_io_writeEnable    (gpio_writeEnable_o),

        // -- APB Slave 0 --
        .io_apbSlave_0_PADDR     (apb_paddr_o),
        .io_apbSlave_0_PENABLE   (apb_penable_o),
        .io_apbSlave_0_PSEL      (apb_psel_o),
        .io_apbSlave_0_PWRITE    (apb_pwrite_o),
        .io_apbSlave_0_PWDATA    (apb_pwdata_o),
        .io_apbSlave_0_PRDATA    (apb_prdata_i),
        .io_apbSlave_0_PREADY    (apb_pready_i),
        .io_apbSlave_0_PSLVERROR (apb_pslverror_i)
    );

endmodule

`default_nettype wire
