`default_nettype none
`timescale 1ns / 1ps

//============================================================================
// 模块名称: axi_dwidth_converter
// 功能描述: AXI4 数据位宽转换器（narrow manager ↔ wide subordinate）。
//           把 SoC 32-bit AXI4 主口适配到 DDR 512-bit AXI4 从口：
//             · 写通道：聚集 RATIO 个 narrow W 节拍 → 1 个 wide W 节拍
//                       （WDATA 按 dword 偏移拼装到 wide 累加器；WSTRB 合并；
//                        地址对齐到 wide-word 边界后下发）
//             · 读通道：1 个 wide R 节拍 → 拆分成 narrow R 节拍序列
//                       （按 ARADDR 偏移选择起始 dword，顺序返回 ARLEN+1 拍）
//             · AW/AR 的 len/size/addr 经翻译后下发；B/R 的 id 用 manager
//               原始 id 返回（converter 是 1:1 事务映射，不依赖 sub id）
// 接口说明: AXI4 (M_DW=32 / S_DW=512)，单时钟 clk_i 同时驱动两侧。
// 设计约束:
//   · 单时钟 aclk = clk_i；rst_n_i 异步低，已由调用方同步释放（RTL Rules §4）。
//   · CDC（sys_clk ↔ mem_clk）不在本模块处理 —— 现网 Stage 1~4 的 SoC↔DDR
//     连接已是单时钟假设（顶层原 assign 桥接），本模块保持同一假设。
//     若 sys_clk 与 mem_clk 不同源，需在两侧外接 async AXI FIFO（后续工作，
//     见 docs/设计说明书.md §5.4 备注）。
//   · 假设 manager 突发不跨 wide-word 边界（RATIO=16 → 64 字节对齐）。
//     Sapphire SoC cache line 读写满足此约束（设计说明书 §5.4）。
//   · AWSIZE/ARSIZE 翻译：manager 2 (4B) → subordinate 6 (64B)。
//============================================================================
module axi_dwidth_converter #(
    parameter M_DW   = 32,    // manager 数据位宽（narrow）
    parameter S_DW   = 512,   // subordinate 数据位宽（wide）
    parameter M_AW   = 32,    // manager 地址位宽
    parameter S_AW   = 33,    // subordinate 地址位宽（≥ M_AW，高位零扩展）
    parameter M_IDW  = 8,     // manager ID 位宽
    parameter S_IDW  = 6      // subordinate ID 位宽
)(
    input  wire                  clk_i,
    input  wire                  rst_n_i,

    //======== AXI4 Manager (narrow, SoC 侧) ========
    // 写地址通道
    input  wire [M_IDW-1:0]      m_axi_awid_i,
    input  wire [M_AW-1:0]       m_axi_awaddr_i,
    input  wire [7:0]            m_axi_awlen_i,
    input  wire [2:0]            m_axi_awsize_i,
    input  wire [1:0]            m_axi_awburst_i,
    input  wire                  m_axi_awlock_i,
    input  wire [3:0]            m_axi_awcache_i,
    input  wire [2:0]            m_axi_awprot_i,
    input  wire [3:0]            m_axi_awqos_i,
    input  wire                  m_axi_awvalid_i,
    output wire                  m_axi_awready_o,
    // 写数据通道
    input  wire [M_DW-1:0]       m_axi_wdata_i,
    input  wire [M_DW/8-1:0]     m_axi_wstrb_i,
    input  wire                  m_axi_wlast_i,
    input  wire                  m_axi_wvalid_i,
    output wire                  m_axi_wready_o,
    // 写响应通道
    output wire [M_IDW-1:0]      m_axi_bid_o,
    output wire [1:0]            m_axi_bresp_o,
    output wire                  m_axi_bvalid_o,
    input  wire                  m_axi_bready_i,
    // 读地址通道
    input  wire [M_IDW-1:0]      m_axi_arid_i,
    input  wire [M_AW-1:0]       m_axi_araddr_i,
    input  wire [7:0]            m_axi_arlen_i,
    input  wire [2:0]            m_axi_arsize_i,
    input  wire [1:0]            m_axi_arburst_i,
    input  wire                  m_axi_arlock_i,
    input  wire [3:0]            m_axi_arcache_i,
    input  wire [2:0]            m_axi_arprot_i,
    input  wire [3:0]            m_axi_arqos_i,
    input  wire                  m_axi_arvalid_i,
    output wire                  m_axi_arready_o,
    // 读数据通道
    output wire [M_IDW-1:0]      m_axi_rid_o,
    output wire [M_DW-1:0]       m_axi_rdata_o,
    output wire [1:0]            m_axi_rresp_o,
    output wire                  m_axi_rlast_o,
    output wire                  m_axi_rvalid_o,
    input  wire                  m_axi_rready_i,

    //======== AXI4 Subordinate (wide, DDR 侧) ========
    // 写地址通道
    output wire [S_IDW-1:0]      s_axi_awid_o,
    output wire [S_AW-1:0]       s_axi_awaddr_o,
    output wire [7:0]            s_axi_awlen_o,
    output wire [2:0]            s_axi_awsize_o,
    output wire [1:0]            s_axi_awburst_o,
    output wire                  s_axi_awlock_o,
    output wire [3:0]            s_axi_awcache_o,
    output wire [2:0]            s_axi_awprot_o,
    output wire [3:0]            s_axi_awqos_o,
    output wire                  s_axi_awvalid_o,
    input  wire                  s_axi_awready_i,
    // 写数据通道
    output wire [S_DW-1:0]       s_axi_wdata_o,
    output wire [S_DW/8-1:0]     s_axi_wstrb_o,
    output wire                  s_axi_wlast_o,
    output wire                  s_axi_wvalid_o,
    input  wire                  s_axi_wready_i,
    // 写响应通道
    input  wire [S_IDW-1:0]      s_axi_bid_i,
    input  wire [1:0]            s_axi_bresp_i,
    input  wire                  s_axi_bvalid_i,
    output wire                  s_axi_bready_o,
    // 读地址通道
    output wire [S_IDW-1:0]      s_axi_arid_o,
    output wire [S_AW-1:0]       s_axi_araddr_o,
    output wire [7:0]            s_axi_arlen_o,
    output wire [2:0]            s_axi_arsize_o,
    output wire [1:0]            s_axi_arburst_o,
    output wire                  s_axi_arlock_o,
    output wire [3:0]            s_axi_arcache_o,
    output wire [2:0]            s_axi_arprot_o,
    output wire [3:0]            s_axi_arqos_o,
    output wire                  s_axi_arvalid_o,
    input  wire                  s_axi_arready_i,
    // 读数据通道
    input  wire [S_IDW-1:0]      s_axi_rid_i,
    input  wire [S_DW-1:0]       s_axi_rdata_i,
    input  wire [1:0]            s_axi_rresp_i,
    input  wire                  s_axi_rlast_i,
    input  wire                  s_axi_rvalid_i,
    output wire                  s_axi_rready_o
);

    //==================================================================
    // 局部参数
    //==================================================================
    localparam integer RATIO       = S_DW / M_DW;             // 16 narrow beats / wide beat
    localparam integer BEAT_BITS   = $clog2(RATIO);           // 4
    localparam integer BYTE_BITS_S = $clog2(S_DW/8);          // 6  (wide-word 内字节地址位宽)
    localparam integer BYTE_BITS_M = $clog2(M_DW/8);          // 2  (narrow-word 内字节地址位宽)
    localparam integer M_STRB      = M_DW/8;                  // 4
    localparam [2:0]  S_XSIZE      = BYTE_BITS_S[2:0];        // subordinate SIZE = 6

    //==================================================================
    // 写通道 FSM（one-hot）
    //   W_IDLE → W_AW（发 wide AW）→ W_ACC（聚集 narrow W）→ W_W（发 wide W）
    //          → W_B（等 wide B，回 narrow B）→ W_IDLE
   //==================================================================
    (* fsm_encoding = "one-hot" *) reg [4:0] wstate;
    localparam [4:0] W_IDLE = 5'b00001;
    localparam [4:0] W_AW   = 5'b00010;
    localparam [4:0] W_ACC  = 5'b00100;
    localparam [4:0] W_W    = 5'b01000;
    localparam [4:0] W_B    = 5'b10000;

    // 锁存的 manager AW 字段
    reg [M_IDW-1:0]   aw_id_r;
    reg [M_AW-1:0]    aw_addr_r;
    reg [1:0]         aw_burst_r;
    reg               aw_lock_r;
    reg [3:0]         aw_cache_r;
    reg [2:0]         aw_prot_r;
    reg [3:0]         aw_qos_r;

    // wide-word 内起始 dword 偏移（来自 aw_addr_r）
    wire [BEAT_BITS-1:0] aw_start_off = aw_addr_r[BYTE_BITS_S-1:BYTE_BITS_M];

    // W 数据/STRB 累加器（直接驱动 subordinate wide W，组合输出）
    reg [S_DW-1:0]      wdata_accum;
    reg [S_DW/8-1:0]    wstrb_accum;
    reg [BEAT_BITS:0]   wbeat_cnt;          // 0..RATIO（多 1 bit 容纳 RATIO）

    // 当前 narrow W 节拍在 wide-word 中的 dword 索引
    wire [BEAT_BITS-1:0] cur_dword_idx = aw_start_off + wbeat_cnt[BEAT_BITS-1:0];

    // 写通道寄存器输出
    reg                 m_awready_r;
    reg                 m_wready_r;
    reg [M_IDW-1:0]     m_bid_r;
    reg [1:0]           m_bresp_r;
    reg                 m_bvalid_r;
    reg [S_IDW-1:0]     s_awid_r;
    reg [S_AW-1:0]      s_awaddr_r;
    reg [7:0]           s_awlen_r;
    reg [2:0]           s_awsize_r;
    reg [1:0]           s_awburst_r;
    reg                 s_awlock_r;
    reg [3:0]           s_awcache_r;
    reg [2:0]           s_awprot_r;
    reg [3:0]           s_awqos_r;
    reg                 s_awvalid_r;
    reg                 s_wlast_r;
    reg                 s_wvalid_r;
    reg                 s_bready_r;

    integer i;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            wstate       <= W_IDLE;
            wbeat_cnt    <= {(BEAT_BITS+1){1'b0}};
            wdata_accum  <= {S_DW{1'b0}};
            wstrb_accum  <= {(S_DW/8){1'b0}};
            m_awready_r  <= 1'b0;
            m_wready_r   <= 1'b0;
            m_bid_r      <= {M_IDW{1'b0}};
            m_bresp_r    <= 2'b00;
            m_bvalid_r   <= 1'b0;
            s_awid_r     <= {S_IDW{1'b0}};
            s_awaddr_r   <= {S_AW{1'b0}};
            s_awlen_r    <= 8'd0;
            s_awsize_r   <= 3'd0;
            s_awburst_r  <= 2'b00;
            s_awlock_r   <= 1'b0;
            s_awcache_r  <= 4'b0000;
            s_awprot_r   <= 3'b000;
            s_awqos_r    <= 4'b0000;
            s_awvalid_r  <= 1'b0;
            s_wlast_r    <= 1'b0;
            s_wvalid_r   <= 1'b0;
            s_bready_r   <= 1'b0;
        end else begin
            // 默认值（脉冲类输出每拍归零，电平类由状态机显式管理）
            m_awready_r <= 1'b0;
            m_wready_r  <= 1'b0;
            s_bready_r  <= 1'b0;

            case (wstate)
                //------------------------------------------------------
                W_IDLE: begin
                    if (m_axi_awvalid_i) begin
                        // 锁存 AW 字段
                        aw_id_r     <= m_axi_awid_i;
                        aw_addr_r   <= m_axi_awaddr_i;
                        aw_burst_r  <= m_axi_awburst_i;
                        aw_lock_r   <= m_axi_awlock_i;
                        aw_cache_r  <= m_axi_awcache_i;
                        aw_prot_r   <= m_axi_awprot_i;
                        aw_qos_r    <= m_axi_awqos_i;
                        // 准备 wide AW（地址对齐到 wide-word 边界）
                        s_awid_r    <= m_axi_awid_i[S_IDW-1:0];
                        s_awaddr_r  <= {{(S_AW-M_AW){1'b0}},
                                        {m_axi_awaddr_i[M_AW-1:BYTE_BITS_S], {BYTE_BITS_S{1'b0}}}};
                        s_awlen_r   <= 8'd0;                 // 1 个 wide 节拍
                        s_awsize_r  <= S_XSIZE;              // 6 = 64 字节
                        s_awburst_r <= m_axi_awburst_i;      // 透传（应为 INCR）
                        s_awlock_r  <= m_axi_awlock_i;
                        s_awcache_r <= m_axi_awcache_i;
                        s_awprot_r  <= m_axi_awprot_i;
                        s_awqos_r   <= m_axi_awqos_i;
                        s_awvalid_r <= 1'b1;
                        m_awready_r <= 1'b1;                 // 同拍接收 manager AW
                        wbeat_cnt   <= {(BEAT_BITS+1){1'b0}};
                        wdata_accum <= {S_DW{1'b0}};
                        wstrb_accum <= {(S_DW/8){1'b0}};
                        wstate      <= W_AW;
                    end
                end
                //------------------------------------------------------
                W_AW: begin
                    if (s_axi_awready_i) begin
                        s_awvalid_r <= 1'b0;
                        wstate      <= W_ACC;
                    end
                end
                //------------------------------------------------------
                W_ACC: begin
                    // 接受 narrow W 节拍，按 dword 偏移拼装到累加器
                    if (m_axi_wvalid_i) begin
                        m_wready_r <= 1'b1;
                        wdata_accum[cur_dword_idx*M_DW +: M_DW] <= m_axi_wdata_i;
                        for (i = 0; i < M_STRB; i = i + 1) begin
                            wstrb_accum[cur_dword_idx*M_STRB + i] <= m_axi_wstrb_i[i];
                        end
                        if (m_axi_wlast_i || (wbeat_cnt == RATIO-1)) begin
                            // 累加完成 —— 进入 W_W（累加器值下一拍生效，W_W 中组合输出）
                            s_wlast_r  <= 1'b1;
                            s_wvalid_r <= 1'b1;
                            wstate     <= W_W;
                        end else begin
                            wbeat_cnt <= wbeat_cnt + 1'b1;
                        end
                    end
                end
                //------------------------------------------------------
                // 注：从 W_ACC 跳到 W_W 是同一拍内 NBA，故 W_W 第一拍看到的
                //     wdata_accum 已含最后一拍数据（NBA 在本时钟沿更新）。
                W_W: begin
                    if (s_axi_wready_i) begin
                        s_wvalid_r <= 1'b0;
                        s_wlast_r  <= 1'b0;
                        s_bready_r <= 1'b1;        // 准备接收 wide B
                        wstate     <= W_B;
                    end
                end
                //------------------------------------------------------
                W_B: begin
                    s_bready_r <= 1'b1;            // 持续声明 ready 直到收到 B
                    if (s_axi_bvalid_i) begin
                        m_bid_r    <= aw_id_r;     // 用 manager 原始 id
                        m_bresp_r  <= s_axi_bresp_i;
                        m_bvalid_r <= 1'b1;
                        wstate     <= W_IDLE;
                    end
                end
                //------------------------------------------------------
                default: wstate <= W_IDLE;
            endcase

            // manager 取走 B 后清 m_bvalid
            if (m_bvalid_r && m_axi_bready_i)
                m_bvalid_r <= 1'b0;
        end
    end

    //==================================================================
    // 读通道 FSM（one-hot）
    //   R_IDLE → R_AR（发 wide AR）→ R_FETCH（收 wide R，开拆 narrow R）
    //          → 继续 R_FETCH 返回剩余 narrow R → R_IDLE
    //==================================================================
    (* fsm_encoding = "one-hot" *) reg [2:0] rstate;
    localparam [2:0] R_IDLE    = 3'b001;
    localparam [2:0] R_AR      = 3'b010;
    localparam [2:0] R_FETCH   = 3'b100;

    // 锁存的 manager AR 字段
    reg [M_IDW-1:0]   ar_id_r;
    reg [1:0]         ar_burst_r;
    reg               ar_lock_r;
    reg [3:0]         ar_cache_r;
    reg [2:0]         ar_prot_r;
    reg [3:0]         ar_qos_r;

    // 拆分 narrow R 计数
    reg [BEAT_BITS:0]   rbeat_cnt;          // 已返回 narrow 节拍数
    reg [8:0]           rbeats_total;       // 待返回 narrow 节拍总数 = ARLEN+1
    reg [BEAT_BITS-1:0] rstart_off;         // 起始 dword 偏移
    reg [S_DW-1:0]      rdata_held;         // 锁存的 wide RDATA
    reg [1:0]           rresp_held;
    reg                 rheld_valid;        // wide R 已捕获

    // 当前返回的 dword 索引（rdata_held 的 32-bit 切片）
    wire [BEAT_BITS-1:0] rcur_dword = rstart_off + rbeat_cnt[BEAT_BITS-1:0];

    // 读通道寄存器输出
    reg                 m_arready_r;
    reg [M_IDW-1:0]     m_rid_r;
    reg [1:0]           m_rresp_r;
    reg                 m_rlast_r;
    reg                 m_rvalid_r;
    reg [S_IDW-1:0]     s_arid_r;
    reg [S_AW-1:0]      s_araddr_r;
    reg [7:0]           s_arlen_r;
    reg [2:0]           s_arsize_r;
    reg [1:0]           s_arburst_r;
    reg                 s_arlock_r;
    reg [3:0]           s_arcache_r;
    reg [2:0]           s_arprot_r;
    reg [3:0]           s_arqos_r;
    reg                 s_arvalid_r;
    reg                 s_rready_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            rstate       <= R_IDLE;
            rbeat_cnt    <= {(BEAT_BITS+1){1'b0}};
            rbeats_total <= 9'd0;
            rstart_off   <= {BEAT_BITS{1'b0}};
            rdata_held   <= {S_DW{1'b0}};
            rresp_held   <= 2'b00;
            rheld_valid  <= 1'b0;
            m_arready_r  <= 1'b0;
            m_rid_r      <= {M_IDW{1'b0}};
            m_rresp_r    <= 2'b00;
            m_rlast_r    <= 1'b0;
            m_rvalid_r   <= 1'b0;
            s_arid_r     <= {S_IDW{1'b0}};
            s_araddr_r   <= {S_AW{1'b0}};
            s_arlen_r    <= 8'd0;
            s_arsize_r   <= 3'd0;
            s_arburst_r  <= 2'b00;
            s_arlock_r   <= 1'b0;
            s_arcache_r  <= 4'b0000;
            s_arprot_r   <= 3'b000;
            s_arqos_r    <= 4'b0000;
            s_arvalid_r  <= 1'b0;
            s_rready_r   <= 1'b0;
        end else begin
            // 默认值
            m_arready_r <= 1'b0;

            case (rstate)
                //------------------------------------------------------
                R_IDLE: begin
                    if (m_axi_arvalid_i) begin
                        ar_id_r     <= m_axi_arid_i;
                        ar_burst_r  <= m_axi_arburst_i;
                        ar_lock_r   <= m_axi_arlock_i;
                        ar_cache_r  <= m_axi_arcache_i;
                        ar_prot_r   <= m_axi_arprot_i;
                        ar_qos_r    <= m_axi_arqos_i;

                        s_arid_r    <= m_axi_arid_i[S_IDW-1:0];
                        s_araddr_r  <= {{(S_AW-M_AW){1'b0}},
                                        {m_axi_araddr_i[M_AW-1:BYTE_BITS_S], {BYTE_BITS_S{1'b0}}}};
                        s_arlen_r   <= 8'd0;                 // 1 个 wide 节拍
                        s_arsize_r  <= S_XSIZE;
                        s_arburst_r <= m_axi_arburst_i;
                        s_arlock_r  <= m_axi_arlock_i;
                        s_arcache_r <= m_axi_arcache_i;
                        s_arprot_r  <= m_axi_arprot_i;
                        s_arqos_r   <= m_axi_arqos_i;
                        s_arvalid_r <= 1'b1;
                        m_arready_r <= 1'b1;

                        rstart_off   <= m_axi_araddr_i[BYTE_BITS_S-1:BYTE_BITS_M];
                        rbeats_total <= m_axi_arlen_i + 9'd1;
                        rbeat_cnt    <= {(BEAT_BITS+1){1'b0}};
                        rheld_valid  <= 1'b0;
                        rstate       <= R_AR;
                    end
                end
                //------------------------------------------------------
                R_AR: begin
                    if (s_axi_arready_i) begin
                        s_arvalid_r <= 1'b0;
                        s_rready_r  <= 1'b1;        // 声明收 wide R
                        rstate      <= R_FETCH;
                    end
                end
                //------------------------------------------------------
                R_FETCH: begin
                    if (!rheld_valid) begin
                        // 首次：等 wide R，捕获后呈现第 0 拍 narrow R
                        s_rready_r <= 1'b1;
                        if (s_axi_rvalid_i) begin
                            rdata_held  <= s_axi_rdata_i;
                            rresp_held  <= s_axi_rresp_i;
                            rheld_valid <= 1'b1;
                            s_rready_r  <= 1'b0;    // wide R 只收一拍
                            rbeat_cnt   <= {(BEAT_BITS+1){1'b0}};   // 当前呈现 beat 0
                            m_rid_r     <= ar_id_r;
                            m_rresp_r   <= s_axi_rresp_i;
                            m_rlast_r   <= (rbeats_total == 9'd1);
                            m_rvalid_r  <= 1'b1;
                        end
                    end else begin
                        // wide R 已捕获，beat 正在呈现；被 manager 接收后推进
                        if (m_rvalid_r && m_axi_rready_i) begin
                            if ((rbeat_cnt + 9'd1) < rbeats_total) begin
                                // 还有下一拍 —— rbeat_cnt 即"当前呈现的 beat 索引"
                                rbeat_cnt <= rbeat_cnt + 1'b1;
                                m_rid_r   <= ar_id_r;
                                m_rresp_r <= rresp_held;
                                m_rlast_r <= ((rbeat_cnt + 9'd2) == rbeats_total);
                                // m_rvalid_r 保持 1
                            end else begin
                                // 最后一拍已被接收，事务完成
                                m_rvalid_r  <= 1'b0;
                                rheld_valid <= 1'b0;
                                rstate      <= R_IDLE;
                            end
                        end
                    end
                end
                //------------------------------------------------------
                default: rstate <= R_IDLE;
            endcase
        end
    end

    //==================================================================
    // 输出驱动
    //==================================================================
    // --- Manager 侧 ---
    assign m_axi_awready_o = m_awready_r;
    assign m_axi_wready_o  = m_wready_r;
    assign m_axi_bid_o     = m_bid_r;
    assign m_axi_bresp_o   = m_bresp_r;
    assign m_axi_bvalid_o  = m_bvalid_r;
    assign m_axi_arready_o = m_arready_r;
    assign m_axi_rid_o     = m_rid_r;
    assign m_axi_rdata_o   = rdata_held[rcur_dword*M_DW +: M_DW];
    assign m_axi_rresp_o   = m_rresp_r;
    assign m_axi_rlast_o   = m_rlast_r;
    assign m_axi_rvalid_o  = m_rvalid_r;

    // --- Subordinate 侧 ---
    assign s_axi_awid_o    = s_awid_r;
    assign s_axi_awaddr_o  = s_awaddr_r;
    assign s_axi_awlen_o   = s_awlen_r;
    assign s_axi_awsize_o  = s_awsize_r;
    assign s_axi_awburst_o = s_awburst_r;
    assign s_axi_awlock_o  = s_awlock_r;
    assign s_axi_awcache_o = s_awcache_r;
    assign s_axi_awprot_o  = s_awprot_r;
    assign s_axi_awqos_o   = s_awqos_r;
    assign s_axi_awvalid_o = s_awvalid_r;
    // wide W 数据/STRB 直接来自累加器（仅在 W_W 状态 s_wvalid_r=1 时被 subordinate 采样）
    assign s_axi_wdata_o   = wdata_accum;
    assign s_axi_wstrb_o   = wstrb_accum;
    assign s_axi_wlast_o   = s_wlast_r;
    assign s_axi_wvalid_o  = s_wvalid_r;
    assign s_axi_bready_o  = s_bready_r;
    assign s_axi_arid_o    = s_arid_r;
    assign s_axi_araddr_o  = s_araddr_r;
    assign s_axi_arlen_o   = s_arlen_r;
    assign s_axi_arsize_o  = s_arsize_r;
    assign s_axi_arburst_o = s_arburst_r;
    assign s_axi_arlock_o  = s_arlock_r;
    assign s_axi_arcache_o = s_arcache_r;
    assign s_axi_arprot_o  = s_arprot_r;
    assign s_axi_arqos_o   = s_arqos_r;
    assign s_axi_arvalid_o = s_arvalid_r;
    assign s_axi_rready_o  = s_rready_r;

    // 抑制未用信号告警：subordinate 返回的 id 不被使用（converter 用 manager id 回送）
    wire _unused_sok = &{1'b0, s_axi_bid_i, s_axi_rid_i,
                         m_axi_awsize_i, m_axi_arsize_i, 1'b0};

endmodule

`default_nettype wire
