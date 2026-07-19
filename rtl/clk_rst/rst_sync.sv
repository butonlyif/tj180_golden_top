`default_nettype none
`timescale 1ns / 1ps

//============================================================================
// 模块名称: rst_sync
// 功能描述: 异步复位，同步释放（3 级），每时钟域独立例化
// 接口说明: 输入异步 rst_n_i，输出同步 rst_n_o
// 设计约束: ASYNC_REG 属性防止优化，STAGES 参数可配置（默认 3）
//============================================================================
module rst_sync #(
    parameter STAGES = 3
)(
    input  wire clk_i,
    input  wire rst_n_i,      // 异步复位，低有效
    output wire rst_n_o       // 同步释放后复位
);

    (* ASYNC_REG = "TRUE" *) reg [STAGES-1:0] sync_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            sync_r <= {STAGES{1'b0}};
        else
            sync_r <= {sync_r[STAGES-2:0], 1'b1};
    end

    assign rst_n_o = sync_r[STAGES-1];

endmodule

`default_nettype wire
