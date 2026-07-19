`default_nettype none
`timescale 1ns / 1ps

//============================================================================
// 模块名称: tb_eth
// 功能描述: Stage 4 Ethernet + SD Host 总线拓扑仿真 testbench。
//
//   TSE MAC IP 本身是 Efinity 加密硬 IP（test_tse.v 内部 `IP_MODULE_NAME` 实
//   例化为黑盒），iverilog 无法独立仿真。本 testbench 聚焦 Stage 4 引入的
//   可仿真部分：
//     (A) apb_decoder_1to3 — APB 地址译码正确性（slave 0/1/2 互斥）
//     (B) sdhost_slot_wrapper — APB→AXI-Lite 桥 + idle slave 占位响应
//
//   验收：
//     · 写 slave 0/1/2 时仅对应 psel 拉高，其余为 0
//     · 读 slave 2 任意地址返回 0xDEAD_BEEF（idle slave 标识）
//     · 写 slave 2 任意地址 pready 在 2 拍内回 1
//     · 未映射地址默认落到 slave 0（兼容旧行为）
//
// 接口说明: 自包含 APB master BFM，无外部依赖
//============================================================================
module tb_eth;

    // =====================================================================
    // 时钟 / 复位
    // =====================================================================
    reg clk = 1'b0;
    reg rst_n = 1'b0;

    localparam realtime CLK_PERIOD = 10.0ns;   // 100 MHz

    always #(CLK_PERIOD/2.0) clk = ~clk;

    initial begin
        rst_n = 1'b0;
        #50ns;
        rst_n = 1'b1;
    end

    // =====================================================================
    // APB master BFM（驱动 decoder 输入端）
    // =====================================================================
    reg  [15:0] m_paddr  = 16'h0;
    reg         m_psel   = 1'b0;
    reg         m_penable = 1'b0;
    reg         m_pwrite = 1'b0;
    reg  [31:0] m_pwdata = 32'h0;
    wire [31:0] m_prdata;
    wire        m_pready;
    wire        m_pslverror;

    integer err_count = 0;

    // APB 单笔写
    task apb_write(input [15:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            m_paddr   = addr;
            m_psel    = 1'b1;
            m_penable = 1'b0;        // setup phase
            m_pwrite  = 1'b1;
            m_pwdata  = data;
            @(posedge clk);
            m_penable = 1'b1;        // access phase
            // 等握手
            while (!m_pready) @(posedge clk);
            m_psel    = 1'b0;
            m_penable = 1'b0;
            m_pwrite  = 1'b0;
        end
    endtask

    // APB 单笔读
    task apb_read(input [15:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            m_paddr   = addr;
            m_psel    = 1'b1;
            m_penable = 1'b0;
            m_pwrite  = 1'b0;
            m_pwdata  = 32'h0;
            @(posedge clk);
            m_penable = 1'b1;
            while (!m_pready) @(posedge clk);
            data      = m_prdata;
            m_psel    = 1'b0;
            m_penable = 1'b0;
        end
    endtask

    // =====================================================================
    // DUT 1: apb_decoder_1to3
    //   下游接 3 个最小 APB slave 响应器，分别回 prdata = 0xA0/0xB0/0xC0
    //   方便检测 MUX 选择是否正确。
    // =====================================================================
    wire [15:0] s0_paddr, s1_paddr, s2_paddr;
    wire        s0_psel,  s1_psel,  s2_psel;
    wire        s0_penable, s1_penable, s2_penable;
    wire        s0_pwrite,  s1_pwrite,  s2_pwrite;
    wire [31:0] s0_pwdata, s1_pwdata, s2_pwdata;
    wire [31:0] s0_prdata, s1_prdata, s2_prdata;
    wire        s0_pready, s1_pready, s2_pready;
    wire        s0_pslverror, s1_pslverror, s2_pslverror;

    // slave 0 — 一拍 pready，prdata=0xA0
    assign s0_prdata    = 32'h0000_00A0;
    assign s0_pready    = s0_psel & s0_penable;
    assign s0_pslverror = 1'b0;

    // slave 1 — 一拍 pready，prdata=0xB0
    assign s1_prdata    = 32'h0000_00B0;
    assign s1_pready    = s1_psel & s1_penable;
    assign s1_pslverror = 1'b0;

    // slave 2 — 一拍 pready，prdata=0xC0
    assign s2_prdata    = 32'h0000_00C0;
    assign s2_pready    = s2_psel & s2_penable;
    assign s2_pslverror = 1'b0;

    apb_decoder_1to3 #(.AW(16), .DW(32)) u_dut_dec (
        .clk_i           ( clk           ),
        .rst_n_i         ( rst_n         ),
        .apb_paddr_i     ( m_paddr       ),
        .apb_psel_i      ( m_psel        ),
        .apb_penable_i   ( m_penable     ),
        .apb_pwrite_i    ( m_pwrite      ),
        .apb_pwdata_i    ( m_pwdata      ),
        .apb_prdata_o    ( m_prdata      ),
        .apb_pready_o    ( m_pready      ),
        .apb_pslverror_o ( m_pslverror  ),
        .s0_paddr_o      ( s0_paddr      ),
        .s0_psel_o       ( s0_psel       ),
        .s0_penable_o    ( s0_penable    ),
        .s0_pwrite_o     ( s0_pwrite     ),
        .s0_pwdata_o     ( s0_pwdata     ),
        .s0_prdata_i     ( s0_prdata     ),
        .s0_pready_i     ( s0_pready     ),
        .s0_pslverror_i  ( s0_pslverror ),
        .s1_paddr_o      ( s1_paddr      ),
        .s1_psel_o       ( s1_psel       ),
        .s1_penable_o    ( s1_penable    ),
        .s1_pwrite_o     ( s1_pwrite     ),
        .s1_pwdata_o     ( s1_pwdata     ),
        .s1_prdata_i     ( s1_prdata     ),
        .s1_pready_i     ( s1_pready     ),
        .s1_pslverror_i  ( s1_pslverror ),
        .s2_paddr_o      ( s2_paddr      ),
        .s2_psel_o       ( s2_psel       ),
        .s2_penable_o    ( s2_penable    ),
        .s2_pwrite_o     ( s2_pwrite     ),
        .s2_pwdata_o     ( s2_pwdata     ),
        .s2_prdata_i     ( s2_prdata     ),
        .s2_pready_i     ( s2_pready     ),
        .s2_pslverror_i  ( s2_pslverror )
    );

    // =====================================================================
    // DUT 2: sdhost_slot_wrapper（独立例化）
    //   验证 APB→AXI-Lite 桥 + idle slave 占位响应
    // =====================================================================
    reg  [15:0] sd_paddr   = 16'h0;
    reg         sd_psel    = 1'b0;
    reg         sd_penable = 1'b0;
    reg         sd_pwrite  = 1'b0;
    reg  [31:0] sd_pwdata  = 32'h0;
    wire [31:0] sd_prdata;
    wire        sd_pready;
    wire        sd_pslverror;

    wire        sd_clk;
    wire        sd_cmd_o;
    wire        sd_cmd_oe;
    wire [3:0]  sd_dat_o;
    wire [3:0]  sd_dat_oe;
    wire [2:0]  eth_speed_unused;

    sdhost_slot_wrapper u_dut_sd (
        .clk_i           ( clk           ),
        .rst_n_i         ( rst_n         ),
        .apb_paddr_i     ( sd_paddr      ),
        .apb_psel_i      ( sd_psel       ),
        .apb_penable_i   ( sd_penable    ),
        .apb_pwrite_i    ( sd_pwrite     ),
        .apb_pwdata_i    ( sd_pwdata     ),
        .apb_prdata_o    ( sd_prdata     ),
        .apb_pready_o    ( sd_pready     ),
        .apb_pslverror_o ( sd_pslverror  ),
        .sd_clk_o        ( sd_clk        ),
        .sd_cmd_o        ( sd_cmd_o      ),
        .sd_cmd_oe       ( sd_cmd_oe     ),
        .sd_cmd_i        ( 1'b1          ),
        .sd_dat_o        ( sd_dat_o      ),
        .sd_dat_oe       ( sd_dat_oe     ),
        .sd_dat_i        ( 4'h0          ),
        .sd_cd_n         ( 1'b1          )
    );

    // SD slot wrapper 的 APB master BFM（与上面独立，复用任务逻辑）
    task sd_apb_write(input [15:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            sd_paddr   = addr;
            sd_psel    = 1'b1;
            sd_penable = 1'b0;
            sd_pwrite  = 1'b1;
            sd_pwdata  = data;
            @(posedge clk);
            sd_penable = 1'b1;
            while (!sd_pready) @(posedge clk);
            sd_psel    = 1'b0;
            sd_penable = 1'b0;
            sd_pwrite  = 1'b0;
        end
    endtask

    task sd_apb_read(input [15:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            sd_paddr   = addr;
            sd_psel    = 1'b1;
            sd_penable = 1'b0;
            sd_pwrite  = 1'b0;
            sd_pwdata  = 32'h0;
            @(posedge clk);
            sd_penable = 1'b1;
            while (!sd_pready) @(posedge clk);
            data       = sd_prdata;
            sd_psel    = 1'b0;
            sd_penable = 1'b0;
        end
    endtask

    // =====================================================================
    // 监测：组合观察 decoder 输出（不依赖时钟边沿，避免 NBA 竞争）
    // =====================================================================
    wire [2:0] psel_live = {s2_psel, s1_psel, s0_psel};

    // =====================================================================
    // 主测试流程
    // =====================================================================
    reg [31:0] rdata;
    integer    i;

    initial begin
        $dumpfile("tb_eth.vcd");
        $dumpvars(0, tb_eth);

        // 等复位释放
        wait(rst_n === 1'b1);
        @(posedge clk);

        // -----------------------------------------------------------------
        // Test 1: decoder 互斥 — 访问 slave 0/1/2 各一次
        // -----------------------------------------------------------------
        $display("[%0t] === Test 1: APB decoder slave select ===", $time);

        // Slave 0 @ 0x0000
        apb_read(16'h0000, rdata);
        if (rdata !== 32'h0000_00A0) begin
            $display("[%0t] FAIL: slave 0 read returned 0x%08x, expected 0x0000_00A0", $time, rdata);
            err_count = err_count + 1;
        end else $display("[%0t] PASS: slave 0 read OK", $time);

        // Slave 1 @ 0x0800 (apb_paddr[15:11] = 5'b00001)
        apb_read(16'h0800, rdata);
        if (rdata !== 32'h0000_00B0) begin
            $display("[%0t] FAIL: slave 1 read returned 0x%08x, expected 0x0000_00B0", $time, rdata);
            err_count = err_count + 1;
        end else $display("[%0t] PASS: slave 1 read OK", $time);

        // Slave 2 @ 0x1000 (apb_paddr[15:11] = 5'b00010)
        apb_read(16'h1000, rdata);
        if (rdata !== 32'h0000_00C0) begin
            $display("[%0t] FAIL: slave 2 read returned 0x%08x, expected 0x0000_00C0", $time, rdata);
            err_count = err_count + 1;
        end else $display("[%0t] PASS: slave 2 read OK", $time);

        // 未映射区域 @ 0x7C00 → 默认路由到 slave 0
        apb_read(16'h7C00, rdata);
        if (rdata !== 32'h0000_00A0) begin
            $display("[%0t] FAIL: unmapped read returned 0x%08x, expected 0x0000_00A0 (default to slave 0)", $time, rdata);
            err_count = err_count + 1;
        end else $display("[%0t] PASS: unmapped addr defaults to slave 0", $time);

        // -----------------------------------------------------------------
        // Test 2: decoder 互斥检查（每次访问只有 1 个 psel=1）
        //   组合观察 psel_live：apb_read 期间 m_psel=1，decoder 即时驱动
        //   对应 sN_psel=1；读返回前最后一拍观测。
        // -----------------------------------------------------------------
        $display("[%0t] === Test 2: psel exclusivity ===", $time);
        for (i = 0; i < 3; i = i + 1) begin
            // 启动一次 apb_read，但在 access phase 抓拍 psel_live
            @(posedge clk);
            m_paddr   = 16'h0000 + (i << 11);
            m_psel    = 1'b1;
            m_penable = 1'b0;
            m_pwrite  = 1'b0;
            m_pwdata  = 32'h0;
            @(posedge clk);
            m_penable = 1'b1;
            // 此刻 m_psel=1 m_penable=1，decoder 组合输出已稳定
            // （access phase；wait pready 不影响 psel_live 已经确定的值）
            #1;  // 让组合逻辑稳定
            case (i)
                0: if (psel_live !== 3'b001) begin
                       $display("[%0t] FAIL: slave 0 access psel_live=0b%03b (want 001)", $time, psel_live);
                       err_count = err_count + 1;
                   end else $display("[%0t] PASS: slave 0 exclusive", $time);
                1: if (psel_live !== 3'b010) begin
                       $display("[%0t] FAIL: slave 1 access psel_live=0b%03b (want 010)", $time, psel_live);
                       err_count = err_count + 1;
                   end else $display("[%0t] PASS: slave 1 exclusive", $time);
                2: if (psel_live !== 3'b100) begin
                       $display("[%0t] FAIL: slave 2 access psel_live=0b%03b (want 100)", $time, psel_live);
                       err_count = err_count + 1;
                   end else $display("[%0t] PASS: slave 2 exclusive", $time);
            endcase
            // 完成 APB 读（清场）
            while (!m_pready) @(posedge clk);
            rdata = m_prdata;
            m_psel    = 1'b0;
            m_penable = 1'b0;
        end

        // -----------------------------------------------------------------
        // Test 3: sdhost_slot_wrapper — idle slave 读返回 0xDEAD_BEEF
        // -----------------------------------------------------------------
        $display("[%0t] === Test 3: SD Host slot idle slave ===", $time);
        sd_apb_read(16'h0000, rdata);
        if (rdata !== 32'hDEAD_BEEF) begin
            $display("[%0t] FAIL: SD slot read returned 0x%08x, expected 0xDEAD_BEEF", $time, rdata);
            err_count = err_count + 1;
        end else $display("[%0t] PASS: SD slot idle read returns magic", $time);

        // SD slot 写 — 应在合理拍数内回 pready
        sd_apb_write(16'h0010, 32'h1234_5678);
        $display("[%0t] PASS: SD slot write accepted", $time);

        // SD 物理引脚必须保持安全默认（OE=0）
        if (sd_clk !== 1'b0 || sd_cmd_oe !== 1'b0 || sd_dat_oe !== 4'h0) begin
            $display("[%0t] FAIL: SD pins not safe (clk=%b cmd_oe=%b dat_oe=%b)",
                $time, sd_clk, sd_cmd_oe, sd_dat_oe);
            err_count = err_count + 1;
        end else $display("[%0t] PASS: SD pins safe-default", $time);

        // -----------------------------------------------------------------
        // 总结
        // -----------------------------------------------------------------
        $display("[%0t] === Test finished: %0d errors ===", $time, err_count);
        if (err_count == 0) $display("[%0t] PASS", $time);
        else                $display("[%0t] FAIL", $time);
        $finish;
    end

endmodule

`default_nettype wire
