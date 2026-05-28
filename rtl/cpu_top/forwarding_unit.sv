`include "defines.svh"

// 数据前递选择单元
// 在EXE阶段使用，根据前递信号选择正确的操作数
module forwarding_unit (
    input logic [31:0] reg_src1,         // 来自寄存器文件的rs1数据
    input logic [31:0] reg_src2,         // 来自寄存器文件的rs2数据
    input logic [31:0] exe_result_reg,   // EXE阶段结果（前递源1）
    input logic [31:0] mem_result_reg,   // MEM阶段结果（前递源2）
    input logic [1:0] src1_fwd,          // src1前递控制: 00=无 01=EXE 10=MEM
    input logic [1:0] src2_fwd,          // src2前递控制: 00=无 01=EXE 10=MEM

    output logic [31:0] src1,            // 最终选中的src1操作数
    output logic [31:0] src2             // 最终选中的src2操作数
);

    // src1数据选择MUX
    always_comb begin
        src1 = 32'b0;
        unique case (1'b1)
            src1_fwd[0]: src1 = exe_result_reg;  // EXE前递
            src1_fwd[1]: src1 = mem_result_reg;  // MEM前递
            default:     src1 = reg_src1;        // 来自寄存器文件
        endcase
    end

    // src2数据选择MUX
    always_comb begin
        src2 = 32'b0;
        unique case (1'b1)
            src2_fwd[0]: src2 = exe_result_reg;  // EXE前递
            src2_fwd[1]: src2 = mem_result_reg;  // MEM前递
            default:     src2 = reg_src2;        // 来自寄存器文件
        endcase
    end

endmodule : forwarding_unit
