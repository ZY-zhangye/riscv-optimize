`include "defines.svh"
module wb_stage (
    input logic clk,
    input logic rst_n,
    //来自内存阶段的信息
    input logic [`MS_WS_WIDTH-1:0] ms_to_ws_bus,
    //握手信号
    input logic ms_to_ws_valid,
    output logic ws_allowin,
    //送到寄存器堆的信息
    output logic regfile_wen,
    output logic [4:0] regfile_addr,
    output logic [31:0] regfile_wdata
    //debug接口
    `ifdef DEBUG_EN
    ,
    output logic [31:0] debug_wb_pc,
    output logic [4:0] debug_wb_rf_addr,
    output logic [31:0] debug_wb_rf_data,
    output logic debug_wb_rf_wen
    `endif
);

    logic ws_ready_go;
    logic ws_valid;
    assign ws_ready_go = 1'b1;
    assign ws_allowin = !ws_valid || ws_ready_go && ms_to_ws_valid;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ws_valid <= 1'b0;
        end else if (ws_allowin) begin
            ws_valid <= ms_to_ws_valid;
        end
    end

    logic [`MS_WS_WIDTH-1:0] ms_ws_bus_r;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ms_ws_bus_r <= '0;
        end else if (ms_to_ws_valid && ws_allowin) begin
            ms_ws_bus_r <= ms_to_ws_bus;
        end
    end

    //解析来自内存阶段的信息
    logic [31:0] wb_result;
    logic [4:0] wb_dst_addr;
    logic [31:0] wb_pc;
    logic wb_regfile_wen;
    assign {wb_pc, wb_result, wb_dst_addr, wb_regfile_wen} = ms_ws_bus_r;

    //使用写回端口仲裁器（单发射：直接透传，双发射时处理冲突）
    logic stall_1;
    write_port_arbiter u_write_port_arbiter (
        .wb_wen_0(wb_regfile_wen),
        .wb_addr_0(wb_dst_addr),
        .wb_data_0(wb_result),
        .wb_wen_1(1'b0),           // 单发射模式下第二指令无
        .wb_addr_1(5'b0),
        .wb_data_1(32'b0),
        .regfile_wen(regfile_wen),
        .regfile_waddr(regfile_addr),
        .regfile_wdata(regfile_wdata),
        .stall_1(stall_1)
    );
    `ifdef DEBUG_EN
    assign debug_wb_pc = wb_pc;
    assign debug_wb_rf_addr = wb_dst_addr;
    assign debug_wb_rf_data = wb_result;
    assign debug_wb_rf_wen = wb_regfile_wen;
    `endif

endmodule
