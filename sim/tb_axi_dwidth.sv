`default_nettype none
`timescale 1ns / 1ps

//============================================================================
// 模块名称: tb_axi_dwidth
// 功能描述: axi_dwidth_converter 的 iverilog 仿真 testbench。
//   DUT：axi_dwidth_converter（M_DW=32 / S_DW=512）。
//   下游（S 侧）：行为级 512-bit AXI4 从设备，背后 256 个 wide-word 内存数组，
//                 支持 wide 写（按 WSTRB 合并）+ wide 读（返回 1 拍 wide R）。
//   上游（M 侧）：自包含 AXI4 主控 BFM，提供 32-bit 单拍写/读与 16-beat 突发。
//
//   验收用例：
//     T1: 单 dword 写 base+0x00 → 读回比对
//     T2: 单 dword 写 base+0x14（dword 5 偏移）→ 读回比对
//     T3: 16-beat cache line 写（对齐 base+0x1000）→ 16-beat 读回逐拍比对
//     T4: 单 dword 写 base+0x0C（dword 3，非 4 字节对齐字节）→ 读回比对
// 接口说明: 自包含，无外部依赖
//============================================================================
module tb_axi_dwidth;

    //==================================================================
    // 参数
    //==================================================================
    localparam M_DW   = 32;
    localparam S_DW   = 512;
    localparam M_AW   = 32;
    localparam S_AW   = 33;
    localparam M_IDW  = 8;
    localparam S_IDW  = 6;
    localparam RATIO  = S_DW / M_DW;        // 16
    localparam MEM_WWORDS = 256;            // 256 wide-words = 16 KB

    //==================================================================
    // 时钟 / 复位
    //==================================================================
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    localparam realtime CLK_PERIOD = 10.0ns;   // 100 MHz
    always #(CLK_PERIOD/2.0) clk = ~clk;
    initial begin
        rst_n = 1'b0;
        #50ns;
        rst_n = 1'b1;
    end

    integer err_count = 0;

    //==================================================================
    // Manager (M 侧) 驱动信号
    //==================================================================
    reg  [M_IDW-1:0] m_awid    = 0;
    reg  [M_AW-1:0]  m_awaddr  = 0;
    reg  [7:0]       m_awlen   = 0;
    reg  [2:0]       m_awsize  = 3'd2;     // 4 字节
    reg  [1:0]       m_awburst = 2'b01;    // INCR
    reg              m_awlock  = 1'b0;
    reg  [3:0]       m_awcache = 4'b0000;
    reg  [2:0]       m_awprot  = 3'b000;
    reg  [3:0]       m_awqos   = 4'b0000;
    reg              m_awvalid = 1'b0;
    wire             m_awready;

    reg  [M_DW-1:0]  m_wdata   = 0;
    reg  [M_DW/8-1:0] m_wstrb  = 4'hF;
    reg              m_wlast   = 1'b0;
    reg              m_wvalid  = 1'b0;
    wire             m_wready;

    wire [M_IDW-1:0] m_bid;
    wire [1:0]       m_bresp;
    wire             m_bvalid;
    reg              m_bready  = 1'b1;

    reg  [M_IDW-1:0] m_arid    = 0;
    reg  [M_AW-1:0]  m_araddr  = 0;
    reg  [7:0]       m_arlen   = 0;
    reg  [2:0]       m_arsize  = 3'd2;
    reg  [1:0]       m_arburst = 2'b01;
    reg              m_arlock  = 1'b0;
    reg  [3:0]       m_arcache = 4'b0000;
    reg  [2:0]       m_arprot  = 3'b000;
    reg  [3:0]       m_arqos   = 4'b0000;
    reg              m_arvalid = 1'b0;
    wire             m_arready;

    wire [M_IDW-1:0] m_rid;
    wire [M_DW-1:0]  m_rdata;
    wire [1:0]       m_rresp;
    wire             m_rlast;
    wire             m_rvalid;
    reg              m_rready  = 1'b1;

    //==================================================================
    // Subordinate (S 侧) —— DUT 驱动，BFM 接收
    //==================================================================
    wire [S_IDW-1:0] s_awid;
    wire [S_AW-1:0]  s_awaddr;
    wire [7:0]       s_awlen;
    wire [2:0]       s_awsize;
    wire [1:0]       s_awburst;
    wire             s_awlock;
    wire [3:0]       s_awcache;
    wire [2:0]       s_awprot;
    wire [3:0]       s_awqos;
    wire             s_awvalid;
    reg              s_awready = 1'b0;

    wire [S_DW-1:0]  s_wdata;
    wire [S_DW/8-1:0] s_wstrb;
    wire             s_wlast;
    wire             s_wvalid;
    reg              s_wready = 1'b0;

    reg  [S_IDW-1:0] s_bid    = 0;
    reg  [1:0]       s_bresp  = 2'b00;     // OKAY
    reg              s_bvalid = 1'b0;
    wire             s_bready;

    wire [S_IDW-1:0] s_arid;
    wire [S_AW-1:0]  s_araddr;
    wire [7:0]       s_arlen;
    wire [2:0]       s_arsize;
    wire [1:0]       s_arburst;
    wire             s_arlock;
    wire [3:0]       s_arcache;
    wire [2:0]       s_arprot;
    wire [3:0]       s_arqos;
    wire             s_arvalid;
    reg              s_arready = 1'b0;

    reg  [S_IDW-1:0] s_rid    = 0;
    reg  [S_DW-1:0]  s_rdata  = 0;
    reg  [1:0]       s_rresp  = 2'b00;
    reg              s_rlast  = 1'b0;
    reg              s_rvalid = 1'b0;
    wire             s_rready;

    //==================================================================
    // DUT
    //==================================================================
    axi_dwidth_converter #(
        .M_DW  ( M_DW  ),
        .S_DW  ( S_DW  ),
        .M_AW  ( M_AW  ),
        .S_AW  ( S_AW  ),
        .M_IDW ( M_IDW ),
        .S_IDW ( S_IDW )
    ) u_dut (
        .clk_i           ( clk      ),
        .rst_n_i         ( rst_n    ),

        // M 侧
        .m_axi_awid_i    ( m_awid   ),
        .m_axi_awaddr_i  ( m_awaddr ),
        .m_axi_awlen_i   ( m_awlen  ),
        .m_axi_awsize_i  ( m_awsize ),
        .m_axi_awburst_i ( m_awburst),
        .m_axi_awlock_i  ( m_awlock ),
        .m_axi_awcache_i ( m_awcache),
        .m_axi_awprot_i  ( m_awprot ),
        .m_axi_awqos_i   ( m_awqos  ),
        .m_axi_awvalid_i ( m_awvalid),
        .m_axi_awready_o ( m_awready),
        .m_axi_wdata_i   ( m_wdata  ),
        .m_axi_wstrb_i   ( m_wstrb  ),
        .m_axi_wlast_i   ( m_wlast  ),
        .m_axi_wvalid_i  ( m_wvalid ),
        .m_axi_wready_o  ( m_wready),
        .m_axi_bid_o     ( m_bid    ),
        .m_axi_bresp_o   ( m_bresp  ),
        .m_axi_bvalid_o  ( m_bvalid ),
        .m_axi_bready_i  ( m_bready ),
        .m_axi_arid_i    ( m_arid   ),
        .m_axi_araddr_i  ( m_araddr ),
        .m_axi_arlen_i   ( m_arlen  ),
        .m_axi_arsize_i  ( m_arsize ),
        .m_axi_arburst_i ( m_arburst),
        .m_axi_arlock_i  ( m_arlock ),
        .m_axi_arcache_i ( m_arcache),
        .m_axi_arprot_i  ( m_arprot ),
        .m_axi_arqos_i   ( m_arqos  ),
        .m_axi_arvalid_i ( m_arvalid),
        .m_axi_arready_o ( m_arready),
        .m_axi_rid_o     ( m_rid    ),
        .m_axi_rdata_o   ( m_rdata  ),
        .m_axi_rresp_o   ( m_rresp  ),
        .m_axi_rlast_o   ( m_rlast  ),
        .m_axi_rvalid_o  ( m_rvalid ),
        .m_axi_rready_i  ( m_rready ),

        // S 侧
        .s_axi_awid_o    ( s_awid    ),
        .s_axi_awaddr_o  ( s_awaddr  ),
        .s_axi_awlen_o   ( s_awlen   ),
        .s_axi_awsize_o  ( s_awsize  ),
        .s_axi_awburst_o ( s_awburst ),
        .s_axi_awlock_o  ( s_awlock  ),
        .s_axi_awcache_o ( s_awcache ),
        .s_axi_awprot_o  ( s_awprot  ),
        .s_axi_awqos_o   ( s_awqos   ),
        .s_axi_awvalid_o ( s_awvalid ),
        .s_axi_awready_i ( s_awready ),
        .s_axi_wdata_o   ( s_wdata   ),
        .s_axi_wstrb_o   ( s_wstrb   ),
        .s_axi_wlast_o   ( s_wlast   ),
        .s_axi_wvalid_o  ( s_wvalid  ),
        .s_axi_wready_i  ( s_wready  ),
        .s_axi_bid_i     ( s_bid     ),
        .s_axi_bresp_i   ( s_bresp   ),
        .s_axi_bvalid_i  ( s_bvalid  ),
        .s_axi_bready_o  ( s_bready  ),
        .s_axi_arid_o    ( s_arid    ),
        .s_axi_araddr_o  ( s_araddr  ),
        .s_axi_arlen_o   ( s_arlen   ),
        .s_axi_arsize_o  ( s_arsize  ),
        .s_axi_arburst_o ( s_arburst ),
        .s_axi_arlock_o  ( s_arlock  ),
        .s_axi_arcache_o ( s_arcache ),
        .s_axi_arprot_o  ( s_arprot  ),
        .s_axi_arqos_o   ( s_arqos   ),
        .s_axi_arvalid_o ( s_arvalid ),
        .s_axi_arready_i ( s_arready ),
        .s_axi_rid_i     ( s_rid     ),
        .s_axi_rdata_i   ( s_rdata   ),
        .s_axi_rresp_i   ( s_rresp   ),
        .s_axi_rlast_i   ( s_rlast   ),
        .s_axi_rvalid_i  ( s_rvalid  ),
        .s_axi_rready_o  ( s_rready  )
    );

    //==================================================================
    // 行为级 512-bit AXI 从设备
    //   内存模型：MEM_WWORDS 个 wide-word，按 wide-word 地址索引
    //   写：当 s_awvalid&s_awready 时锁存 wide addr；当 s_wvalid&s_wready
    //       时按 WSTRB 合并到 MEM；回 B。
    //   读：当 s_arvalid&s_arready 时锁存 wide addr，下一拍回 R。
    //==================================================================
    reg [S_DW-1:0] mem [0:MEM_WWORDS-1];
    integer wint_ri;
    initial begin
        for (wint_ri = 0; wint_ri < MEM_WWORDS; wint_ri = wint_ri + 1)
            mem[wint_ri] = {S_DW{1'b0}};
    end

    // wide-word 索引（取地址高位）
    wire [S_AW-1:0] s_awaddr_word = s_awaddr;
    wire [S_AW-1:0] s_araddr_word = s_araddr;

    reg [S_AW-1:0] aw_addr_held;
    reg [S_AW-1:0] ar_addr_held;

    // AW 通道：1 拍 ready 脉冲（s_awvalid 抬起后下一拍回 ready）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_awready <= 1'b0;
            aw_addr_held <= {S_AW{1'b0}};
        end else begin
            s_awready <= 1'b0;
            if (s_awvalid && !s_awready) begin
                s_awready <= 1'b1;
                aw_addr_held <= s_awaddr;
            end
        end
    end

    // W 通道：1 拍 ready 脉冲（s_wvalid 抬起后下一拍回 ready，不依赖 B）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_wready <= 1'b0;
        end else begin
            s_wready <= 1'b0;
            if (s_wvalid && !s_wready) begin
                s_wready <= 1'b1;
            end
        end
    end

    // 在 W 握手时合并到 mem，并触发 B（B 保持直到 s_bready）
    integer mi;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_bvalid <= 1'b0;
            s_bid    <= {S_IDW{1'b0}};
            s_bresp  <= 2'b00;
        end else begin
            if (s_bvalid && s_bready) s_bvalid <= 1'b0;
            if (s_wvalid && s_wready) begin
                // 合并 wide W 到 mem[aw_addr_held >> 6]
                for (mi = 0; mi < S_DW/8; mi = mi + 1) begin
                    if (s_wstrb[mi])
                        mem[aw_addr_held[S_AW-1:6]][mi*8 +: 8] <= s_wdata[mi*8 +: 8];
                end
                // 回 B
                s_bid    <= s_awid;
                s_bresp  <= 2'b00;
                s_bvalid <= 1'b1;
            end
        end
    end

    // AR 通道：1 拍 ready 脉冲，握手后下一拍发 wide R（保持直到 s_rready）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_arready <= 1'b0;
            ar_addr_held <= {S_AW{1'b0}};
            s_rvalid <= 1'b0;
            s_rdata  <= {S_DW{1'b0}};
            s_rid    <= {S_IDW{1'b0}};
            s_rresp  <= 2'b00;
            s_rlast  <= 1'b0;
        end else begin
            s_arready <= 1'b0;
            if (s_arvalid && !s_arready && !s_rvalid) begin
                s_arready <= 1'b1;
                ar_addr_held <= s_araddr;
            end
            // 握手后下一拍发 R
            if (s_arvalid && s_arready) begin
                s_rdata  <= mem[ar_addr_held[S_AW-1:6]];
                s_rid    <= s_arid;
                s_rresp  <= 2'b00;
                s_rlast  <= 1'b1;
                s_rvalid <= 1'b1;
            end else if (s_rvalid && s_rready) begin
                s_rvalid <= 1'b0;
            end
        end
    end

    //==================================================================
    // Manager BFM tasks（驱动 32-bit M 侧）
    //==================================================================

    // 单 dword 写（AWLEN=0，1 拍 W）
    task axi_write_single(input [M_AW-1:0] addr, input [M_DW-1:0] data);
        begin
            @(posedge clk);
            m_awid    = 8'h01;
            m_awaddr  = addr;
            m_awlen   = 8'd0;          // 1 beat
            m_awsize  = 3'd2;
            m_awburst = 2'b01;
            m_awvalid = 1'b1;
            // W 同拍起来
            m_wdata   = data;
            m_wstrb   = 4'hF;
            m_wlast   = 1'b1;
            m_wvalid  = 1'b1;
            // 等握手
            while (!(m_awvalid && m_awready)) @(posedge clk);
            m_awvalid = 1'b0;
            while (!(m_wvalid && m_wready)) @(posedge clk);
            m_wvalid = 1'b0;
            // 等 B
            while (!(m_bvalid && m_bready)) @(posedge clk);
            if (m_bresp != 2'b00) begin
                $display("  [ERR] write_single @0x%08x bresp=%0d", addr, m_bresp);
                err_count = err_count + 1;
            end
        end
    endtask

    // 16-beat cache line 写（AWLEN=15，对齐 base）
    //   关键：每拍数据在握手后立即推进下一拍（不额外保持），否则当 subordinate
    //   持续 ready 时同一拍会被消费两次 → 数据写进相邻两个 dword。
    task axi_write_line(input [M_AW-1:0] base, input [M_DW-1:0] seed);
        integer k;
        begin
            @(posedge clk);
            m_awid    = 8'h02;
            m_awaddr  = base;
            m_awlen   = 8'd15;         // 16 beats
            m_awsize  = 3'd2;
            m_awburst = 2'b01;
            m_awvalid = 1'b1;
            // 先把 AW 握掉
            while (!(m_awvalid && m_awready)) @(posedge clk);
            m_awvalid = 1'b0;
            // 逐拍 W：每拍呈现一个 cycle，握手后才推进
            for (k = 0; k < 16; k = k + 1) begin
                m_wdata  = seed + k;
                m_wstrb  = 4'hF;
                m_wlast  = (k == 15);
                m_wvalid = 1'b1;
                @(posedge clk);
                while (!(m_wvalid && m_wready)) @(posedge clk);
            end
            m_wvalid = 1'b0;
            // 等 B
            while (!(m_bvalid && m_bready)) @(posedge clk);
            if (m_bresp != 2'b00) begin
                $display("  [ERR] write_line @0x%08x bresp=%0d", base, m_bresp);
                err_count = err_count + 1;
            end
        end
    endtask

    // 单 dword 读，返回数据
    task axi_read_single(input [M_AW-1:0] addr, output [M_DW-1:0] data);
        begin
            @(posedge clk);
            m_arid    = 8'h03;
            m_araddr  = addr;
            m_arlen   = 8'd0;
            m_arsize  = 3'd2;
            m_arburst = 2'b01;
            m_arvalid = 1'b1;
            while (!(m_arvalid && m_arready)) @(posedge clk);
            m_arvalid = 1'b0;
            // 等 R（1 拍）
            while (!(m_rvalid && m_rready)) @(posedge clk);
            data = m_rdata;
            if (m_rresp != 2'b00) begin
                $display("  [ERR] read_single @0x%08x rresp=%0d", addr, m_rresp);
                err_count = err_count + 1;
            end
            if (!m_rlast) begin
                $display("  [ERR] read_single @0x%08x rlast not set on single beat", addr);
                err_count = err_count + 1;
            end
        end
    endtask

    // 16-beat cache line 读，逐拍比对
    task axi_read_line_check(input [M_AW-1:0] base, input [M_DW-1:0] seed);
        integer k;
        reg [M_DW-1:0] expd;
        reg [M_DW-1:0] got;
        begin
            @(posedge clk);
            m_arid    = 8'h04;
            m_araddr  = base;
            m_arlen   = 8'd15;
            m_arsize  = 3'd2;
            m_arburst = 2'b01;
            m_arvalid = 1'b1;
            while (!(m_arvalid && m_arready)) @(posedge clk);
            m_arvalid = 1'b0;
            for (k = 0; k < 16; k = k + 1) begin
                while (!(m_rvalid && m_rready)) @(posedge clk);
                got = m_rdata;
                expd = seed + k;
                if (got !== expd) begin
                    $display("  [ERR] read_line @0x%08x beat %0d: got=0x%08x exp=0x%08x",
                             base, k, got, expd);
                    err_count = err_count + 1;
                end
                if ((k == 15) && !m_rlast) begin
                    $display("  [ERR] read_line @0x%08x last beat rlast not set", base);
                    err_count = err_count + 1;
                end
                @(posedge clk);
            end
        end
    endtask

    //==================================================================
    // 主激励
    //==================================================================
    reg [M_DW-1:0] rdat;
    initial begin
        // 等复位释放 + 几拍稳定
        wait(rst_n === 1'b1);
        @(posedge clk); @(posedge clk);

        //----------------------------------------------------------
        $display("== T1: single dword write/read @ 0x0000_0000 (dword 0) ==");
        axi_write_single(32'h0000_0000, 32'hDEAD_BEEF);
        axi_read_single (32'h0000_0000, rdat);
        if (rdat !== 32'hDEAD_BEEF) begin
            $display("  [ERR] T1 readback: got=0x%08x exp=0xDEADBEEF", rdat);
            err_count = err_count + 1;
        end else $display("  [OK]  T1 readback = 0x%08x", rdat);

        //----------------------------------------------------------
        $display("== T2: single dword write/read @ 0x0000_0014 (dword 5) ==");
        axi_write_single(32'h0000_0014, 32'hCAFE_BABE);   // dword 5
        axi_read_single (32'h0000_0014, rdat);
        if (rdat !== 32'hCAFE_BABE) begin
            $display("  [ERR] T2 readback: got=0x%08x exp=0xCAFEBABE", rdat);
            err_count = err_count + 1;
        end else $display("  [OK]  T2 readback = 0x%08x", rdat);

        //----------------------------------------------------------
        $display("== T3: 16-beat cache line write/read @ 0x0000_1000 ==");
        axi_write_line        (32'h0000_1000, 32'h1000_0000);
        axi_read_line_check   (32'h0000_1000, 32'h1000_0000);
        if (err_count == 0) $display("  [OK]  T3 16-beat line round-trip");

        //----------------------------------------------------------
        $display("== T4: single dword write/read @ 0x0000_000C (dword 3) ==");
        axi_write_single(32'h0000_000C, 32'h1234_5678);   // dword 3
        axi_read_single (32'h0000_000C, rdat);
        if (rdat !== 32'h1234_5678) begin
            $display("  [ERR] T4 readback: got=0x%08x exp=0x12345678", rdat);
            err_count = err_count + 1;
        end else $display("  [OK]  T4 readback = 0x%08x", rdat);

        //----------------------------------------------------------
        // 验证 dword 0/3/5 在同一 wide-word 内不互相干扰
        $display("== T5: neighbor isolation — re-read dword 0/3/5 ==");
        axi_read_single(32'h0000_0000, rdat);
        if (rdat !== 32'hDEAD_BEEF) begin
            $display("  [ERR] T5 dword0 corrupted: got=0x%08x", rdat);
            err_count = err_count + 1;
        end
        axi_read_single(32'h0000_000C, rdat);
        if (rdat !== 32'h1234_5678) begin
            $display("  [ERR] T5 dword3 corrupted: got=0x%08x", rdat);
            err_count = err_count + 1;
        end
        axi_read_single(32'h0000_0014, rdat);
        if (rdat !== 32'hCAFE_BABE) begin
            $display("  [ERR] T5 dword5 corrupted: got=0x%08x", rdat);
            err_count = err_count + 1;
        end
        if (err_count == 0) $display("  [OK]  T5 neighbors intact");

        //----------------------------------------------------------
        if (err_count == 0)
            $display("\nPASS: axi_dwidth_converter all tests passed");
        else
            $display("\nFAIL: %0d errors", err_count);
        $finish;
    end

    // 仿真看门狗
    initial begin
        #200us;
        $display("FAIL: timeout");
        $finish;
    end

endmodule

`default_nettype wire
