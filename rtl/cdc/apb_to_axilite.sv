`default_nettype none
`timescale 1ns / 1ps

//============================================================================
// 模块名称: apb_to_axilite
// 功能描述: APB3 Slave → AXI4-Lite Master 单点桥。
//           把 SoC 的 APB Slave 0 协议翻译成 AXI4-Lite，供 CSI RX/TX
//           配置寄存器使用。两侧同处 sys_clk 域（无 CDC）。
// 接口说明: APB3 (16-bit addr / 32-bit data) → AXI4-Lite (AW 位地址)
// 设计约束: 单笔交易：APB ACCESS 触发 AXI AW+W (写) 或 AR (读)；
//           AXI B/R 完成握手后回 pready。
//============================================================================
module apb_to_axilite #(
    parameter AW = 6,            // AXI-Lite 地址位宽（CSI RX regmap = 6）
    parameter DW = 32            // 数据位宽
)(
    input  wire              clk_i,
    input  wire              rst_n_i,

    // -- APB3 Slave (来自 SoC) --
    input  wire [15:0]       apb_paddr_i,
    input  wire              apb_psel_i,
    input  wire              apb_penable_i,
    input  wire              apb_pwrite_i,
    input  wire [DW-1:0]     apb_pwdata_i,
    output wire [DW-1:0]     apb_prdata_o,
    output wire              apb_pready_o,
    output wire              apb_pslverror_o,

    // -- AXI4-Lite Master (去 CSI) --
    output wire [AW-1:0]     axi_awaddr_o,
    output wire              axi_awvalid_o,
    input  wire              axi_awready_i,
    output wire [DW-1:0]     axi_wdata_o,
    output wire [DW/8-1:0]   axi_wstrb_o,
    output wire              axi_wvalid_o,
    input  wire              axi_wready_i,
    input  wire              axi_bvalid_i,
    output wire              axi_bready_o,
    output wire [AW-1:0]     axi_araddr_o,
    output wire              axi_arvalid_o,
    input  wire              axi_arready_i,
    output wire              axi_rready_o,
    input  wire              axi_rvalid_i,
    input  wire [DW-1:0]     axi_rdata_i
);

    //==================================================================
    // FSM 状态（one-hot 编码）
    //==================================================================
    localparam [4:0] ST_IDLE     = 5'b00001;
    localparam [4:0] ST_W_ADDR   = 5'b00010; // 写：AW+W 同发
    localparam [4:0] ST_W_RESP   = 5'b00100; // 写：等 B
    localparam [4:0] ST_R_ADDR   = 5'b01000; // 读：发 AR
    localparam [4:0] ST_R_DATA   = 5'b10000; // 读：等 R

    (* fsm_encoding = "one-hot" *) reg [4:0] st;
    reg [4:0] st_next;

    // -- 捕获 APB setup 阶段信息 --
    reg [15:0]   addr_lat;
    reg [DW-1:0] wdata_lat;

    // -- R 通道读回缓冲 --
    reg [DW-1:0] rdata_lat;

    // -- pready / prdata 组合输出 --
    reg          pready_c;
    reg [DW-1:0] prdata_c;

    //==================================================================
    // 寄存器更新
    //==================================================================
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            st        <= ST_IDLE;
            addr_lat  <= 16'h0;
            wdata_lat <= {DW{1'b0}};
            rdata_lat <= {DW{1'b0}};
        end else begin
            st <= st_next;

            // 在 IDLE 拍且 APB ACCESS 抬起时，捕获本次访问信息
            if (st == ST_IDLE && apb_psel_i && apb_penable_i) begin
                addr_lat  <= apb_paddr_i;
                wdata_lat <= apb_pwdata_i;
            end

            // R 通道：在 ST_R_DATA 拍采样读回数据
            if (st == ST_R_DATA && axi_rvalid_i) begin
                rdata_lat <= axi_rdata_i;
            end
        end
    end

    //==================================================================
    // 组合下一状态 + pready/prdata
    //==================================================================
    always @(*) begin
        // 顶部默认
        st_next  = st;
        pready_c = 1'b0;
        prdata_c = rdata_lat;

        case (st)
            ST_IDLE: begin
                if (apb_psel_i && apb_penable_i) begin
                    if (apb_pwrite_i)
                        st_next = ST_W_ADDR;
                    else
                        st_next = ST_R_ADDR;
                end
            end

            ST_W_ADDR: begin
                // AW+W 握手完成 (awready ∧ wready 同时拉高) 后进入响应等待
                if (axi_awready_i && axi_wready_i)
                    st_next = ST_W_RESP;
            end

            ST_W_RESP: begin
                if (axi_bvalid_i) begin
                    st_next  = ST_IDLE;
                    pready_c = 1'b1;       // 同拍回 APB ready
                end
            end

            ST_R_ADDR: begin
                // AR 握手完成 (arready 拉高) 后进入数据等待
                if (axi_arready_i)
                    st_next = ST_R_DATA;
            end

            ST_R_DATA: begin
                if (axi_rvalid_i) begin
                    st_next  = ST_IDLE;
                    pready_c = 1'b1;
                    prdata_c = axi_rdata_i;
                end
            end

            default: st_next = ST_IDLE;
        endcase
    end

    //==================================================================
    // AXI-Lite 输出
    //==================================================================
    // 字地址对齐：APB paddr 是字节地址，转字地址 (右移 2) 后取低 AW 位
    wire [AW-1:0] addr_word = addr_lat[AW+1:2];

    assign axi_awaddr_o  = addr_word;
    assign axi_awvalid_o = (st == ST_W_ADDR);
    assign axi_wdata_o   = wdata_lat;
    assign axi_wstrb_o   = {{(DW/8){1'b1}}};
    assign axi_wvalid_o  = (st == ST_W_ADDR);
    assign axi_bready_o  = 1'b1;             // 始终接受 B

    assign axi_araddr_o  = addr_word;
    assign axi_arvalid_o = (st == ST_R_ADDR);
    assign axi_rready_o  = 1'b1;             // 始终接受 R

    //==================================================================
    // APB 返回
    //==================================================================
    assign apb_pready_o    = pready_c;
    assign apb_prdata_o    = prdata_c;
    assign apb_pslverror_o = 1'b0;

endmodule

`default_nettype wire
