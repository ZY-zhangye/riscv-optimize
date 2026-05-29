`include "defines.svh"

// 写回端口仲裁器
// 在双发射时处理两条指令对寄存器文件的写端口冲突
// 目前单发射模式下直接透传，为双发射预留
module write_port_arbiter (
    input logic wb_wen_0,              // 第一条指令写使能
    input logic [4:0] wb_addr_0,       // 第一条指令写地址
    input logic [31:0] wb_data_0,      // 第一条指令写数据

    input logic wb_wen_1,              // 第二条指令写使能（双发射）
    input logic [4:0] wb_addr_1,       // 第二条指令写地址（双发射）
    input logic [31:0] wb_data_1,      // 第二条指令写数据（双发射）

    output logic regfile_wen,          // 最终写使能
    output logic [4:0] regfile_waddr,  // 最终写地址
    output logic [31:0] regfile_wdata, // 最终写数据
    output logic stall_1               // 第二条指令是否需要停顿
);

    // 单发射模式：直接使用第一条指令
    // 双发射时需要处理冲突：
    // - 如果两条指令写同一寄存器，第二条指令停顿
    // - 否则需要分离写操作（需要多个写端口）

    logic conflict;
    assign conflict = wb_wen_0 && wb_wen_1 && (wb_addr_0 == wb_addr_1) && (wb_addr_0 != 5'b0);

    always_comb begin
        // Lane0 has priority (older instruction). If lane0 doesn't write,
        // lane1's write passes through.
        if (wb_wen_0) begin
            regfile_wen   = wb_wen_0;
            regfile_waddr = wb_addr_0;
            regfile_wdata = wb_data_0;
            stall_1 = conflict;
        end else if (wb_wen_1) begin
            regfile_wen   = wb_wen_1;
            regfile_waddr = wb_addr_1;
            regfile_wdata = wb_data_1;
            stall_1 = 1'b0;
        end else begin
            regfile_wen   = 1'b0;
            regfile_waddr = 5'b0;
            regfile_wdata = 32'b0;
            stall_1 = 1'b0;
        end
    end

endmodule : write_port_arbiter
